# Инструменты главного героя

- `pickaxe_equipped_mesh.tres` — тот же нормализованный `pickaxe_inhand.glb`, уже включённый в проект (pipeline `normalize_library_tools.py`, Quaternius Pickaxe_Bronze). Сохраняет существующие BaseColor/Normal/ORM текстуры. Используется один меш в idle и mine вместо отделённого от исходной AI-модели инструмента, похожего на топор.
- `scenes/tools/hoe_inhand.tscn` — собственная геометрия мотыги: деревянный черенок, две обмотки, стальная втулка, кованое полотно, заточенная кромка. Текстура древесины — собственный материал игрового костра. Старые сцены shovel_model / shovel_inhand — совместимые оболочки новой модели.
- `assets/tools/hoe_icon.tres` — собственный силуэт мотыги, 48×48 RGBA, PortableCompressedTexture2D с сохранёнными сжатыми данными.
- `assets/animations/hero_actions.tres` — отдельный клип hoe_dig: опора на idle существующего ретаргета UAL, умеренный наклон Spine1/Spine2. Двуручный хват и траектория инструмента — SkeletonModifier3D после анимации корпуса.

Пересборка из корня проекта:

```bash
godot --headless --path . -s tools/create_hoe_model.gd
godot --headless --path . -s tools/create_hero_actions.gd
```

В игровых ID сохранены shovel / iron_shovel: это ключ совместимости старых сейвов, не отображаемое название инструмента.
