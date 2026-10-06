---
date: 2026-07-27
description: "CloudByte/TGCloud detailed architecture, component layer breakdown, request execution lifecycle, background workers, and deferred initialization."
tags: [memory, cloudbyte, tgcloud, architecture, fastapi, backend]
source: mcp-capture
origin: "replit"
session: "2026-07-27T15:24:41.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte Architecture and Component Flow

## Layered System Architecture

```
[ Frontend (React 19 / Zustand) / Android Client ]
                       │ (HTTP REST / WebSockets / mDNS)
                       ▼
             [ FastAPI Router Layer ]
   (auth_router, file_crud, file_upload, file_download, folders, etc.)
                       │
                       ▼
           [ Service Layer (Business Logic) ]
   (UploadService, DownloadService, FileService, FolderService, etc.)
                       │
       ┌───────────────┴───────────────┐
       ▼                               ▼
[ Repository Layer / PostgreSQL ]   [ Telegram Cluster (`tg/`) ]
  (Database Models, Closure Table)    (MultiClientManager, Pyrogram)
```

## Core Backend Modules & Services (`backend/services/`)

1. **`upload_service.py`**:
   - Hybrid upload pipeline: Stream incoming payload to temporary disk buffer (`CUSTOM_TEMP_DIR`) without holding semaphores.
   - Chunking payload into 512KB/1MB parts, encrypting via `encrypt_stream`.
   - Dispatching chunks to Telegram accounts via `MultiClientManager` with `MAX_CONCURRENT_UPLOADS` limits.

2. **`download_service.py`**:
   - Manages linear streaming (`stream_file_linear`) and high-speed multiplexed download (`stream_file_from_saved`).
   - Integrates `FastStreamer` and True Mid-Stream Failover.
   - Generates and verifies download tickets for browser/mobile audio streaming.

3. **`folder_service.py` & `file_service.py`**:
   - Hierarchical VFS management.
   - Batch move/copy operations with Conflict Resolution (returns structured 409 responses on file collisions).
   - Recalculates folder statistics and updates PostgreSQL `Closure Table`.

4. **`mirror_service.py`**:
   - Robust 3-stage bulk mirroring across Telegram account cluster:
     1. Forward source message to target account.
     2. Discover message metadata on target.
     3. Update `account_map` in database.

5. **`auto_integrity_service.py` & `integrity_service.py`**:
   - Background worker inspecting completed `MirrorJob` entries with a 30-second Telegram indexing buffer.
   - Marks orphaned/missing files with `pending_deletion = True`.

6. **`websocket_service.py`**:
   - Real-time WebSocket event broadcaster notifying connected clients of upload progress, storage quota updates, and background repairs.

## Deferred Service Startup Pattern (`backend/main.py`)
To ensure rapid application boot times and prevent startup blocking during database wait cycles:
- `MirrorWorker` and `AutoIntegrityService` are initialized using `asyncio.create_task` **after** database readiness checks (`wait_for_db` with exponential backoff) and **before** `yield` in the FastAPI `lifespan()` handler.

## Concurrency & RAM Protection
- **`MAX_RAM_BUFFER_MB`**: Environment variable governing peak memory allocation for buffer streams.
- **`TG_MAX_CONCURRENT_TRANSMISSIONS`**: Controls maximum parallel Pyrogram RPC transmissions per account to avoid `FloodWait`.

## Error Handling Conventions (обновлено 2026-08-29)

По результатам аудита обработки ошибок внедрены единые правила (правка замороженных зон `tg/downloader.py` и `tg/manager.py` выполнена по явному разрешению пользователя):

- **Запрет bare `except:`**: все обработчики типизированы. Парсинг чисел/JSON/строк — `except (ValueError, TypeError)`; `json.loads` с `.get()` — `except (ValueError, AttributeError, TypeError)`; base64 — `except (ValueError, TypeError)` (`binascii.Error` наследует `ValueError`). Затронуты: `services/download_service.py`, `services/upload_service.py`, `services/cache_service.py`, `tg/downloader.py`, `tg/manager.py` (семантика fallback-логики не изменена).
- **Уровни логирования для «молчаливых» ошибок**: сбои записи temp-файлов в БД (`TransferRepository.add_temp_file` в `upload_service.py`, `file_crud.py`) и итоговой очистки temp-файлов подняты с `debug` до `warning` с описательным сообщением — это гарантирует diagnosability потери гарантии очистки. Best-effort `os.unlink` отдельных файлов остался на `debug` (шум Windows file-lock).
- **Фронтенд**: пустые `catch { }` в `TransferManager.jsx` (fetch/delete/cancel/clear/cancelAll) заменены на `console.error` с контекстом; в `useSearch.js` добавлен `console.warn` перед graceful fallback на пустой результат. `useUploadFlow.js` уже показывал toast — не тронут.
- **Известный ранее существовавший сбой**: `tests/test_auto_integrity_service.py::test_process_done_jobs_healthy` падает и на чистом HEAD (mock `db.execute` сопоставляет `str(stmt)` по подстроке «done», а SQLAlchemy 2.0 рендерит bound-параметры — совпадения нет). Также ранее существовавшие: `test_folder_tree.py` (IntegrityError), `test_chaos.py::test_upload_retry_account_switching`, `test_sync_stress.py::test_mirror_stress_50_files` — идентичны на HEAD и в рабочем дереве, к правкам обработки ошибок отношения не имеют.

