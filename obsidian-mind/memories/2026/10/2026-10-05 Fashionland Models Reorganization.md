# 2026-10-05 Fashionland Models Reorganization

**Дата:** 05.10.2026  
**Статус:** Выполнено  
**Область:** `P:\Video\F\Fashionland Models\` и PostgreSQL VFS (`Drive P: / Video / F / Fashionland Models`, Root ID: `8901`)

---

## 1. Обзор задачи

Была проведена комплексная стандартизация, нормализация структуры подпапок и переименование видеофайлов по каноническим правилам `fashionland-rename-rules` для всех моделей Fashionland:
1. **Фаза 1:** Adrianna (1 файл)
2. **Фаза 2:** Ai (30 файлов)
3. **Фаза 3:** Модели на букву «A» (15 моделей, 108 файлов)
4. **Фаза 4:** Модели на букву «B» (Bella, Bethany, Betsy — 31 файл)
5. **Фаза 5:** Модели от Charlotte до Vivian (31 модель, 868 файлов):
   - `Charlotte`, `Danielle`, `Diana`, `Elena`, `Elona`, `Eva`, `Evelyn`, `Giselle`, `Hanna`, `Iris`, `Jessica`, `Katie`, `Kaylee`, `Lacey`, `Lauren`, `Lesya`, `Lexie`, `Marina`, `Mary`, `Megan`, `Mia`, `Mika`, `Multi Dolls`, `Olivia`, `Scarlett`, `Sofi`, `Sofie Doll`, `Sophia`, `Veronica`, `Violetta`, `Vivian`.

---

## 2. Ключевые операции и решения

1. **Канонизация папок:**
   - Все папки `Classic Collection` и `CC` переименованы в каноническое `Complete Collection` (на диске и в БД).
   - `Multi Doll` (ID: 14658) слита в `Multi Dolls` (ID: 8893) и удалена из БД; на диске папка переименована в `Multi Dolls`.
   - В модели `Kaylee` папка `PVT Edition` переименована в `Private Edition`.
   - В модели `Lesya` папка `Fashion Doll` переименована в `Fashion Dolls`.
   - Созданы необходимые подпапки для серий: `Fashion Kingdom`, `Fashion Stars`, `Limited Edition`, `The Club Edition`.

2. **Обработка дубликатов и спецфайлов:**
   - Из базы данных удалены записи `Multi Doll Giselle - Ai - 38a/38b` (ID: 196602, 196603) по прямому указанию пользователя.
   - Из базы данных удалена запись `Fashion Land - PRV - Kay07.mp4` (ID: 158582); файл оставлен на диске.
   - С диска и из БД удалены дубликаты H.265 (`FD-Diana-031a_H.265.mp4`, `FD-Diana-031b_H.265.mp4`, `FD-Lesya-014a_H.265.mp4`) и Dynamic HQ (`FK-Scarlett-015-Dynamic.mp4`).
   - Удалён дубликат Katie bonus video (`FL-Katie-Mika-bonus-video.mp4`), вторая копия перемещена в `Multi Dolls` как `Katie,Mika - Bonus.mp4`.
   - В модели `Mia` для 16 пар дублирующих разрешений одной сцены ко второй меньшей копии добавлен суффикс `_copy`.
   - `Alissa-CCVRXM01-Part2` (199.7 MB) выгружен из Telegram-кластера, помещен на диск в `Alissa\Complete Collection\CCVRXM01-Part2.rar`, а в БД перепривязан к папке Alissa `Complete Collection` (ID: 11486) как `CCVRXM-01 Part 2.rar`.

3. **Синхронизация и безопасность:**
   - Все 860 файлов обновлены в БД в рамках единой транзакции (COMMIT).
   - Сформирован и сохранён манифест полного отката `revert_manifest.json` (с резервной копией `revert_manifest_backup.json`).
   - Доработан инструмент отката `revert.py`, поддерживающий откат переименований, перемещений, слияния папок и восстановление удалённых записей.
