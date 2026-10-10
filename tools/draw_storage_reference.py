"""Референс склада продукции (docs/art/storage_reference.svg): три состояния спереди, план, палитра.
Запуск из корня проекта: python3 tools/draw_storage_reference.py"""
import math, random
S = 70                      # 1 м = 70 px
out = []
random.seed(5)
def P(x, z, ox, oz): return (ox + x * S, oz - z * S)
def poly(pts, fill, ox, oz, stroke="#2a2622", sw=2, extra=""):
    d = " ".join("%.1f,%.1f" % P(x, z, ox, oz) for x, z in pts)
    out.append(f'<polygon points="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" {extra}/>')
def rect(x0, z0, x1, z1, fill, ox, oz, sw=2, extra=""):
    poly([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], fill, ox, oz, sw=sw, extra=extra)
def line(pts, stroke, sw, ox, oz):
    d = " ".join("%.1f,%.1f" % P(x, z, ox, oz) for x, z in pts)
    out.append(f'<polyline points="{d}" fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round"/>')
def text(x, y, s, size=18, fill="#2d2a26", w="normal", anchor="start"):
    out.append(f'<text x="{x:.0f}" y="{y:.0f}" font-family="Arial" font-size="{size}" fill="{fill}" font-weight="{w}" text-anchor="{anchor}">{s}</text>')
OLD = "#7d7264"; DARK = "#3f362e"; NEW = "#b98d58"; RUST = "#8a5a3c"; GALV = "#a3abb0"; CONC = "#9a968e"; STONE = "#857f76"
BRICK = "#9a4a2c"; SIDING = "#8a3d28"; TRIM = "#d8d1c2"; TARP = "#46663d"; GREEN = "#4f6e49"; YEL = "#d1a02a"; BLUE = "#376690"
W, H = 1900, 1000
out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
out.append('<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#cfd8dc"/><stop offset="1" stop-color="#eef0ea"/></linearGradient>'
           '<pattern id="brick" width="18" height="10" patternUnits="userSpaceOnUse"><rect width="18" height="10" fill="#b8ae9c"/>'
           '<rect x="0.8" y="0.8" width="16.4" height="3.6" fill="#9a4a2c"/><rect x="-8.2" y="5.8" width="16.4" height="3.6" fill="#a5552f"/>'
           '<rect x="9.8" y="5.8" width="16.4" height="3.6" fill="#8a3f26"/></pattern></defs>')
