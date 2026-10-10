"""Генератор векторного референса для автоматической паровой дробилки камня.
Создаёт docs/art/crusher_reference.svg в строгом соответствии с требованиями брифа:
- 16:9 ландшафт (1920x1080)
- Нейтральный светло-серый студийный фон (#dce0e4 / #eef1f4)
- Мягкое студийное освещение и контактные тени
- Верхний ряд: 5 ракурсов машины (Front 3/4, Rear 3/4, Left, Right, Elevated Top)
- Средний ряд: 8 изолированных механических узлов
- Нижний ряд: 8-кадровый сториборд анимации полного цикла работы
- БЕЗ ТЕКСТА, БЕЗ МЕТОК, БЕЗ ЛОГОТИПОВ, БЕЗ ВОДЯНЫХ ЗНАКОВ
"""

import math
import os

OUT_PATH = os.path.abspath("docs/art/crusher_reference.svg")
os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)

class SVGBuilder:
    def __init__(self, width=1920, height=1080):
        self.w = width
        self.h = height
        self.defs = []
        self.body = []

    def add_def(self, d):
        self.defs.append(d)

    def add(self, element):
        self.body.append(element)

    def render(self):
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
            f'width="{self.w}" height="{self.h}">\n'
            f'<defs>\n' + "\n".join(self.defs) + f'\n</defs>\n'
            + "\n".join(self.body) +
            f'\n</svg>'
        )

svg = SVGBuilder()

# ----------------- ДЕФИНИЦИИ И ГРАДИЕНТЫ -----------------
svg.add_def("""
<!-- Фоновый студийный градиент -->
<radialGradient id="bgStudio" cx="50%" cy="45%" r="70%">
    <stop offset="0%" stop-color="#edf0f3"/>
    <stop offset="60%" stop-color="#d6dadf"/>
    <stop offset="100%" stop-color="#c4c9cf"/>
</radialGradient>

<!-- Мягкая контактная тень -->
<radialGradient id="shadowFloor" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="#181c20" stop-opacity="0.35"/>
    <stop offset="50%" stop-color="#181c20" stop-opacity="0.15"/>
    <stop offset="100%" stop-color="#181c20" stop-opacity="0.0"/>
</radialGradient>

<!-- Палитра: Чугун и темная сталь -->
<linearGradient id="ironH" x1="0%" y1="0%" x2="100%" y2="0%">
    <stop offset="0%" stop-color="#24272b"/>
    <stop offset="35%" stop-color="#464b52"/>
    <stop offset="70%" stop-color="#32353a"/>
    <stop offset="100%" stop-color="#1c1e21"/>
</linearGradient>

<linearGradient id="ironV" x1="0%" y1="0%" x2="0%" y2="100%">
    <stop offset="0%" stop-color="#464b52"/>
    <stop offset="50%" stop-color="#32353a"/>
    <stop offset="100%" stop-color="#1e2023"/>
</linearGradient>

<!-- Палитра: Состаренная латунь (шестерни, втулки, манометр) -->
<linearGradient id="brassH" x1="0%" y1="0%" x2="100%" y2="0%">
    <stop offset="0%" stop-color="#6e5318"/>
    <stop offset="30%" stop-color="#c29837"/>
    <stop offset="65%" stop-color="#e8be56"/>
    <stop offset="100%" stop-color="#7a5b1c"/>
</linearGradient>

<!-- Палитра: Состаренная медь (трубы, клапаны) -->
<linearGradient id="copperH" x1="0%" y1="0%" x2="100%" y2="0%">
    <stop offset="0%" stop-color="#542416"/>
    <stop offset="40%" stop-color="#9e4b30"/>
    <stop offset="70%" stop-color="#be6244"/>
    <stop offset="100%" stop-color="#5c2617"/>
</linearGradient>

<!-- Палитра: Серый гранит (жернова) -->
<linearGradient id="graniteH" x1="0%" y1="0%" x2="100%" y2="0%">
    <stop offset="0%" stop-color="#484a4d"/>
    <stop offset="30%" stop-color="#73767a"/>
    <stop offset="60%" stop-color="#888c91"/>
    <stop offset="100%" stop-color="#525559"/>
</linearGradient>

<radialGradient id="graniteTop" cx="45%" cy="45%" r="55%">
    <stop offset="0%" stop-color="#9ea2a8"/>
    <stop offset="60%" stop-color="#767a7f"/>
    <stop offset="100%" stop-color="#55585c"/>
</radialGradient>

<!-- Палитра: Выветренная древесина балок -->
<linearGradient id="woodBeamV" x1="0%" y1="0%" x2="100%" y2="0%">
    <stop offset="0%" stop-color="#342214"/>
    <stop offset="25%" stop-color="#543924"/>
    <stop offset="75%" stop-color="#63452c"/>
    <stop offset="100%" stop-color="#3b2617"/>
</linearGradient>

<!-- Эффекты: пар и дым -->
<radialGradient id="steamPuff" cx="40%" cy="40%" r="55%">
    <stop offset="0%" stop-color="#ffffff" stop-opacity="0.8"/>
    <stop offset="50%" stop-color="#e2e6eb" stop-opacity="0.45"/>
    <stop offset="100%" stop-color="#cbd0d6" stop-opacity="0.0"/>
</radialGradient>

<radialGradient id="smokePuff" cx="45%" cy="45%" r="55%">
    <stop offset="0%" stop-color="#52565c" stop-opacity="0.75"/>
    <stop offset="55%" stop-color="#3a3d42" stop-opacity="0.4"/>
    <stop offset="100%" stop-color="#2a2c30" stop-opacity="0.0"/>
</radialGradient>

<radialGradient id="dustCloud" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="#b8b3a7" stop-opacity="0.6"/>
    <stop offset="50%" stop-color="#a39e93" stop-opacity="0.25"/>
    <stop offset="100%" stop-color="#8e897e" stop-opacity="0.0"/>
</radialGradient>

<filter id="softGlow" x="-20%" y="-20%" width="140%" height="140%">
    <feGaussianBlur stdDeviation="3" result="blur"/>
    <feComposite in="SourceGraphic" in2="blur" operator="over"/>
</filter>
""")

# Фоновый прямоугольник (1920x1080)
svg.add('<rect width="1920" height="1080" fill="url(#bgStudio)"/>')

# Сетки / разделительные карманы (тонкие нейтральные студийные контуры)
def add_card(x, y, w, h):
    svg.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" '
            f'fill="#ffffff" fill-opacity="0.22" stroke="#b0b6bc" stroke-width="1.2"/>')

