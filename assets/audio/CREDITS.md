# Звуки — источники и лицензии

Все сэмплы — **CC0 (общественное достояние)**: их можно свободно использовать, менять и распространять,
в том числе в коммерческих проектах, без обязательного указания авторства. Авторы всё равно указаны — из уважения.

Файлы `*.tres` здесь — текстовые ресурсы Godot (`AudioStreamOggVorbis`), собранные из исходников:
`python3 tools/build_sounds.py <папка_с_паками> /tmp/sfx_build` → `godot --headless --path . -s tools/import_sounds.gd -- /tmp/sfx_build`.
Скрипт обрезает тишину, делает затухание, нормализует громкость, переводит в моно OGG и склеивает фоновые петли кроссфейдом.

| Пак | Автор | Ссылка | Что взято |
|---|---|---|---|
| Impact Sounds | Kenney | https://kenney.nl/assets/impact-sounds | удары по дереву, камню (кирка), металлу; доски (стройка); мягкие удары (лопата, посадка); шаги по траве |
| RPG Audio | Kenney | https://kenney.nl/assets/rpg-audio | рубка (`chop`), подбор (ткань), выброс (кожа), монеты, шаги по грунту |
| Interface Sounds | Kenney | https://kenney.nl/assets/interface-sounds | клики, открытие/закрытие окон, ошибка, сбор ягод (`pluck`), урожай и готовность станка (`confirmation`) |
| Music Jingles | Kenney | https://kenney.nl/assets/music-jingles | фанфара победы (`jingles_SAX07`) |
| 30 CC0 SFX loops | rubberduck | https://opengameart.org/content/30-cc0-sfx-loops | запуск станка (`machine_01`) |
| 40 CC0 water / splash / slime SFX | rubberduck | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | плеск воды, набор воды, питьё |
| 80 CC0 RPG SFX | rubberduck | https://opengameart.org/content/80-cc0-rpg-sfx | монеты (`item_coins_01`) |
| Shovel Sound | OpenGameArt (CC0) | https://opengameart.org/content/shovel-sound | копание лопатой |
| AMB Rain Loop 1 | OpenGameArt (CC0) | https://opengameart.org/content/amb-rain-loop-1 | фон дождя |
| Park ambiences | OpenGameArt (CC0) | https://opengameart.org/content/park-ambiences | фон ветра |
| Ambient Bird Sounds | isaiah658 | https://opengameart.org/content/ambient-bird-sounds | пение птиц (в сухую погоду) |

**Сгенерированы** `tools/build_sounds.py` (подходящих бесплатных не нашлось): `swing_*` — свист замаха инструментом
(полосовой шум с развёрткой частоты), `eat_*` — хруст при еде (серия коротких отфильтрованных шумовых щелчков).
