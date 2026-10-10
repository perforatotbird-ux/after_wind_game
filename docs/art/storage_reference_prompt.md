# Склад продукции — промт для референса

Промт, по которому нарисован референс `storage_reference.svg` и собрана модель
(`tools/create_storage_model.py`). Его же можно отдать генератору изображений — по одному
запросу на состояние, с общим началом.

## Общее начало (EN)

> Stylized semi-realistic 3D game asset, three-quarter front view from a high isometric camera,
> of a **small farm storage building** for a cozy post-storm survival-crafting game
> ("After The Storm"). Footprint about 4.8 × 3.8 m, gabled roof, the main gate faces the camera.
> Sunny meadow daylight, soft shadows, rich materials, clean readable silhouette, no people,
> no text except the sign, 4k, octane-like render, Stardew-meets-realistic style.

## Состояние 1 — разрушенный склад (стадия 0)

> …**ruined by a storm**: a cracked concrete floor slab broken into three tilted pieces with
> rubble in the cracks; one charred corner post still standing, one snapped with splinters, one
> leaning post and a stump; a jagged fragment of the plank back wall; the **ridge beam fallen
> diagonally** across the floor; rusty corrugated roof sheets — one resting on the beam with a
> hole, one crumpled on the ground, one leaning against the wall; a broken crate under a
> **torn faded green tarp**, a tipped-over crate, a toppled plank shelf, a rusty barrel on its
> side, scattered planks, a fallen sign board "СКЛАД".

## Состояние 2 — восстановленный амбар (стадии 1–2)

> …**rebuilt as a wooden barn**: frame of square posts on fieldstone footings, raised plank floor,
> knee braces, tie beams, rafters and purlins; supplies inside (crates, burlap sacks, a blue
> barrel). *Stage 1:* only the frame, covered by a **green tarp stretched over the rafters**,
> sagging between purlins, tied with ropes to wooden stakes. *Stage 2:* weathered vertical board
> walls with a few fresh pine replacements, a small cross-framed window on each side, a
> **double plank gate with Z-bracing** and black iron strap hinges (left leaf ajar), old
> galvanized corrugated roof with one rusty sheet, ridge cap, barge boards, a white sign
> "СКЛАД" above the gate, a wooden rain barrel at the corner.

## Состояние 3 — логистический комплекс (стадия 3)

> …**upgraded to a small logistics hub**: rubble-stone plinth with concrete steps, **fired-brick
> lower walls and corner pilasters**, upper walls of **red-ochre lap siding** with worn paint and
> white trim, new galvanized corrugated roof with two translucent skylight sheets, gutters and
> downpipes, a ridge vent; a **green roll-up shutter gate** two-thirds open showing a blue/orange
> pallet rack with crates and sacks and a pallet with boxes; two green gooseneck lamps; a sign
> "СКЛАД №1". On the right a **sorting lean-to** with a galvanized roof and three open bins
> (yellow — stone, blue — scrap metal, green — firewood) under a "СОРТИРОВКА" sign, and a
> yellow **jib crane with a hand winch on cast-iron gears**: a crank pinion drives a big gear
> with a rope drum, the chain hangs from a trolley and lifts a crate from a pallet.

**Negative:** sci-fi, neon, modern glass office, skyscraper, oversized, clutter, people, cartoon
outline, blurry, low-poly flat shading.

## Как это стало моделью

- Три состояния — три запечённых атласа (цвет 2048, нормали и ORM 1024), один скрипт Blender
  с переменной `STORAGE_STATE`.
- Стадии 1 и 2 — одно состояние «амбар»: общий меш каркаса, на стадии 1 к нему добавляется тент,
  на стадии 2 — стены, ворота и кровля.
- Подвижные части подъёмника (шестерня, рукоять, цепь, крюк с ящиком) — отдельные меши
  с центром на осях; анимация — `scripts/buildings/storage_hoist_animator.gd`.