# ----------------- МОДУЛЬ ОТРИСОВКИ МАШИНЫ -----------------
def draw_machine(cx, cy, scale=1.0, view_angle="front_iso",
                 flywheel_deg=0.0, stone_deg=0.0,
                 piston_ratio=0.0, smoke_level=0.0,
                 steam_level=0.0, dust_level=0.0,
                 has_rocks=False, crushed_gravel_level=0.0):
    """
    Рисует полную сборку автоматической паровой дробилки.
    Габариты машины параметризованы под заданный ракурс и фазу анимации.
    """
    g = []
    s = scale

    # Тень под машиной на полу
    sh_w = 190 * s
    sh_h = 42 * s
    g.append(f'<ellipse cx="{cx}" cy="{cy + 130 * s}" rx="{sh_w}" ry="{sh_h}" fill="url(#shadowFloor)"/>')

    if view_angle == "top":
        # Вид сверху: круглая форма жернова, крестовина бункера, бойлер сбоку, маховик сверху
        # Фундамент плита
        g.append(f'<rect x="{cx - 110*s}" y="{cy - 100*s}" width="{220*s}" height="{200*s}" rx="{10*s}" fill="#5a5d62" stroke="#36383b" stroke-width="{2*s}"/>')
        # Нижний жернов (базовый диск)
        g.append(f'<circle cx="{cx - 15*s}" cy="{cy}" r="{75*s}" fill="url(#graniteH)" stroke="#2b2d30" stroke-width="{3*s}"/>')
        # Верхний жернов с радиальными бороздами
        g.append(f'<circle cx="{cx - 15*s}" cy="{cy}" r="{68*s}" fill="url(#graniteTop)" stroke="#222426" stroke-width="{2*s}"/>')
        rad_stone = math.radians(stone_deg)
        for i in range(12):
            ang = rad_stone + i * (math.pi / 6)
            x1 = (cx - 15*s) + math.cos(ang) * (20*s)
            y1 = cy + math.sin(ang) * (20*s)
            x2 = (cx - 15*s) + math.cos(ang) * (66*s)
            y2 = cy + math.sin(ang) * (66*s)
            g.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#36383b" stroke-width="{2.5*s}"/>')

        # Бункер (воронка сверху)
        g.append(f'<polygon points="{cx-50*s},{cy-50*s} {cx+20*s},{cy-50*s} {cx+10*s},{cy+40*s} {cx-40*s},{cy+40*s}" fill="url(#ironV)" stroke="#1a1c1e" stroke-width="{2.5*s}"/>')
        g.append(f'<rect x="{cx-35*s}" y="{cy-35*s}" width="{50*s}" height="{55*s}" fill="#202225"/>')
        if has_rocks:
            g.append(f'<polygon points="{cx-20*s},{cy-20*s} {cx-10*s},{cy-28*s} {cx},{cy-18*s} {cx-12*s},{cy-8*s}" fill="#6b6f75" stroke="#333"/>')
            g.append(f'<polygon points="{cx-5*s},{cy-10*s} {cx+8*s},{cy-20*s} {cx+12*s},{cy-5*s} {cx+2*s},{cy+5*s}" fill="#54575c" stroke="#333"/>')

        # Бойлер сбоку справа
        g.append(f'<circle cx="{cx + 70*s}" cy="{cy - 10*s}" r="{35*s}" fill="url(#ironH)" stroke="#1f2124" stroke-width="{2*s}"/>')
        # Труба выхлопа сверху бойлера
        g.append(f'<circle cx="{cx + 80*s}" cy="{cy - 20*s}" r="{12*s}" fill="#1c1e21" stroke="#4c5056" stroke-width="{2*s}"/>')
        # Маховик с торца
        g.append(f'<rect x="{cx + 62*s}" y="{cy + 35*s}" width="{16*s}" height="{50*s}" rx="{3*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')

    elif view_angle == "left":
        # Вид слева (профиль): четко видны два жернова друг над другом, деревянные стойки, зазор, выходной желоб
        # Каменный фундамент
        g.append(f'<rect x="{cx - 75*s}" y="{cy + 85*s}" width="{150*s}" height="{40*s}" fill="#525559" stroke="#252729" stroke-width="{2*s}"/>')
        # Деревянный каркас (две массивные стойки и поперечина)
        g.append(f'<rect x="{cx - 65*s}" y="{cy - 40*s}" width="{22*s}" height="{130*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')
        g.append(f'<rect x="{cx + 43*s}" y="{cy - 40*s}" width="{22*s}" height="{130*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')
        g.append(f'<rect x="{cx - 70*s}" y="{cy - 48*s}" width="{140*s}" height="{18*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')

        # Стальной нижний жернов (STATIC)
        g.append(f'<rect x="{cx - 52*s}" y="{cy + 42*s}" width="{104*s}" height="{38*s}" rx="{4*s}" fill="url(#graniteH)" stroke="#222426" stroke-width="{2.5*s}"/>')
        # Зазор между жерновами (темный промежуток)
        g.append(f'<rect x="{cx - 48*s}" y="{cy + 34*s}" width="{96*s}" height="{8*s}" fill="#1a1c1e"/>')
        # Верхний жернов (ROTATING)
        g.append(f'<rect x="{cx - 54*s}" y="{cy - 4*s}" width="{108*s}" height="{38*s}" rx="{4*s}" fill="url(#graniteH)" stroke="#222426" stroke-width="{2.5*s}"/>')
        # Стальной обруч на верхнем жернове
        g.append(f'<rect x="{cx - 55*s}" y="{cy + 8*s}" width="{110*s}" height="{10*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')

        # Центральный вертикальный вал
        g.append(f'<rect x="{cx - 7*s}" y="{cy - 65*s}" width="{14*s}" height="{65*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')

        # Коническая передача вверху (угол 90°)
        g.append(f'<polygon points="{cx-18*s},{cy-65*s} {cx+18*s},{cy-65*s} {cx+12*s},{cy-50*s} {cx-12*s},{cy-50*s}" fill="url(#brassH)" stroke="#523d11" stroke-width="{1.5*s}"/>')

        # Бункер подачи сверху
        g.append(f'<polygon points="{cx-45*s},{cy-115*s} {cx+45*s},{cy-115*s} {cx+25*s},{cy-70*s} {cx-25*s},{cy-70*s}" fill="url(#ironV)" stroke="#181a1c" stroke-width="{2.5*s}"/>')

        # Наклонный разгрузочный лоток слева внизу
        g.append(f'<polygon points="{cx-48*s},{cy+65*s} {cx-85*s},{cy+95*s} {cx-80*s},{cy+110*s} {cx-42*s},{cy+78*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')

        # Горка щебня под лотком
        if crushed_gravel_level > 0:
            gw = 35 * s * crushed_gravel_level
            gh = 18 * s * crushed_gravel_level
            g.append(f'<ellipse cx="{cx - 88*s}" cy="{cy + 115*s}" rx="{gw}" ry="{gh}" fill="#63666b" stroke="#383a3d" stroke-width="{1.5*s}"/>')

    elif view_angle == "right":
        # Вид справа: паровой котел, маховик, цилиндр с поршнем и шатуном, выхлопная труба
        # Основание
        g.append(f'<rect x="{cx - 80*s}" y="{cy + 85*s}" width="{160*s}" height="{40*s}" fill="#525559" stroke="#252729" stroke-width="{2*s}"/>')
        # Бойлер (вертикальный цилиндр с заклепками)
        g.append(f'<rect x="{cx - 60*s}" y="{cy - 30*s}" width="{55*s}" height="{115*s}" rx="{6*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
        g.append(f'<path d="M {cx-60*s} {cy-30*s} Q {cx-32.5*s} {cy-50*s} {cx-5*s} {cy-30*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
        # Латунные обручи на котле
        g.append(f'<rect x="{cx - 61*s}" y="{cy + 5*s}" width="{57*s}" height="{6*s}" fill="url(#brassH)"/>')
        g.append(f'<rect x="{cx - 61*s}" y="{cy + 45*s}" width="{57*s}" height="{6*s}" fill="url(#brassH)"/>')

        # Манометр
        g.append(f'<circle cx="{cx - 45*s}" cy="{cy - 10*s}" r="{11*s}" fill="url(#brassH)" stroke="#3e2d09" stroke-width="{1.5*s}"/>')
        g.append(f'<circle cx="{cx - 45*s}" cy="{cy - 10*s}" r="{8*s}" fill="#f2efe9"/>')
        g.append(f'<line x1="{cx - 45*s}" y1="{cy - 10*s}" x2="{cx - 40*s}" y2="{cy - 15*s}" stroke="#a82313" stroke-width="{1.5*s}"/>')

        # Дымовая труба вверх
        g.append(f'<rect x="{cx - 42*s}" y="{cy - 110*s}" width="{18*s}" height="{70*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')
        # Колпак трубы
        g.append(f'<polygon points="{cx-48*s},{cy-110*s} {cx-24*s},{cy-110*s} {cx-33*s},{cy-122*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{1.5*s}"/>')

        # Горизонтальный паровой цилиндр
        g.append(f'<rect x="{cx + 10*s}" y="{cy + 48*s}" width="{45*s}" height="{24*s}" rx="{3*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
        # Шток поршня и шатун
        pist_x = (cx + 5*s) - (12 * s * piston_ratio)
        g.append(f'<line x1="{cx + 10*s}" y1="{cy + 60*s}" x2="{pist_x}" y2="{cy + 60*s}" stroke="#8c929a" stroke-width="{4*s}"/>')

        # Маховик (большое колесо справа)
        fly_cx = cx + 25 * s
        fly_cy = cy + 10 * s
        fly_r = 42 * s
        g.append(f'<circle cx="{fly_cx}" cy="{fly_cy}" r="{fly_r}" fill="none" stroke="url(#ironH)" stroke-width="{8*s}"/>')
        g.append(f'<circle cx="{fly_cx}" cy="{fly_cy}" r="{12*s}" fill="url(#brassH)" stroke="#3a2b09" stroke-width="{2*s}"/>')
        # Спицы маховика
        rad_fly = math.radians(flywheel_deg)
        for i in range(6):
            ang = rad_fly + i * (math.pi / 3)
            fx = fly_cx + math.cos(ang) * (fly_r - 4*s)
            fy = fly_cy + math.sin(ang) * (fly_r - 4*s)
            g.append(f'<line x1="{fly_cx}" y1="{fly_cy}" x2="{fx:.1f}" y2="{fy:.1f}" stroke="url(#ironH)" stroke-width="{3.5*s}"/>')

    elif view_angle == "rear_iso":
        # Задний ракурс 3/4: виден бойлер, трубопровод, задняя балка, картер цилиндра
        # Фундамент
        g.append(f'<polygon points="{cx-80*s},{cy+70*s} {cx+40*s},{cy+95*s} {cx+95*s},{cy+75*s} {cx-25*s},{cy+50*s}" fill="#4d5054" stroke="#252729" stroke-width="{2*s}"/>')
        g.append(f'<polygon points="{cx-80*s},{cy+70*s} {cx+40*s},{cy+95*s} {cx+40*s},{cy+120*s} {cx-80*s},{cy+95*s}" fill="#3f4144" stroke="#252729" stroke-width="{2*s}"/>')
        g.append(f'<polygon points="{cx+40*s},{cy+95*s} {cx+95*s},{cy+75*s} {cx+95*s},{cy+100*s} {cx+40*s},{cy+120*s}" fill="#2e3033" stroke="#252729" stroke-width="{2*s}"/>')

        # Задние брусья каркаса
        g.append(f'<rect x="{cx - 65*s}" y="{cy - 30*s}" width="{18*s}" height="{115*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')
        g.append(f'<rect x="{cx + 15*s}" y="{cy - 45*s}" width="{18*s}" height="{115*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')

        # Котёл крупно по центру заднего вида
        g.append(f'<rect x="{cx - 35*s}" y="{cy - 10*s}" width="{52*s}" height="{95*s}" rx="{6*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
        g.append(f'<ellipse cx="{cx - 9*s}" cy="{cy - 10*s}" rx="{26*s}" ry="{12*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')

        # Труба и дым
        g.append(f'<rect x="{cx - 16*s}" y="{cy - 110*s}" width="{16*s}" height="{100*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')

        # Медные паропроводы
        g.append(f'<path d="M {cx-9*s} {cy+10*s} L {cx+35*s} {cy+10*s} L {cx+35*s} {cy+55*s}" fill="none" stroke="url(#copperH)" stroke-width="{4*s}"/>')

    else:
        # ОСНОВНОЙ РАКУРС: Front three-quarter view (видны верхний/нижний жернова, паровая машина, маховик, труба, желоб)
        # Каменный граненый фундамент
        p_base_top = f"{cx-75*s},{cy+65*s} {cx-15*s},{cy+92*s} {cx+85*s},{cy+60*s} {cx+25*s},{cy+35*s}"
        p_base_left = f"{cx-75*s},{cy+65*s} {cx-15*s},{cy+92*s} {cx-15*s},{cy+122*s} {cx-75*s},{cy+95*s}"
        p_base_right = f"{cx-15*s},{cy+92*s} {cx+85*s},{cy+60*s} {cx+85*s},{cy+90*s} {cx-15*s},{cy+122*s}"
        g.append(f'<polygon points="{p_base_top}" fill="#63666b" stroke="#2b2d30" stroke-width="{2*s}"/>')
        g.append(f'<polygon points="{p_base_left}" fill="#4d5054" stroke="#2b2d30" stroke-width="{2*s}"/>')
        g.append(f'<polygon points="{p_base_right}" fill="#383a3d" stroke="#2b2d30" stroke-width="{2*s}"/>')

        # Деревянные угловые стойки с железными накладками
        # Стойка левая передняя
        g.append(f'<rect x="{cx - 68*s}" y="{cy - 35*s}" width="{16*s}" height="{115*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')
        # Стойка правая центральная
        g.append(f'<rect x="{cx - 2*s}" y="{cy - 48*s}" width="{16*s}" height="{125*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')
        # Верхняя поперечная балка
        g.append(f'<polygon points="{cx-72*s},{cy-35*s} {cx+18*s},{cy-48*s} {cx+18*s},{cy-32*s} {cx-72*s},{cy-19*s}" fill="url(#woodBeamV)" stroke="#22160d" stroke-width="{2*s}"/>')
        # Металлические косынки и болты
        g.append(f'<polygon points="{cx-68*s},{cy-19*s} {cx-50*s},{cy-22*s} {cx-68*s},{cy-5*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')
        g.append(f'<circle cx="{cx-62*s}" cy="{cy-14*s}" r="{2*s}" fill="#787e87"/>')

        # НИЖНИЙ ЖЕРНОВ (STATIC) - гранитный толстый цилиндр
        g.append(f'<ellipse cx="{cx - 25*s}" cy="{cy + 62*s}" rx="{48*s}" ry="{20*s}" fill="url(#graniteTop)" stroke="#282a2d" stroke-width="{2*s}"/>')
        g.append(f'<path d="M {cx-73*s} {cy+62*s} A {48*s} {20*s} 0 0 0 {cx+23*s} {cy+62*s} L {cx+23*s} {cy+78*s} A {48*s} {20*s} 0 0 1 {cx-73*s} {cy+78*s} Z" fill="url(#graniteH)" stroke="#222426" stroke-width="{2*s}"/>')

        # ЗАЗОР МЕЖДУ ЖЕРНОВАМИ
        g.append(f'<path d="M {cx-69*s} {cy+57*s} A {46*s} {18*s} 0 0 0 {cx+21*s} {cy+57*s} L {cx+21*s} {cy+59*s} A {46*s} {18*s} 0 0 1 {cx-69*s} {cy+59*s} Z" fill="#151718"/>')

        # ВЕРХНИЙ ЖЕРНОВ (ROTATING) - с радиальными бороздами и стальным ободом
        stone_y = cy + 28 * s
        g.append(f'<path d="M {cx-74*s} {stone_y} A {49*s} {21*s} 0 0 0 {cx+24*s} {stone_y} L {cx+24*s} {stone_y+24*s} A {49*s} {21*s} 0 0 1 {cx-74*s} {stone_y+24*s} Z" fill="url(#graniteH)" stroke="#222426" stroke-width="{2*s}"/>')
        g.append(f'<ellipse cx="{cx - 25*s}" cy="{stone_y}" rx="{49*s}" ry="{21*s}" fill="url(#graniteTop)" stroke="#282a2d" stroke-width="{2*s}"/>')
        # Стальной армирующий обруч
        g.append(f'<path d="M {cx-74*s} {stone_y+10*s} A {49*s} {21*s} 0 0 0 {cx+24*s} {stone_y+10*s} L {cx+24*s} {stone_y+16*s} A {49*s} {21*s} 0 0 1 {cx-74*s} {stone_y+16*s} Z" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')
        # Борозды на верхнем камне (поворачиваются на угол stone_deg)
        rad_stone = math.radians(stone_deg)
        for i in range(8):
            ang = rad_stone + i * (math.pi / 4)
            bx1 = (cx - 25*s) + math.cos(ang) * (14*s)
            by1 = stone_y + math.sin(ang) * (6*s)
            bx2 = (cx - 25*s) + math.cos(ang) * (45*s)
            by2 = stone_y + math.sin(ang) * (19*s)
            g.append(f'<line x1="{bx1:.1f}" y1="{by1:.1f}" x2="{bx2:.1f}" y2="{by2:.1f}" stroke="#33363a" stroke-width="{2*s}"/>')

        # Вертикальный вал привода через верхний камень
        g.append(f'<rect x="{cx - 28*s}" y="{cy - 50*s}" width="{7*s}" height="{80*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')

        # Коническая зубчатая передача (90 градусов)
        # Горизонтальная коническая шестерня (на верт. валу)
        g.append(f'<polygon points="{cx-36*s},{cy-46*s} {cx-15*s},{cy-49*s} {cx-19*s},{cy-37*s} {cx-32*s},{cy-35*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{1.5*s}"/>')
        # Вертикальная коническая шестерня (на гориз. валу двигателя)
        g.append(f'<polygon points="{cx-15*s},{cy-49*s} {cx-13*s},{cy-35*s} {cx-5*s},{cy-38*s} {cx-7*s},{cy-52*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{1.5*s}"/>')

        # Горизонтальный вал передачи к паровой машине
        g.append(f'<polygon points="{cx-7*s},{cy-48*s} {cx+48*s},{cy-36*s} {cx+48*s},{cy-31*s} {cx-7*s},{cy-43*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')

        # ПАРОВОЙ КОТЕЛ (справа)
        boiler_cx = cx + 55 * s
        boiler_cy = cy + 22 * s
        g.append(f'<rect x="{boiler_cx - 20*s}" y="{boiler_cy - 45*s}" width="{40*s}" height="{75*s}" rx="{5*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
        g.append(f'<ellipse cx="{boiler_cx}" cy="{boiler_cy - 45*s}" rx="{20*s}" ry="{9*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
        # Латунные обручи
        g.append(f'<path d="M {boiler_cx-20*s} {boiler_cy-20*s} A {20*s} {9*s} 0 0 0 {boiler_cx+20*s} {boiler_cy-20*s}" fill="none" stroke="url(#brassH)" stroke-width="{4*s}"/>')
        g.append(f'<path d="M {boiler_cx-20*s} {boiler_cy+10*s} A {20*s} {9*s} 0 0 0 {boiler_cx+20*s} {boiler_cy+10*s}" fill="none" stroke="url(#brassH)" stroke-width="{4*s}"/>')
        # Манометр на котле
        g.append(f'<circle cx="{boiler_cx - 8*s}" cy="{boiler_cy - 28*s}" r="{8*s}" fill="url(#brassH)" stroke="#3e2d09" stroke-width="{1.2*s}"/>')
        g.append(f'<circle cx="{boiler_cx - 8*s}" cy="{boiler_cy - 28*s}" r="{6*s}" fill="#f6f3eb"/>')
        g.append(f'<line x1="{boiler_cx - 8*s}" y1="{boiler_cy - 28*s}" x2="{boiler_cx - 5*s}" y2="{boiler_cy - 32*s}" stroke="#a82313" stroke-width="{1.2*s}"/>')

        # ДЫМОВАЯ ТРУБА И ВЫХЛОП
        chim_x = boiler_cx - 5 * s
        chim_y = boiler_cy - 45 * s
        g.append(f'<rect x="{chim_x - 7*s}" y="{chim_y - 70*s}" width="{14*s}" height="{72*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')
        # Кольца и колпак трубы
        g.append(f'<rect x="{chim_x - 9*s}" y="{chim_y - 25*s}" width="{18*s}" height="{5*s}" fill="#222426"/>')
        g.append(f'<polygon points="{chim_x-12*s},{chim_y-70*s} {chim_x+12*s},{chim_y-70*s} {chim_x},{chim_y-80*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{1.5*s}"/>')

        # ГОРИЗОНТАЛЬНЫЙ МАХОВИК И ШАТУН
        fly_cx = cx + 58 * s
        fly_cy = cy + 48 * s
        fly_r = 30 * s
        # Эллиптическая проекция маховика
        g.append(f'<ellipse cx="{fly_cx}" cy="{fly_cy}" rx="{fly_r}" ry="{fly_r * 0.45}" fill="none" stroke="url(#ironH)" stroke-width="{6*s}"/>')
        g.append(f'<ellipse cx="{fly_cx}" cy="{fly_cy}" rx="{8*s}" ry="{4*s}" fill="url(#brassH)" stroke="#3e2d09" stroke-width="{1.5*s}"/>')
        # Спицы маховика
        rad_fly = math.radians(flywheel_deg)
        for i in range(4):
            ang = rad_fly + i * (math.pi / 2)
            fx = fly_cx + math.cos(ang) * (fly_r - 2*s)
            fy = fly_cy + math.sin(ang) * ((fly_r - 2*s) * 0.45)
            g.append(f'<line x1="{fly_cx}" y1="{fly_cy}" x2="{fx:.1f}" y2="{fy:.1f}" stroke="url(#ironH)" stroke-width="{2.5*s}"/>')

        # Поршень и шатун к маховику
        crank_x = fly_cx + math.cos(rad_fly) * (18 * s)
        crank_y = fly_cy + math.sin(rad_fly) * (8 * s)
        piston_box_x = cx + 18 * s
        piston_box_y = cy + 54 * s
        g.append(f'<line x1="{piston_box_x}" y1="{piston_box_y}" x2="{crank_x:.1f}" y2="{crank_y:.1f}" stroke="url(#brassH)" stroke-width="{3.5*s}"/>')
        g.append(f'<circle cx="{crank_x:.1f}" cy="{crank_y:.1f}" r="{3*s}" fill="#ebd076"/>')

        # ЗАГРУЗОЧНЫЙ БУНКЕР (сверху над жерновами)
        hop_cx = cx - 25 * s
        hop_cy = cy - 65 * s
        p_hopper = f"{hop_cx-36*s},{hop_cy-35*s} {hop_cx+30*s},{hop_cy-42*s} {hop_cx+18*s},{hop_cy+10*s} {hop_cx-24*s},{hop_cy+14*s}"
        g.append(f'<polygon points="{p_hopper}" fill="url(#ironV)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
        # Горловина бункера
        g.append(f'<polygon points="{hop_cx-32*s},{hop_cy-33*s} {hop_cx+26*s},{hop_cy-39*s} {hop_cx+16*s},{hop_cy-22*s} {hop_cx-22*s},{hop_cy-18*s}" fill="#1c1e21"/>')

        # Падающие камни в бункер
        if has_rocks:
            g.append(f'<polygon points="{hop_cx-12*s},{hop_cy-24*s} {hop_cx-2*s},{hop_cy-30*s} {hop_cx+6*s},{hop_cy-22*s} {hop_cx-4*s},{hop_cy-14*s}" fill="#767980" stroke="#2a2c2e" stroke-width="{1.5*s}"/>')
            g.append(f'<polygon points="{hop_cx+4*s},{hop_cy-16*s} {hop_cx+14*s},{hop_cy-22*s} {hop_cx+18*s},{hop_cy-10*s} {hop_cx+8*s},{hop_cy-6*s}" fill="#5a5d62" stroke="#2a2c2e" stroke-width="{1.5*s}"/>')

        # РАЗГРУЗОЧНЫЙ НАКЛОННЫЙ ЛОТОК (Chute) слева внизу
        chute_p = f"{cx-58*s},{cy+68*s} {cx-92*s},{cy+88*s} {cx-82*s},{cy+98*s} {cx-48*s},{cy+78*s}"
        g.append(f'<polygon points="{chute_p}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')
        # Внутренняя грань лотка
        g.append(f'<polygon points="{cx-60*s},{cy+67*s} {cx-90*s},{cy+85*s} {cx-86*s},{cy+90*s} {cx-56*s},{cy+72*s}" fill="#25272a"/>')

        # Дробленая каменная крошка / щебень
        if crushed_gravel_level > 0:
            gw = 28 * s * crushed_gravel_level
            gh = 14 * s * crushed_gravel_level
            g.append(f'<ellipse cx="{cx - 96*s}" cy="{cy + 106*s}" rx="{gw}" ry="{gh}" fill="#63666b" stroke="#36383b" stroke-width="{1.5*s}"/>')
            # Отдельные камешки
            for offx, offy in [(-8, 2), (4, -3), (10, 4), (-3, -5)]:
                rx = (cx - 96*s) + offx * s * crushed_gravel_level
                ry = (cy + 106*s) + offy * s * crushed_gravel_level
                g.append(f'<circle cx="{rx}" cy="{ry}" r="{2.5*s}" fill="#888c92"/>')

    # ВЫБРОС ДЫМА И ПАРА (Smoke & Steam)
    chim_top_x = (cx + 50*s) if view_angle not in ["top", "left"] else (cx - 33*s)
    chim_top_y = (cy - 95*s) if view_angle not in ["top"] else cy

    if smoke_level > 0 and view_angle != "top":
        smk_sizes = [12, 18, 25, 34]
        for idx, sz in enumerate(smk_sizes):
            alpha = (0.2 + 0.6 * smoke_level) * (1.0 - idx * 0.2)
            px = chim_top_x + (idx * 10 * s) + (math.sin(idx * 1.5) * 6 * s)
            py = chim_top_y - (idx * 22 * s * smoke_level) - (15 * s)
            r = sz * s * (0.6 + 0.4 * smoke_level)
            g.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{r:.1f}" fill="url(#smokePuff)" opacity="{alpha:.2f}"/>')

    if steam_level > 0 and view_angle != "top":
        # Небольшие струи пара из предохранительного клапана
        px = chim_top_x - 14 * s
        py = chim_top_y + 15 * s
        g.append(f'<ellipse cx="{px}" cy="{py - 10*s}" rx="{10*s*steam_level}" ry="{16*s*steam_level}" fill="url(#steamPuff)" opacity="{0.7*steam_level:.2f}"/>')

    # КАМЕННАЯ ПЫЛЬ ВОКРУГ ЖЕРНОВОВ (Mineral Grinding Dust)
    if dust_level > 0 and view_angle in ["front_iso", "left"]:
        dust_cx = cx - 25 * s
        dust_cy = cy + 45 * s
        g.append(f'<ellipse cx="{dust_cx}" cy="{dust_cy}" rx="{55*s}" ry="{22*s}" fill="url(#dustCloud)" opacity="{0.55*dust_level:.2f}"/>')
        g.append(f'<ellipse cx="{dust_cx - 15*s}" cy="{dust_cy + 8*s}" rx="{35*s}" ry="{15*s}" fill="url(#dustCloud)" opacity="{0.4*dust_level:.2f}"/>')

    return "\n".join(g)


# =========================================================================
# 1. ВЕРХНЯЯ СЕКЦИЯ: 5 РАКУРСОВ МАШИНЫ (TOP SECTION - MACHINE DESIGN)
# =========================================================================
# Y: 25 .. 335 (H=310). 5 колонок шириной 360px
views_cfg = [
    ("front_iso", 195, 175, 1.05),
    ("rear_iso", 575, 175, 1.05),
    ("left", 955, 175, 1.05),
    ("right", 1335, 175, 1.05),
    ("top", 1715, 175, 1.05),
]

for idx, (v_name, cx, cy, sc) in enumerate(views_cfg):
    box_x = 25 + idx * 378
    add_card(box_x, 22, 368, 308)
    # Рисуем машину в статичном полурабочем состоянии (аккуратный технический вид)
    svg.add(draw_machine(cx, cy, scale=sc, view_angle=v_name,
                         flywheel_deg=45.0, stone_deg=25.0,
                         piston_ratio=0.5, smoke_level=0.35,
                         steam_level=0.2, dust_level=0.15,
                         has_rocks=True, crushed_gravel_level=0.4))


# =========================================================================
# 2. СРЕДНЯЯ СЕКЦИЯ: 8 ИЗОЛИРОВАННЫХ МЕХАНИЧЕСКИХ ДЕТАЛЕЙ (MIDDLE SECTION)
# =========================================================================
# Y: 345 .. 630 (H=285). 8 ячеек шириной ~226px
card_w = 226
card_h = 285
card_gap = 12
start_x = 25

def draw_detail_upper_stone(cx, cy, s=1.1):
    # Деталь 1: Верхний жернов с валом и радиальными бороздами
    g = []
    # Вал
    g.append(f'<rect x="{cx - 7*s}" y="{cy - 85*s}" width="{14*s}" height="{80*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
    # Ступица
    g.append(f'<rect x="{cx - 15*s}" y="{cy - 20*s}" width="{30*s}" height="{22*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{2*s}"/>')
    # Гранитный диск
    g.append(f'<path d="M {cx-65*s} {cy-5*s} A {65*s} {28*s} 0 0 0 {cx+65*s} {cy-5*s} L {cx+65*s} {cy+28*s} A {65*s} {28*s} 0 0 1 {cx-65*s} {cy+28*s} Z" fill="url(#graniteH)" stroke="#222426" stroke-width="{2.5*s}"/>')
    g.append(f'<ellipse cx="{cx}" cy="{cy-5*s}" rx="{65*s}" ry="{28*s}" fill="url(#graniteTop)" stroke="#252729" stroke-width="{2.5*s}"/>')
    # Стальной обод
    g.append(f'<path d="M {cx-66*s} {cy+10*s} A {66*s} {28*s} 0 0 0 {cx+66*s} {cy+10*s} L {cx+66*s} {cy+18*s} A {66*s} {28*s} 0 0 1 {cx-66*s} {cy+18*s} Z" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
    # Радиальные борозды
    for i in range(12):
        ang = i * (math.pi / 6)
        x1 = cx + math.cos(ang) * (18*s)
        y1 = (cy - 5*s) + math.sin(ang) * (8*s)
        x2 = cx + math.cos(ang) * (60*s)
        y2 = (cy - 5*s) + math.sin(ang) * (26*s)
        g.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#2e3033" stroke-width="{2.5*s}"/>')
    return "\n".join(g)

def draw_detail_lower_stone(cx, cy, s=1.1):
    # Деталь 2: Нижний неподвижный жернов в каменном ложе
    g = []
    # Каменное основание
    g.append(f'<rect x="{cx - 75*s}" y="{cy + 25*s}" width="{150*s}" height="{45*s}" rx="{4*s}" fill="#54575b" stroke="#252729" stroke-width="{2*s}"/>')
    # Нижний гранитный жернов
    g.append(f'<path d="M {cx-65*s} {cy-10*s} A {65*s} {28*s} 0 0 0 {cx+65*s} {cy-10*s} L {cx+65*s} {cy+25*s} A {65*s} {28*s} 0 0 1 {cx-65*s} {cy+25*s} Z" fill="url(#graniteH)" stroke="#222426" stroke-width="{2.5*s}"/>')
    g.append(f'<ellipse cx="{cx}" cy="{cy-10*s}" rx="{65*s}" ry="{28*s}" fill="url(#graniteTop)" stroke="#252729" stroke-width="{2.5*s}"/>')
    # Фиксирующие анкерные кронштейны
    for kx in [cx - 60*s, cx + 45*s]:
        g.append(f'<rect x="{kx}" y="{cy + 5*s}" width="{15*s}" height="{30*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')
        g.append(f'<circle cx="{kx + 7.5*s}" cy="{cy + 15*s}" r="{2.5*s}" fill="#787e87"/>')
    return "\n".join(g)

def draw_detail_bevel_gears(cx, cy, s=1.15):
    # Деталь 3: Коническая зубчатая передача 90°
    g = []
    # Валы
    g.append(f'<rect x="{cx - 6*s}" y="{cy - 80*s}" width="{12*s}" height="{140*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
    g.append(f'<rect x="{cx - 70*s}" y="{cy - 6*s}" width="{140*s}" height="{12*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
    # Подшипниковый узел
    g.append(f'<rect x="{cx + 15*s}" y="{cy - 20*s}" width="{32*s}" height="{40*s}" rx="{3*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
    # Горизонтальная коническая шестерня (зубья на скошенном венце)
    g.append(f'<polygon points="{cx-45*s},{cy-35*s} {cx+45*s},{cy-35*s} {cx+30*s},{cy-12*s} {cx-30*s},{cy-12*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{2*s}"/>')
    for zx in [-35, -20, -5, 10, 25, 40]:
        g.append(f'<line x1="{cx + zx*s}" y1="{cy - 35*s}" x2="{cx + (zx*0.7)*s}" y2="{cy - 12*s}" stroke="#594312" stroke-width="{2*s}"/>')
    # Вертикальная коническая шестерня
    g.append(f'<polygon points="{cx-35*s},{cy-45*s} {cx-12*s},{cy-30*s} {cx-12*s},{cy+30*s} {cx-35*s},{cy+45*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{2*s}"/>')
    for zy in [-35, -20, -5, 10, 25, 40]:
        g.append(f'<line x1="{cx - 35*s}" y1="{cy + zy*s}" x2="{cx - 12*s}" y2="{cy + (zy*0.7)*s}" stroke="#594312" stroke-width="{2*s}"/>')
    return "\n".join(g)

def draw_detail_flywheel(cx, cy, s=1.1):
    # Деталь 4: Маховик со спицами и кривошипом
    g = []
    # Обод маховика
    g.append(f'<circle cx="{cx}" cy="{cy}" r="{62*s}" fill="none" stroke="url(#ironH)" stroke-width="{14*s}"/>')
    g.append(f'<circle cx="{cx}" cy="{cy}" r="{69*s}" fill="none" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')
    g.append(f'<circle cx="{cx}" cy="{cy}" r="{55*s}" fill="none" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')
    # Ступица
    g.append(f'<circle cx="{cx}" cy="{cy}" r="{18*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{2*s}"/>')
    g.append(f'<circle cx="{cx}" cy="{cy}" r="{6*s}" fill="#1c1e21"/>')
    # Спицы
    for i in range(6):
        ang = i * (math.pi / 3)
        fx = cx + math.cos(ang) * (55*s)
        fy = cy + math.sin(ang) * (55*s)
        g.append(f'<line x1="{cx}" y1="{cy}" x2="{fx:.1f}" y2="{fy:.1f}" stroke="url(#ironH)" stroke-width="{5*s}"/>')
    # Кривошипный палец (crank pin)
    cpx = cx + math.cos(math.pi / 4) * (36*s)
    cpy = cy + math.sin(math.pi / 4) * (36*s)
    g.append(f'<circle cx="{cpx:.1f}" cy="{cpy:.1f}" r="{7*s}" fill="url(#brassH)" stroke="#3e2d09" stroke-width="{1.5*s}"/>')
    g.append(f'<circle cx="{cpx:.1f}" cy="{cpy:.1f}" r="{3*s}" fill="#ffffff"/>')
    return "\n".join(g)

def draw_detail_piston(cx, cy, s=1.1):
    # Деталь 5: Цилиндр, поршень и шатун
    g = []
    # Цилиндр (продольный разрез)
    g.append(f'<rect x="{cx - 70*s}" y="{cy - 28*s}" width="{75*s}" height="{56*s}" rx="{4*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{2*s}"/>')
    g.append(f'<rect x="{cx - 65*s}" y="{cy - 22*s}" width="{65*s}" height="{44*s}" fill="#202225"/>')
    # Поршень внутри
    g.append(f'<rect x="{cx - 45*s}" y="{cy - 20*s}" width="{24*s}" height="{40*s}" rx="{2*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{1.5*s}"/>')
    # Шток
    g.append(f'<rect x="{cx - 21*s}" y="{cy - 5*s}" width="{38*s}" height="{10*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')
    # Крейцкопф и шарнир
    g.append(f'<circle cx="{cx + 17*s}" cy="{cy}" r="{9*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{1.5*s}"/>')
    # Шатун
    g.append(f'<line x1="{cx + 17*s}" y1="{cy}" x2="{cx + 65*s}" y2="{cy + 25*s}" stroke="url(#ironH)" stroke-width="{7*s}" stroke-linecap="round"/>')
    g.append(f'<circle cx="{cx + 65*s}" cy="{cy + 25*s}" r="{8*s}" fill="url(#brassH)" stroke="#4a370e" stroke-width="{1.5*s}"/>')
    return "\n".join(g)

def draw_detail_hopper(cx, cy, s=1.1):
    # Деталь 6: Загрузочный бункер с ребрами жесткости и заклепками
    g = []
    # Листовой бункер
    g.append(f'<polygon points="{cx-65*s},{cy-60*s} {cx+65*s},{cy-60*s} {cx+28*s},{cy+35*s} {cx-28*s},{cy+35*s}" fill="url(#ironV)" stroke="#1a1c1e" stroke-width="{2.5*s}"/>')
    # Внутренняя полость
    g.append(f'<polygon points="{cx-55*s},{cy-56*s} {cx+55*s},{cy-56*s} {cx+22*s},{cy-25*s} {cx-22*s},{cy-25*s}" fill="#1f2124"/>')
    # Усиливающие ребра и заклепки
    g.append(f'<line x1="{cx-45*s}" y1="{cy-56*s}" x2="{cx-15*s}" y2="{cy+35*s}" stroke="url(#ironH)" stroke-width="{3*s}"/>')
    g.append(f'<line x1="{cx+45*s}" y1="{cy-56*s}" x2="{cx+15*s}" y2="{cy+35*s}" stroke="url(#ironH)" stroke-width="{3*s}"/>')
    for y_riv in [-45, -25, -5, 15]:
        g.append(f'<circle cx="{cx-55*s + (y_riv+45)*0.35*s}" cy="{cy + y_riv*s}" r="{2.2*s}" fill="#787e87"/>')
        g.append(f'<circle cx="{cx+55*s - (y_riv+45)*0.35*s}" cy="{cy + y_riv*s}" r="{2.2*s}" fill="#787e87"/>')
    # Камни, загружаемые сверху
    g.append(f'<polygon points="{cx-22*s},{cy-48*s} {cx-6*s},{cy-58*s} {cx+8*s},{cy-45*s} {cx-8*s},{cy-32*s}" fill="#6b6f75" stroke="#25272a" stroke-width="{1.5*s}"/>')
    g.append(f'<polygon points="{cx+5*s},{cy-40*s} {cx+22*s},{cy-48*s} {cx+26*s},{cy-30*s} {cx+12*s},{cy-22*s}" fill="#52555a" stroke="#25272a" stroke-width="{1.5*s}"/>')
    return "\n".join(g)

def draw_detail_chimney(cx, cy, s=1.1):
    # Деталь 7: Выхлопная труба с муфтами, кронштейнами и оголовком
    g = []
    # Труба
    g.append(f'<rect x="{cx - 16*s}" y="{cy - 85*s}" width="{32*s}" height="{155*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')
    # Кольца и хомуты с болтами
    for y_col in [-45, 10, 50]:
        g.append(f'<rect x="{cx - 20*s}" y="{cy + y_col*s}" width="{40*s}" height="{10*s}" rx="{2*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{1.5*s}"/>')
        g.append(f'<circle cx="{cx - 16*s}" cy="{cy + (y_col+5)*s}" r="{2*s}" fill="#888e96"/>')
        g.append(f'<circle cx="{cx + 16*s}" cy="{cy + (y_col+5)*s}" r="{2*s}" fill="#888e96"/>')
    # Оголовок / дефлектор трубы
    g.append(f'<polygon points="{cx-26*s},{cy-85*s} {cx+26*s},{cy-85*s} {cx},{cy-105*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')
    # Стойки дефлектора
    g.append(f'<line x1="{cx-16*s}" y1="{cy-85*s}" x2="{cx-16*s}" y2="{cy-75*s}" stroke="#1c1e21" stroke-width="{3*s}"/>')
    g.append(f'<line x1="{cx+16*s}" y1="{cy-85*s}" x2="{cx+16*s}" y2="{cy-75*s}" stroke="#1c1e21" stroke-width="{3*s}"/>')
    # Струя дыма
    g.append(f'<ellipse cx="{cx}" cy="{cy-115*s}" rx="{18*s}" ry="{12*s}" fill="url(#smokePuff)" opacity="0.6"/>')
    return "\n".join(g)

def draw_detail_chute(cx, cy, s=1.1):
    # Деталь 8: Разгрузочный лоток и дробленая фракция
    g = []
    # Наклонный короб лотка
    g.append(f'<polygon points="{cx+35*s},{cy-55*s} {cx-45*s},{cy-10*s} {cx-35*s},{cy+15*s} {cx+45*s},{cy-30*s}" fill="url(#ironH)" stroke="#181a1c" stroke-width="{2*s}"/>')
    g.append(f'<polygon points="{cx+30*s},{cy-52*s} {cx-42*s},{cy-8*s} {cx-38*s},{cy+2*s} {cx+34*s},{cy-42*s}" fill="#202225"/>')
    # Крепежная лапа
    g.append(f'<rect x="{cx + 15*s}" y="{cy - 25*s}" width="{12*s}" height="{40*s}" fill="url(#ironH)" stroke="#1a1c1e" stroke-width="{1.5*s}"/>')
    # Высыпающийся щебень
    g.append(f'<ellipse cx="{cx - 50*s}" cy="{cy + 35*s}" rx="{35*s}" ry="{16*s}" fill="#63666b" stroke="#36383b" stroke-width="{1.5*s}"/>')
    for ox, oy in [(-12, 3), (-2, -5), (8, 2), (-18, -2), (15, 6)]:
        g.append(f'<circle cx="{cx - 50*s + ox*s}" cy="{cy + 35*s + oy*s}" r="{3*s}" fill="#888c92"/>')
    return "\n".join(g)

detail_funcs = [
    draw_detail_upper_stone,
    draw_detail_lower_stone,
    draw_detail_bevel_gears,
    draw_detail_flywheel,
    draw_detail_piston,
    draw_detail_hopper,
    draw_detail_chimney,
    draw_detail_chute,
]

for idx, func in enumerate(detail_funcs):
    bx = start_x + idx * (card_w + card_gap)
    by = 345
    add_card(bx, by, card_w, card_h)
    svg.add(func(bx + card_w // 2, by + card_h // 2, s=1.0))


# =========================================================================
# 3. НИЖНЯЯ СЕКЦИЯ: 8-КАДРОВЫЙ АНИМАЦИОННЫЙ СТОРИБОРД (STORYBOARD)
# =========================================================================
# Y: 645 .. 1060 (H=415). 8 ячеек шириной ~226px
# Строго идентичная изометрическая камера, последовательное развитие цикла:
sb_y = 645
sb_h = 415

storyboard_frames = [
    # (fly_deg, stone_deg, pist_ratio, smoke, steam, dust, rocks, gravel)
    (0.0,   0.0,   0.0, 0.0,  0.0,  0.0,  False, 0.0),   # FRAME 1 - IDLE
    (45.0,  15.0,  0.3, 0.0,  0.35, 0.0,  False, 0.0),   # FRAME 2 - STARTUP
    (110.0, 35.0,  0.8, 0.15, 0.6,  0.25, False, 0.0),   # FRAME 3 - ACCELERATION
    (210.0, 65.0,  0.4, 0.45, 0.4,  0.4,  True,  0.15),  # FRAME 4 - ROCK FEEDING
    (330.0, 105.0, 0.9, 0.85, 0.7,  0.8,  True,  0.5),   # FRAME 5 - FULL OPERATION
    (480.0, 160.0, 0.5, 0.95, 0.8,  1.0,  True,  0.9),   # FRAME 6 - ACTIVE CRUSHING
    (620.0, 205.0, 0.2, 0.4,  0.3,  0.4,  False, 1.0),   # FRAME 7 - SLOWDOWN
    (0.0,   0.0,   0.0, 0.0,  0.0,  0.0,  False, 1.0),   # FRAME 8 - STOPPED (IDLE)
]

for idx, (f_fly, f_stone, f_pist, f_smk, f_stm, f_dst, f_rck, f_grv) in enumerate(storyboard_frames):
    bx = start_x + idx * (card_w + card_gap)
    add_card(bx, sb_y, card_w, sb_h)
    svg.add(draw_machine(
        cx=bx + card_w // 2,
        cy=sb_y + sb_h // 2 + 10,
        scale=0.92,
        view_angle="front_iso",
        flywheel_deg=f_fly,
        stone_deg=f_stone,
        piston_ratio=f_pist,
        smoke_level=f_smk,
        steam_level=f_stm,
        dust_level=f_dst,
        has_rocks=f_rck,
        crushed_gravel_level=f_grv
    ))

# Запись файла
with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write(svg.render())

print(f"Generated successfully: {OUT_PATH} ({os.path.getsize(OUT_PATH)} bytes)")
