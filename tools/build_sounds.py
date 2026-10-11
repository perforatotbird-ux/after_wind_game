#!/usr/bin/env python3
"""Собирает звуки игры из бесплатных CC0-паков (Kenney, OpenGameArt) и
генерирует недостающие. Результат: OGG-файлы в OUT_DIR, которые затем
tools/import_sounds.gd превращает в текстовые res://assets/audio/*.tres.

Источники ожидаются в SRC (по умолчанию /data/sfx), см. assets/audio/CREDITS.md.
Запуск: python3 tools/build_sounds.py [SRC] [OUT_DIR]
"""
import os, sys, subprocess, glob
import numpy as np

SRC = sys.argv[1] if len(sys.argv) > 1 else "/data/sfx"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/data/sfx_build"
SFX_SR = 32000
AMB_SR = 22050
RNG = np.random.default_rng(1234)

K_IMP = SRC + "/kenney_impact-sounds/Audio/"
K_RPG = SRC + "/kenney_rpg-audio/Audio/"
K_UI = SRC + "/kenney_interface-sounds/Audio/"
K_JIN = SRC + "/kenney_music-jingles/Audio/"
OGA = SRC + "/oga/"


def load(path, sr, start=0.0, dur=None):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start)]
    if dur:
        cmd += ["-t", str(dur)]
    cmd += ["-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def trim(x, thr=0.01, pad=0.004, sr=SFX_SR):
    idx = np.where(np.abs(x) > thr * max(1e-9, np.max(np.abs(x))))[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(pad * sr))
    b = min(len(x), idx[-1] + int(0.02 * sr))
    return x[a:b]


def fade(x, fin=0.003, fout=0.03, sr=SFX_SR):
    x = x.copy()
    ni, no = min(len(x), int(fin * sr)), min(len(x), int(fout * sr))
    if ni > 0:
        x[:ni] *= np.linspace(0, 1, ni)
    if no > 0:
        x[-no:] *= np.linspace(1, 0, no)
    return x


def norm(x, peak_db=-3.0):
    p = np.max(np.abs(x))
    return x if p < 1e-9 else x * (10 ** (peak_db / 20) / p)


def norm_rms(x, rms_db):
    r = np.sqrt(np.mean(x ** 2))
    y = x * (10 ** (rms_db / 20) / max(r, 1e-9))
    p = np.max(np.abs(y))
    return y * (0.95 / p) if p > 0.95 else y


def loopify(x, sr, length, xfade):
    L, X = int(length * sr), int(xfade * sr)
    seg = x[: L + X].copy()
    t = np.linspace(0, np.pi / 2, X)
    out = seg[:L].copy()
    out[:X] = seg[:X] * np.sin(t) + seg[L:L + X] * np.cos(t)
    return out


def write(name, x, sr, q):
    os.makedirs(OUT, exist_ok=True)
    pcm = np.clip(x, -1, 1).astype(np.float32).tobytes()
    path = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", "1",
                    "-i", "-", "-c:a", "libvorbis", "-q:a", str(q), path], input=pcm, check=True)
    return path


def sfx(name, path, peak=-3.0, start=0.0, dur=None, fout=0.03, maxlen=None, thr=0.01):
    x = load(path, SFX_SR, start, dur)
    x = trim(x, thr)
    if maxlen and len(x) > maxlen * SFX_SR:
        x = x[: int(maxlen * SFX_SR)]
        fout = max(fout, 0.08)
    write(name, norm(fade(x, fout=fout), peak), SFX_SR, 3)


# ---------- процедурные (то, чего нет в паках) ----------
def onepole_lp(x, cut_hz, sr):
    """Однополюсный ФНЧ; cut_hz может быть массивом (развёртка)."""
    cut = np.broadcast_to(np.asarray(cut_hz, dtype=np.float64), x.shape)
    a = 1.0 - np.exp(-2 * np.pi * cut / sr)
    y = np.zeros_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def gen_swing(seed, dur=0.32):
    """Свист замаха инструментом: полосовой шум с развёрткой частоты."""
    rng = np.random.default_rng(seed)
    n = int(dur * SFX_SR)
    t = np.linspace(0, 1, n)
    noise = rng.standard_normal(n)
    sweep = 400 + 2600 * np.sin(np.pi * t) ** 2
    band = onepole_lp(noise, sweep, SFX_SR) - onepole_lp(noise, sweep * 0.35, SFX_SR)
    env = np.sin(np.pi * t) ** 1.6
    return norm(fade(band * env, 0.005, 0.03), -6.0)


def gen_crunch(seed, dur=0.42):
    """Хруст при еде: серия коротких отфильтрованных шумовых щелчков."""
    rng = np.random.default_rng(seed)
    n = int(dur * SFX_SR)
    out = np.zeros(n)
    t0 = 0.0
    while t0 < dur - 0.05:
        ln = int(rng.uniform(0.015, 0.045) * SFX_SR)
        st = int(t0 * SFX_SR)
        burst = rng.standard_normal(ln) * np.exp(-np.linspace(0, rng.uniform(4, 8), ln))
        burst = burst - onepole_lp(burst, 700, SFX_SR)  # убираем низ
        burst = onepole_lp(burst, rng.uniform(2500, 5000), SFX_SR)
        end = min(n, st + ln)
        out[st:end] += burst[: end - st] * rng.uniform(0.4, 1.0)
        t0 += rng.uniform(0.03, 0.08)
    env = np.exp(-np.linspace(0, 2.0, n))
    return norm(fade(out * env, 0.002, 0.04), -5.0)