## Database Query Optimizations (2026-08-29)

Аудит запросов к БД (модели, репозитории, ORM-вызовы) + внедрение оптимизаций по явному разрешению пользователя (включая замороженные зоны). Масштаб: vfiles ≈ 218k строк, folders ≈ 10.8k.

### Устранённые N+1
- **`FileService.delete_files` / `restore_files` / `move_files`** (`file_service.py`): корзина/восстановление — один `UPDATE ... WHERE id IN (...)` вместо SELECT+COMMIT на каждый файл; отмена джобов — bulk `update(TransferJob)`; статистика папок — `update_stats_batch` вместо цикла.
- **`FolderService.update_stats_batch`**: теперь инвалидирует кэш `folder_stats:{id}` и у всех предков (один запрос к `folder_closures`), эквивалент `recursive_up=True`; используется в `delete_files`, `delete_folders`, `restore_folders`, `move_folders`, `move_files`.
- **`move_folders`**: папки целевого родителя префетчатся одним SELECT (map name→Folder); конфликтные проверки обеих фаз идут по map вместо повторного SELECT на папку; после `replace` конкурент удаляется из map (сохраняет семантику повторного запроса).
- **`VFileRepository.collect_folders_contents_bulk`** (новый): сбор файлов из нескольких папок одним запросом (`c.ancestor_id IN :root_ids`); `collect_batch_contents` переведён на него.
- **`batch_zip_start`** (`file_zip.py`): один вызов `collect_batch_contents` вместо цикла по папкам + `get_by_id` по каждому файлу. Побочный эффект: файлы без msg_ids и файлы в корзине больше не попадают в батч-ZIP (раньше `get_by_id` не фильтровал).
- **`music_library_service.sync_structure`**: артисты и альбомы префетчатся двумя запросами (`folder_id IN`, `artist_id IN`), `_sync_albums_for` работает по картам `albums_by_fid`/`albums_by_artist` вместо per-album SELECT и lazy `artist.albums`. `classify_folder`/`_folder_metrics` не тронуты (валидированная логика).
- **`AutoIntegrityService._process_done_jobs`** (замороженная зона): один `SELECT ... FOR UPDATE ... ORDER BY id` на батч (до 200) вместо per-id SELECT; порядок id сохраняет защиту от дедлоков.
- **`IntegrityService.apply_repairs`** (замороженная зона): удаление dead-файлов — один `delete(VFile) ... IN`.
- **`MirrorService`** (замороженная зона): `create_mirror_jobs` — один EXISTS-запрос по всем аккаунтам; `_process_pending_jobs` — префетч `account_map` всех кандидатов (до 600) одним запросом; `_run_bulk_mirror` — префетч VFile батча (FOR UPDATE путь записи сохранён по-джобово).

### Индексы
- В моделях (`database.py`): `idx_transfer_jobs_vfile_id`, `idx_transfer_jobs_created_at`, `idx_share_links_vfile_id`, `idx_mirror_jobs_vfile_id` (FK без индексов). Для существующей БД применены `CREATE INDEX CONCURRENTLY` (create_all не добавляет индексы к существующим таблицам!).
- **Поиск**: `CREATE EXTENSION pg_trgm` + GIN-индексы `idx_vfiles_name_trgm`, `idx_folders_name_trgm` (`gin_trgm_ops`) — ILIKE '%q%' не использует btree по name. Проверено EXPLAIN ANALYZE: Bitmap Index Scan, ~10ms на 218k строк. Индексы применены только к живой БД (не в metadata — чтобы не ломать свежие установки без расширения).

### SELECT * / тяжёлые столбцы
- `list_files` и `tracks-recursive` (`file_crud.py`): `load_only` из 16 столбцов `FileResponseModel`; `account_map` (JSON) и `encryption_header` (Text) не тянутся — контракт их не возвращает. `_LISTING_COLUMNS` применяется во ВСЕХ ветках построения stmt (в т.ч. корзина с outerjoin).
- `build_folder_tree` (`folder_repository.py`): `load_only` 7 полей.
- `VFileRepository.file_exists_in_folder`: `select(VFile.id)` вместо полной строки.

### Пагинация и ретеншн
- **`GET /api/transfers`** (`transfers.py`): добавлены `limit` (default 200, max 500) и `offset` — фронтенд уже слал `limit: 200`, бэкенд игнорировал. Формат ответа не изменён.
- **Ретеншн** (`TransferRepository.cleanup_stuck_jobs`, выполняется при старте): finished-джобы (done/error/canceled/skipped) старше 7 дней удаляются одним DELETE — таблица transfer_jobs росла без границ.
- `TransferRepository.update_job_status`: убран `db.refresh(job)` (лишний SELECT; значения выставляются клиентски).

### Тесты
После оптимизаций: 99 passed, 12 failed + 8 errors — набор сбоев побайтово идентичен baseline до правок (все ранее существовавшие: test_folder_tree, test_auto_integrity, test_chaos, test_sync_stress).