out.append(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
text(40, 56, "Склад продукции — референс трёх состояний", 36, w="bold")
text(40, 90, "«После бури»: от разрушенного сарая к логистическому комплексу. Вид спереди (к двору, +Z в Godot). 1 м = 70 px.", 19)
GY = 640
for ox in (330, 950, 1540):
    out.append(f'<rect x="{ox - 290}" y="{GY}" width="580" height="16" fill="#6f8f3a"/>')
# --- 1. Руины ---
ox = 330
text(ox, 140, "1. Разрушенный склад — стадия 0", 22, w="bold", anchor="middle")
rect(-2.4, 0, 2.4, 0.22, CONC, ox, GY)
line([(0.3, 0.22), (0.1, 0.0)], "#2a2622", 2, ox, GY)
x = -2.3
while x < 0.4:
    h = max(0.35, 2.3 - (x + 2.3) * 0.62 + random.uniform(-0.35, 0.25))
    poly([(x, 0.22), (x + 0.19, 0.22), (x + 0.19, 0.22 + h - random.uniform(0, 0.15)), (x + 0.1, 0.22 + h), (x, 0.22 + h - 0.08)], random.choice([OLD, DARK]), ox, GY, sw=1.5)
    x += 0.2
rect(-2.3, 0.22, -2.14, 2.67, DARK, ox, GY)
poly([(-2.3, 0.22), (-2.14, 0.22), (-1.62, 2.42), (-1.78, 2.42)], DARK, ox, GY)
rect(2.14, 0.22, 2.3, 1.37, DARK, ox, GY)
poly([(2.14, 1.37), (2.2, 1.55), (2.24, 1.4), (2.3, 1.5), (2.3, 1.37)], DARK, ox, GY)
poly([(-2.2, 2.62), (-2.0, 2.66), (0.95, 0.42), (0.85, 0.3)], "#4a3f35", ox, GY)
poly([(-1.4, 0.24), (-0.4, 0.24), (-0.3, 1.5), (-1.25, 1.62)], RUST, ox, GY)
poly([(1.0, 0.25), (1.6, 0.55), (2.3, 0.28), (2.3, 0.35), (1.6, 0.65), (1.0, 0.32)], GALV, ox, GY)
rect(-1.85, 0.22, -1.15, 0.91, OLD, ox, GY)
poly([(-2.1, 0.22), (-1.95, 0.6), (-1.9, 0.95), (-1.1, 0.95), (-0.95, 0.5), (-0.9, 0.22)], TARP, ox, GY, extra='opacity="0.85"')
rect(-0.15, 0.22, 0.45, 0.82, OLD, ox, GY); line([(-0.15, 0.22), (0.45, 0.82)], DARK, 2, ox, GY)
poly([(1.3, 0.0), (2.2, 0.05), (2.15, 0.33), (1.28, 0.28)], TRIM, ox, GY)
text(ox + 1.74 * S, GY - 0.12 * S, "СКЛАД", 13, w="bold", anchor="middle")
# --- 2. Амбар ---
ox = 950
text(ox, 140, "2. Восстановленный амбар — стадии 1 и 2", 22, w="bold", anchor="middle")
for x in (-2.15, 2.15):
    rect(x - 0.18, 0, x + 0.18, 0.22, STONE, ox, GY)
rect(-2.3, 0.22, 2.3, 0.4, OLD, ox, GY)
x = -2.27
while x < 2.27:
    top = 2.6 + (3.5 - 2.6) * max(0.0, 1 - abs(x + 0.1) / 2.3) - 0.05
    if abs(x + 0.1) > 1.03:
        rect(x, 0.24, x + 0.2, top, random.choice([OLD, OLD, NEW]), ox, GY, sw=1.2)
    else:
        rect(x, 2.44, x + 0.2, top, random.choice([OLD, NEW]), ox, GY, sw=1.2)
    x += 0.205
rect(-1.0, 0.42, 1.0, 2.4, "#1f1b17", ox, GY)
rect(0.0, 0.42, 1.0, 2.4, OLD, ox, GY)
for z in (0.72, 2.1): rect(0.02, z - 0.06, 0.98, z + 0.06, NEW, ox, GY, sw=1)
line([(0.1, 0.8), (0.9, 2.02)], NEW, 6, ox, GY)
poly([(-1.0, 0.42), (-0.25, 0.3), (-0.25, 2.3), (-1.0, 2.4)], OLD, ox, GY)
rect(-0.58, 2.71, 0.58, 3.01, TRIM, ox, GY)
text(ox, GY - 2.8 * S, "СКЛАД", 16, w="bold", anchor="middle")
poly([(-2.48, 2.62), (0, 3.68), (2.48, 2.62), (2.48, 2.7), (0, 3.78), (-2.48, 2.7)], GALV, ox, GY)
line([(-1.8, 2.95), (-1.0, 3.3)], RUST, 5, ox, GY)
out.append(f'<path d="M {ox - 2.6 * S} {GY - 2.65 * S} Q {ox - 1.3 * S} {GY - 3.0 * S} {ox} {GY - 3.82 * S}" fill="none" stroke="{TARP}" stroke-width="5" stroke-dasharray="10 6"/>')
text(ox - 2.2 * S, GY - 3.55 * S, "стадия 1: каркас + тент", 13, fill=TARP, w="bold")
text(ox + 0.9 * S, GY - 3.55 * S, "стадия 2: стены, ворота, профлист", 13, w="bold")
# --- 3. Комплекс ---
ox = 1540
text(ox, 140, "3. Логистический комплекс — стадия 3", 22, w="bold", anchor="middle")
rect(-2.4, 0, 2.4, 0.42, STONE, ox, GY)
rect(-1.3, 0, 1.3, 0.28, CONC, ox, GY); rect(-1.3, 0, 1.3, 0.14, CONC, ox, GY)
rect(-2.3, 0.42, 2.3, 1.45, "url(#brick)", ox, GY)
for x in (-2.33, 1.95): rect(x, 0.42, x + 0.38, 2.95, "url(#brick)", ox, GY)
rect(-1.95, 1.51, 1.95, 2.95, SIDING, ox, GY)
for k in range(11): line([(-1.95, 1.51 + k * 0.13), (1.95, 1.51 + k * 0.13)], "#5d2a1b", 1, ox, GY)
poly([(-2.3, 2.95), (2.3, 2.95), (0, 3.95)], SIDING, ox, GY)
rect(-1.4, 0.42, 1.4, 2.8, "url(#brick)", ox, GY)
rect(-1.1, 0.42, 1.1, 2.75, "#2a2723", ox, GY)
for x in (-1.0, 0.0, 1.0):
    rect(x - 0.03 - 0.55, 0.42, x - 0.55 + 0.03, 2.62, BLUE, ox, GY, sw=1)
for z in (0.97, 1.72): rect(-1.1, z, 1.1, z + 0.09, "#c0621f", ox, GY, sw=1)
rect(-1.07, 2.12, 1.07, 2.75, GREEN, ox, GY)
for k in range(6): line([(-1.07, 2.12 + k * 0.105), (1.07, 2.12 + k * 0.105)], "#2f432c", 1.5, ox, GY)
rect(-1.25, 2.75, 1.25, 3.05, GREEN, ox, GY)
rect(-0.78, 3.25, 0.78, 3.59, TRIM, ox, GY)
text(ox, GY - 3.36 * S, "СКЛАД №1", 16, w="bold", anchor="middle")
poly([(-2.62, 2.92), (0, 4.12), (2.62, 2.92), (2.62, 3.0), (0, 4.2), (-2.62, 3.0)], "#bcc4c8", ox, GY)
rect(-0.13, 4.15, 0.13, 4.4, GALV, ox, GY)
rect(2.3, 0, 3.75, 0.1, CONC, ox, GY)
poly([(2.3, 2.96), (3.8, 2.44), (3.8, 2.52), (2.3, 3.04)], GALV, ox, GY)
rect(3.37, 0.12, 3.53, 2.92, YEL, ox, GY)
rect(2.4, 2.59, 3.52, 2.75, YEL, ox, GY)
line([(2.95, 2.5), (2.95, 1.45)], "#555", 3, ox, GY)
rect(2.7, 0.95, 3.2, 1.45, NEW, ox, GY)
rect(2.55, 0.0, 3.35, 0.14, NEW, ox, GY)
out.append(f'<circle cx="{ox + 3.45 * S:.0f}" cy="{GY - 1.4 * S:.0f}" r="{0.17 * S:.0f}" fill="#2b2d30" stroke="#111" stroke-width="2" stroke-dasharray="3 2"/>')
out.append(f'<circle cx="{ox + 3.45 * S:.0f}" cy="{GY - 1.17 * S:.0f}" r="{0.06 * S:.0f}" fill="#80868c" stroke="#111" stroke-width="2"/>')
text(ox + 3.0 * S, GY + 40, "подъёмник: шестерни 2.83 : 1, ящик ↑ 0.45 м", 13, anchor="middle")
# --- подписи и палитра ---
notes = [
    "Стадия 0: треснувшая плита, обломанные стойки, рухнувшая балка конька, ржавые листы, разбитые ящики, рваный тент, табличка «СКЛАД» на земле.",
    "Стадии 1–2 — одно состояние «амбар»: общий каркас на каменных опорах с полом и припасами; на стадии 1 поверх стропил натянут тент на растяжках,",
    "на стадии 2 — дощатые стены с окнами, ворота с Z-обвязкой (левая створка приоткрыта), кровля из профлиста с ржавым листом, вывеска.",
    "Стадия 3: кирпичный цоколь и пилястры, красная обшивка внахлёст, оцинкованная кровля со световыми листами, водостоки, рулонные ворота,",
    "стеллаж с ящиками внутри, сортировочный навес с тремя ящиками (камень, металл, дрова) и поворотная укосина с ручной лебёдкой на шестернях.",
]
for i, n in enumerate(notes):
    text(40, 735 + i * 28, n, 17)
pal = [("доски старые", OLD), ("обгоревшие", DARK), ("свежая сосна", NEW), ("ржавый лист", RUST), ("оцинковка", GALV), ("бетон", CONC),
       ("бут", STONE), ("кирпич", BRICK), ("обшивка", SIDING), ("отделка", TRIM), ("тент", TARP), ("ворота", GREEN), ("кран", YEL), ("стеллаж", BLUE)]
for i, (nm, c) in enumerate(pal):
    x = 40 + i * 130
    out.append(f'<rect x="{x}" y="900" width="40" height="40" fill="{c}" stroke="#2a2622" stroke-width="2"/>')
    text(x + 48, 926, nm, 14)
out.append('</svg>')
open("docs/art/storage_reference.svg", "w").write("\n".join(out))
print("OK docs/art/storage_reference.svg")
