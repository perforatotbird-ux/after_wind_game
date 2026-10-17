# AGENTS.md

Обязательные правила для любого агента, работающего в этом репозитории. Архитектура — [DEVELOPER_HANDOVER.md](DEVELOPER_HANDOVER.md), документация — [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md).

## Постоянные правила

1. **После любого изменения обновляй документацию и дневник разработчика.**
   - Дневник разработчика — `DEVELOPER_HANDOVER.md`: новая секция `### <Название>` в конец файла, хронологически, в стиле соседних секций.
   - `docs/DOCUMENTATION.md` — править затронутые разделы (инвентарь, иконки, таблицы файлов и скриптов и т. п.).
   - Оба файла в UTF-8; консоль Windows (cp1251) искажает русский текст — читать и писать их через файловые инструменты, а не через stdout.
2. **Прогоняй только затронутые тесты, а не весь пакет.** Полный прогон — ~15 минут (63 теста); указывать адресные фильтры.
3. **После завершённой работы — коммит и пуш.** Однострочный conventional commit (en), затем `git push origin main`.

## Команды

- Godot: `K:\Godot_v4.7.2-stable_win64.exe`
- Python: `C:\Users\inval\miniconda3\python.exe`
- Тесты (workdir — корень проекта): `python tools/run_tests.py --godot "K:\Godot_v4.7.2-stable_win64.exe" --filter <подстрока>`
  - `--filter` принимает одну подстроку; для нескольких — цикл.
  - Harness считает прогон проваленным по строкам `ERROR` / `FAIL` / `ПРОВАЛЕН`; логи — в `outputs/test-results/`.
  - Раннер копирует проект вместе с `.godot`, поэтому нужны готовые `.import`.
  - Копии ложатся в `%TEMP%\after-wind-tests-*`; при `[WinError 112] Недостаточно места на диске` (на C: бывает <1 ГБ) удалить старые копии: `Get-ChildItem $env:TEMP -Directory -Filter "after-wind-tests-*" | Remove-Item -Recurse -Force`.
- Импорт ассетов: `& "K:\Godot_v4.7.2-stable_win64.exe" --headless --editor --path "K:\After Wind" --import`

## Конвенции

- Язык документации — русский; сообщения коммитов — однострочные conventional (en).
- «Локальный репозиторий» = локальный коммит: не искать bare-репозиторий по внешним папкам (`K:\*`), дальше — push в `origin main`.
