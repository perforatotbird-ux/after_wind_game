# Дробилка камня — промт для референса

Промт, по которому нарисован референс `crusher_reference.svg` и собрана модель
(`tools/create_crusher_model.py`). Его же можно отдать генератору изображений.

## Промт (EN, для генератора)

> Stylized semi-realistic 3D game asset, three-quarter front view, of a small **post-storm
> scavenged jaw crusher** for a cozy survival-crafting game ("After The Storm").
> A squat steel **jaw-crusher housing** painted **industrial safety yellow**, paint chipped
> and worn to bare dark steel on the edges, rust streaks running down from bolts, thick
> vertical **reinforcing ribs** and big hex bolts on the side cheeks. On top a wide
> **riveted steel hopper** (trapezoid funnel) with yellow–black hazard stripes on the rim,
> half full of grey rubble stones. Two big **cast-iron spoked flywheels** (six curved spokes,
> dark iron, polished worn rim) on both sides on a heavy eccentric shaft with greasy
> bearing blocks; between them the **swing jaw (pitman)** top with a round bearing housing.
> Behind it a weathered green **electric motor** on a steel bracket with cooling fins,
> a small pulley and a black **V-belt** going to the right flywheel; a power cable with a
> rubber sleeve snakes to the ground. The machine stands on a **skid frame of two steel
> I-beams on old wooden sleepers**, bolted down. At the front bottom a **tilted discharge
> chute** of dented galvanized sheet pours fine **grey gravel / stone dust** onto a small
> pile. Repair details: a welded patch plate, mismatched bolts, a wire-tied warning sign
> "ДРОБИЛКА", a red stop button box with a green running lamp. Sunny meadow daylight,
> soft shadows, rich materials (painted metal, cast iron, rubber, wood, stone), clean
> readable silhouette for an isometric camera, no text except the sign, 4k, octane-like
> render, Stardew-meets-realistic style.

**Negative:** sci-fi, glowing neon, futuristic panels, oversized, clutter on the ground,
people, cartoon outline, blurry, low-poly flat shading.

## Что важно для модели

| Деталь | Размер / цвет | Анимация |
|---|---|---|
| Рама: 2 двутавра на шпалах | 1.9 × 1.5 м, ржавый металл, серое дерево | — |
| Корпус (щёки с рёбрами) | 1.0 × 1.0 × 0.9 м, жёлтая краска `#d9a520`, сколы | чуть дрожит при работе |
| Бункер | верх 1.35 × 1.2 м, полосы жёлто-чёрные, камни внутри | камни подпрыгивают |
| Маховики ×2 | Ø 1.05 м, чугун `#2b2d30`, 6 спиц | вращаются |
| Подвижная щека (шатун) | корпус подшипника сверху | ходит по эксцентрику (±3 см) |
| Мотор + шкив + ремень | зелёный `#4f6b4a`, шкив Ø 0.22 м | шкив вращается в 4.8 раза быстрее |
| Лоток и кучка щебня | оцинковка `#9aa3a8`, щебень `#8d8b86` | сыплется щебень, пыль |
| Лампа «работа» | зелёная | горит только в работе |

Фасад (лоток) — к двору (**+Z** в Godot), мотор — сзади, маховики — по бокам (ось X).
Габарит по земле ≤ 2.5 × 2.9 м, чтобы не задевать печь справа.
