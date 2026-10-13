# Расширение фермы — промты для 3D-моделей

Промты для генерации недостающих моделей раздела 8 мастер-плана
(«Расширение фермы»): 2 ягодных куста и 3 фруктовых дерева.
По одному запросу на модель, с общим началом. Стиль — как у существующих
ассетов (`docs/art/storage_reference_prompt.md`, `crusher_reference_prompt.md`):
стилизованный полуреализм, «Stardew-meets-realistic», без людей.

Сейчас в игре стоят заглушки: кусты ежевики/облепихи переиспользуют геометрию
красного куста с перекрашенными ягодами (`berry_bush_black/seа.tscn`),
фруктовые деревья собраны примитивами кодом (`fruit_tree.gd`: ствол-цилиндр,
крона-сфера, плоды-шарики). Сгенерированные модели заменяют их 1:1.

## Общее начало (EN)

> Stylized semi-realistic 3D game asset, three-quarter front view from a high
> isometric camera, for a cozy post-storm survival-crafting game
> ("After The Storm"). Clean readable silhouette, soft daylight, rich but muted
> natural materials, no people, no text, no ground plane, 4k, octane-like
> render, Stardew-meets-realistic style.

Требования ко всем моделям (для исполнителя / генератора с GLB/GLTF выходом):

- Треугольников: кусты — до 8 тыс., деревья — до 15 тыс.
- Ягоды и плоды — **отдельным мешем и отдельным материалом** (нужны варианты
  «с урожаем / без урожая»: `FullModel` показывает ягоды, `EmptyModel` — тот же
  куст без меша ягод, как `berry_bush_red_model.tscn` / `berry_bush_red_empty_model.tscn`).
- Листва — двусторонний материал, тон в цветах вершин (см. `bark_oak`/`leaves`).
- Без скелета и анимаций; колизии и посадка — кодом, не моделью.
- Фасад / «лицо» модели — на **+Z**.

**Negative:** sci-fi, neon, cartoon outline, photorealistic macro, people,
animals, text, watermark, blurry, low-poly flat shading, ground plane, pot, fence.

## 1. Куст ежевики (blackberry)

> …**a lush blackberry bush**, about 1.2 m tall and wide: arching thorny canes
> from the base, dense serrated green leaves, clusters of large ripe berries
> from red to **near-black purple** (a few unripe red ones). Slightly wild,
> forest-edge look.

Цвета игры: ягоды тёмно-фиолетовые (`albedo ≈ 0.08, 0.02, 0.11`,
`berry_bush_berry_black_material.tres`), урожай 4 ягоды за сбор.

## 2. Куст облепихи (sea buckthorn)

> …**a sea buckthorn bush**, about 1.4 m tall: upright grey-brown twiggy
> branches, narrow silvery-green willow-like leaves, dense clusters of small
> round **bright orange-amber berries** packed along the stems. Hardy northern
> look, slightly thorny.

Цвета игры: ягоды янтарно-оранжевые (`albedo ≈ 0.93, 0.42, 0.05`,
`berry_bush_berry_sea_material.tres`), урожай 8 ягод за сбор.

## 3. Яблоня (apple tree)

> …**a small garden apple tree**, about 4 m tall: short sturdy trunk with
> rough bark, rounded crown of fresh green foliage (`canopy ≈ 0.28, 0.55,
> 0.22`), a dozen round **red apples** (`fruit ≈ 0.88, 0.18, 0.15`) hanging
> among the leaves. Tidy orchard look, modelled without roots or ground.

Игра: рост 3 игровых дня, урожай 4–8 яблок, сбор осенью.

## 4. Груша (pear_tree)

> …**a small garden pear tree**, about 4.5 m tall, slightly pyramidal crown:
> straight trunk, elongated glossy green leaves (`canopy ≈ 0.32, 0.58, 0.24`),
> half a dozen **yellow-green teardrop pears** (`fruit ≈ 0.82, 0.74, 0.22`).
> Same orchard style as the apple tree, no roots or ground.

Игра: рост 4 игровых дня, урожай 3–6 груш, сбор осенью.

## 5. Вишня (cherry_tree)

> …**a small garden cherry (sour cherry) tree**, about 3.5 m tall: slender
> dark-barked trunk, airy crown of small pointed green leaves
> (`canopy ≈ 0.35, 0.62, 0.26`), numerous pairs of small round **dark-red
> cherries** (`fruit ≈ 0.72, 0.08, 0.14`) on thin stems. Same orchard style,
> no roots or ground.

Игра: рост 3 игровых дня, урожай 6–12 вишен, сбор летом.

## Как это станет моделями

- Кусты: GLB → `tools/import_berry_bush.gd` (как `berry_bush.glb` раньше) →
  `assets/models/berry_bush/`, затем замена мешей/материалов в
  `berry_bush_black_model.tscn` / `berry_bush_sea_model.tscn`
  (и `_empty`-варианты без меша ягод). Скрипт, сцены кустов и спавнер менять
  не нужно — параметры (`berry_yield`, `grow_seasons`, `regrow_hours`) уже стоят.
- Деревья: замена примитивов в `FruitTree._build_visuals()` на импортированные
  меши (ствол + крона + плоды отдельными `MeshInstance3D`, плоды гаснут через
  `_fruits_node.visible`). Стадии роста остаются масштабом
  (`0.3 / 0.65 / 1.0` в `_update_visuals`), саженец — та же модель маленькой.
- После замены: прогнать `test_berry_bushes` и `test_farm_expansion`,
  обновить этот файл и раздел «Фруктовый сад» в `docs/DOCUMENTATION.md`.