def main():
    # Удары / добыча
    for i, n in enumerate([0, 1, 2, 3]):
        sfx(f"hit_wood_{i}", K_IMP + f"impactWood_heavy_00{n}.ogg", -2)
    sfx("hit_wood_4", K_RPG + "chop.ogg", -2)
    for i in range(5):
        sfx(f"hit_stone_{i}", K_IMP + f"impactMining_00{i}.ogg", -2)
    for i in range(3):
        sfx(f"hit_metal_{i}", K_IMP + f"impactMetal_medium_00{i}.ogg", -4)
    # Копание лопатой / вскапывание
    sfx("dig_0", OGA + "shovel.ogg", -3, maxlen=0.6)
    for i in range(3):
        sfx(f"dig_{i + 1}", K_IMP + f"impactSoft_heavy_00{i}.ogg", -3)
    # Замах (генерируется)
    for i in range(3):
        write(f"swing_{i}", gen_swing(10 + i, 0.28 + 0.04 * i), SFX_SR, 3)
    # Шаги
    for i in range(5):
        sfx(f"footstep_grass_{i}", K_IMP + f"footstep_grass_00{i}.ogg", -9)
    for i in range(5):
        sfx(f"footstep_dirt_{i}", K_RPG + f"footstep0{i}.ogg", -10)
    # Предметы
    for i in range(3):
        sfx(f"pickup_{i}", K_RPG + f"cloth{i + 1}.ogg", -6)
    sfx("drop_0", K_RPG + "dropLeather.ogg", -5)
    sfx("drop_1", K_RPG + "handleSmallLeather.ogg", -5)
    sfx("coins_0", K_RPG + "handleCoins.ogg", -3)
    sfx("coins_1", K_RPG + "handleCoins2.ogg", -3)
    sfx("coins_2", OGA + "80-CC0-RPG-SFX_0/item_coins_01.ogg", -3)
    # Ферма / еда / вода
    sfx("harvest_0", K_UI + "confirmation_002.ogg", -5)
    sfx("berry_pick_0", K_UI + "pluck_001.ogg", -5)
    sfx("berry_pick_1", K_UI + "pluck_002.ogg", -5)
    for i in range(3):
        sfx(f"plant_{i}", K_IMP + f"impactSoft_medium_00{i}.ogg", -5)
    for i, n in enumerate(["02", "03", "08"]):
        sfx(f"water_splash_{i}", OGA + f"water-splash-slime-sfx/splash_{n}.ogg", -4, maxlen=1.2)
    sfx("water_fill_0", OGA + "water-splash-slime-sfx/bubble_01.ogg", -5, maxlen=1.0)
    sfx("drink_0", OGA + "water-splash-slime-sfx/bubble_02.ogg", -6, maxlen=0.8)
    sfx("drink_1", OGA + "water-splash-slime-sfx/bubble_03.ogg", -6, maxlen=0.8)
    for i in range(3):
        write(f"eat_{i}", gen_crunch(20 + i, 0.38 + 0.04 * i), SFX_SR, 3)
    # Станки / стройка
    x = load(OGA + "sfx_loops/machine_01.ogg", SFX_SR, 0.0, 1.6)
    write("machine_start_0", norm(fade(x, 0.12, 0.5), -5), SFX_SR, 3)
    sfx("machine_done_0", K_UI + "confirmation_001.ogg", -5)
    for i in range(3):
        sfx(f"build_{i}", K_IMP + f"impactPlank_medium_00{i}.ogg", -3)
    # Интерфейс
    # click_002..005 — 10-мс тики, слишком тихие/короткие; берём click_001 и мягкие select
    for i, f in enumerate(["click_001", "select_001", "select_002"]):
        sfx(f"ui_click_{i}", K_UI + f + ".ogg", -8)
    sfx("ui_open_0", K_UI + "open_001.ogg", -8)
    sfx("ui_close_0", K_UI + "close_001.ogg", -8)
    sfx("ui_error_0", K_UI + "error_004.ogg", -8)
    # Финал
    x = load(K_JIN + "Sax jingles/jingles_SAX07.ogg", SFX_SR)
    write("victory_fanfare_0", norm(fade(trim(x), 0.002, 0.15), -3), SFX_SR, 4)
    # Эмбиент (бесшовные петли)
    w = load(OGA + "park_ambience_wind.wav", AMB_SR, 20.0, 40.0)
    write("wind_ambient", norm_rms(loopify(w, AMB_SR, 36.0, 3.0), -24), AMB_SR, 0)
    r = load(OGA + "amb_rain_loop_1.ogg", AMB_SR, 5.0, 31.0)
    write("rain_ambient", norm_rms(loopify(r, AMB_SR, 28.0, 2.5), -20), AMB_SR, 0)
    b = load(OGA + "birds-isaiah658_0.ogg", AMB_SR)
    write("birds_ambient", norm_rms(loopify(b, AMB_SR, len(b) / AMB_SR - 2.6, 2.5), -26), AMB_SR, 0)
    total = sum(os.path.getsize(p) for p in glob.glob(OUT + "/*.ogg"))
    print(f"OK: {len(glob.glob(OUT + '/*.ogg'))} files, {total / 1024:.0f} KiB")


if __name__ == "__main__":
    main()
