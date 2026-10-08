"""Тайлящаяся текстура коры для tools/generate_trees.gd.

Пишет .godot/bark_albedo.png (кэш, не в git); generate_trees.gd встраивает её в
материалы коры (оттенки серого, цвет — в albedo_color и цветах вершин).
Запуск из корня проекта: python3 tools/generate_tree_textures.py
"""
import os
import numpy as np
from PIL import Image

N = 512


def fnoise(beta, seed, sx=1.0, sy=1.0):
    """Периодический шум 1/f^beta; sx/sy растягивают спектр (волокна вдоль V)."""
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(N)[:, None] * sy
    fx = np.fft.fftfreq(N)[None, :] * sx
    k = fx ** 2 + fy ** 2
    k[0, 0] = 1
    spec = (r.normal(size=(N, N)) + 1j * r.normal(size=(N, N))) / k ** (beta / 2)
    spec[0, 0] = 0
    n = np.real(np.fft.ifft2(spec))
    return (n - n.mean()) / n.std()


rng = np.random.default_rng(3)
yy, xx = np.mgrid[0:N, 0:N].astype(float)
# Пластины коры: вытянутая по вертикали ячеистая сетка (Вороной с переносом краёв).
wx = xx + fnoise(2.4, 21) * 10
wy = yy + fnoise(2.4, 22) * 18
P = []
while len(P) < 34:  # без почти совпадающих центров (иначе ячейка целиком «бороздка»)
    q = rng.random(2) * N
    if all(min(abs(q[0] - a), N - abs(q[0] - a)) * 1.9 + min(abs(q[1] - b), N - abs(q[1] - b)) * 0.55 > 40 for a, b in P):
        P.append(q)
d = []
for px, py in P:
    dx = np.abs(wx - px); dx = np.minimum(dx, N - dx)
    dy = np.abs(wy - py); dy = np.minimum(dy, N - dy)
    d.append(np.hypot(dx * 1.9, dy * 0.55))
d = np.sort(np.stack(d), 0)
edge = d[1] - d[0]
gw = 7.0 + 5.0 * np.clip(fnoise(2.2, 31), -1, 1)
groove = np.clip(1 - edge / gw, 0, 1) ** 1.3
fibers = fnoise(1.6, 5, sx=0.08, sy=1.0)          # продольные волокна
mott = fnoise(2.3, 7)
fine = fnoise(1.2, 9, sx=0.15, sy=1.0)
v = 0.8 + 0.09 * fibers + 0.05 * fine + 0.06 * mott - 0.55 * groove
v = np.clip(v, 0.12, 1.0)
os.makedirs('.godot', exist_ok=True)
Image.fromarray((v * 255).astype(np.uint8), 'L').save('.godot/bark_albedo.png')
print('OK: .godot/bark_albedo.png', round(float(v.mean()), 3))
