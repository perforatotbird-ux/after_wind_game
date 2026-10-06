---
date: 2026-07-27
updated: 2026-08-29
description: "CloudByte/TGCloud frozen component restrictions, guarded subsystem zones, and mandatory operational guidelines for AI agents."
tags: [memory, cloudbyte, tgcloud, rules, frozen-components, guidelines]
source: mcp-capture
origin: "replit"
session: "2026-07-27T15:24:41.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte Rules and Frozen Components

## Guarded Codebase Zones (Modification Strictly Prohibited Without Explicit User Approval)

To maintain system stability, security, and prevent data corruption, AI agents must **NEVER** modify the following components unless explicitly requested by the user:

### 0. ABSOLUTE Ban on Editing `app.env` (highest priority, added 2026-08-16)

> **КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО** изменять, перезаписывать, пересоздавать, переформатировать или удалять `app.env` и `app.env.example` любым способом без ЯВНОГО и ПРЯМОГО запроса пользователя с указанием конкретного ключа и значения. Этот запрет стоит выше всех остальных правил, включая правило полных перезаписей файлов (на env-файлы оно НЕ распространяется).

- **Запрещено**: `write_file`/`edit_file` в env-файлы; shell-редиректы, `sed -i`; `python-dotenv set_key`; вызовы `config.env_set()`/`env_delete()` из скриптов и тестов; запуск тестов/скриптов, дёргающих `POST /api/auth/setup`, `/api/auth/settings/update`, `/api/auth/env` против реального окружения (они перезаписывают `app.env`).
- **Критические ключи** (потеря/подмена = потеря входа и/или необратимая невозможность расшифровки хранилища): `APP_PASSWORD_HASH`, `SESSION_SECRET`, `ENCRYPTION_MASTER_SALT`, `ENCRYPTION_WRAPPED_KEY`, `ENCRYPTION_RECOVERY_KEY`, `TG_SESSION_STRING`, `TG_API_ID`, `TG_API_HASH`.
- **Разрешено только чтение** (`env_get`, grep) с обязательным маскированием секретов в выводе (первые ~8 символов + «…», полное значение не печатать).
- **Обнаружили внезапное изменение `app.env`** — остановиться и доложить пользователю, молча не «исправлять».
- **Единственное исключение**: явный конкретный запрос пользователя (пример: «сбрось пароль входа на X»). Порядок: бэкап старого значения в `backups/` → изменение только указанного ключа → проверка → отчёт.
- **Прецедент (16.08.2026)**: перезапись `APP_PASSWORD_HASH` через сохранение настроек с заполненным «новым паролем» лишила входа (vault-пароль работал, т.к. `ENCRYPTION_*` не затрагиваются). Пароль восстанавливали вручную с бэкапом хеша в `backups/APP_PASSWORD_HASH.backup-*.txt`.

### 1. File System Core & VFS (`backend/database.py`, `backend/repositories/`)
- Models `VFile`, `Folder`, `FolderClosure`.
- `rebuild_closure_table`, `create_folder`, `move_folder` CTE logic.
- File collection routines for ZIP archive creation.

### 2. Telegram Transport (`backend/tg/`)
- `uploader.py` chunking & throttling logic.
- `downloader.py` streamer failover (`stream_file_linear`, `FastStreamer`).
- `manager.py` Pyrogram session patches & semaphore management.
- `incoming.py` batch album grouping (`media_group_id`).

### 3. Encryption (`backend/encryption.py`)
- 32-byte header format (16B salt + 12B nonce + 4B block size LE).
- AES-256-GCM block encryption/decryption functions.
- Master Key derivation via Argon2id.

### 4. Selection, Trash & Maintenance
- Endpoints `/api/maintenance/empty-trash`, `file_crud.py` delete routes.
- Selection state in Zustand store (`selectedItems`) and drag-and-drop hooks.
- **Trash Deletion Optimization**: `empty-trash` (`backend/routers/maintenance.py`) and `FileService.delete_files` (`backend/services/file_service.py`) perform PostgreSQL DB record deletion immediately (< 50ms) and dispatch Telegram message payload deletions via non-blocking `asyncio.create_task` background tasks. This prevents UI modals from hanging during long Telegram network API calls.

### 5. Music Mode & Android App
- `android_app/` source code.
- mDNS Zeroconf registration (`_cloudbyte._tcp.local.`).
- Music visualizers (Vinyl, Cassette, CD) and audio pre-caching mechanism.

### 6. Configuration & Environment Files
- `backend/config.py` — правки только по явному запросу.
- `app.env`, `app.env.example` — см. ABSOLUTE Ban (раздел 0): только чтение, запись запрещена без явного запроса.

## Mandatory Agent Protocol
1. **Full File Overwrites Only**: Always overwrite files completely using `write_to_file` with `Overwrite=True`. Partial chunk edits are prohibited. **EXCEPTION: `app.env`/`app.env.example` — запрещено перезаписывать вовсе (раздел 0).**
2. **NO Auto-Restarts**: AI agents must NEVER execute `restart.bat` or automatically restart the application. All restarts are executed exclusively by the user.

## Log of Authorized Frozen-Zone Deviations

- **29.08.2026** (аудит обработки ошибок, явное разрешение пользователя: «исправь все ошибки, даже в замороженных зонах»):
  - `tg/downloader.py` — единственная правка: bare `except: continue` → `except (ValueError, TypeError): continue` в `stream_file_from_saved` (парсинг `account_map`). Логика failover/Atomic Start не тронута.
  - `tg/manager.py` — bare `except: limit = 2` → `except (ValueError, TypeError)` в `get_account_download_semaphore` и `get_background_semaphore`. Монkey-patch `save_file`, `SLEEP_THRESHOLD=60`, семафоры — без изменений.
  - `frontend/src/hooks/useSearch.js` (зона «Поиск») — в catch добавлен `console.warn` перед существующим graceful fallback (пустой результат); логика поиска и дебаунс не изменены.
- **29.08.2026** (аудит запросов к БД, явное разрешение пользователя: «выполни все улучшения также и в замороженных зонах»):
  - `auto_integrity_service.py` — per-id `SELECT ... FOR UPDATE` в `_process_done_jobs` заменён на один батчевый запрос с `ORDER BY id` (защита от дедлоков сохранена). Логика проверки/ремонта не тронута.
  - `integrity_service.py` — удаление dead-файлов в `apply_repairs` переведено на bulk `DELETE ... IN`; цикл ремонта broken-файлов не тронут.
  - `mirror_service.py` — `create_mirror_jobs`: один EXISTS-запрос по всем аккаунтам; `_process_pending_jobs` и `_run_bulk_mirror`: префетч VFile/`account_map` одним запросом (read-only), FOR UPDATE путь записи сохранён по-джобово.
  - `routers/file_crud.py` `tracks-recursive` (Music API) — добавлен `load_only` тех же столбцов `FileResponseModel`, контракт ответа не изменён.
  - Зона «Поиск» — применены GIN-индексы pg_trgm на `vfiles.name`/`folders.name` (только SQL-миграция живой БД, код поиска не менялся).
