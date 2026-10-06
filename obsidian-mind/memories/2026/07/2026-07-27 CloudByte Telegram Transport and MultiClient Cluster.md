---
date: 2026-10-05
description: "CloudByte/TGCloud Telegram transport layer decomposition, MultiClientManager cluster lifecycle, streaming failover, chunking transport, direct download Content-Length fix, graceful upload cancellation, and upload presets with live capacity switching."
tags: [memory, cloudbyte, tgcloud, telegram, pyrogram, mtproto, streaming, upload-cancellation, download-fix, content-length-fix, upload-presets, live-capacity]
source: mcp-capture
origin: "replit"
session: "2026-10-05T08:00:00.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte Telegram Transport and MultiClient Cluster

## Package Structure (`backend/tg/`)
The original `tg_client.py` monolith was decomposed into modular components in `backend/tg/`:

1. **`manager.py` (`MultiClientManager`)**:
   - Manages client connection lifecycles, health tracking (`is_account_healthy`), and semaphores.
   - Applies monkey-patches:
     - `PyrogramSession.SLEEP_THRESHOLD = 60`
     - Custom `_patched_save_file` method forcing `TG_UPLOAD_WORKERS` (default 2) to limit parallel RPCs per account and eliminate `FloodWait` spikes.
   - Динамическое обновление конфигурации передачи через `refresh_upload_configuration()` на event loop без переподключения клиентов.

2. **`uploader.py` (`UploaderMixin`)**:
   - Handles file chunking into 512KB / 1MB parts.
   - Throttling via `ThrottledFile` (default **16 MB/s**, configurable via `TG_UPLOAD_THROTTLE_MBPS`).
   - Generates comma-separated `msg_ids` string.
   - **Upload Cancellation Handling**: `send_file_part` checks `transfer_manager.is_canceled(job_id)` and logs user-initiated cancellations as `INFO` rather than false-positive `ERROR` events.

3. **`downloader.py` (`DownloaderMixin`)**:
   - **`stream_file_linear`**: Linear sequential streamer for browser/audio playback. Implements **True Mid-Stream Failover** ("Atomic Start" state machine). Raises an explicit exception if metadata for a part cannot be fetched from any cluster mirror (preventing silent part drops and archive corruption).
   - **`stream_file_from_saved`**: Multiplexed high-speed downloader for infrastructure operations and direct file downloads.

4. **`zip_builder.py` (`ZipBuilderMixin`)**:
   - Asynchronously packages multiple cloud files or folder hierarchies into a streaming ZIP archive on the fly without intermediate disk storage.

5. **`incoming.py` (`IncomingMessageHandler`)**:
   - Processes files sent directly to the Telegram bot/account buffer.
   - Grouping logic strictly uses `media_group_id` for batch/album aggregation to prevent fragmenting files arriving out-of-order.

6. **`upload_control.py` & `upload_transport.py`**:
   - `ResizableSemaphore`: динамическое масштабирование ёмкости (global files, rpc concurrency, preparations) без отмены активных операций.
   - `UploadPolicy`: раздельный контроль пропускной способности байтов/RPC, интервалов между сообщениями, адаптивного троттлинга при `FloodWait`.
   - `_patched_save_file`: конвейер частей MTProto с контролем воркеров и гарантированным подтверждением каждой части.

## Multi-Account Cluster Failover & Download Fixes
- **Direct File Downloads & Content-Length Precision (`file_download.py`)**:
  - **Root Cause of Archive Corruption**: For encrypted or multi-part files, `vf.size` in DB includes multiple 32-byte headers (one per Telegram part). `encrypted_size_to_plain_size` calculated a `reported_size` that was slightly too large. Setting `Content-Length: <reported_size>` caused browsers to expect extra phantom bytes at the end of the HTTP stream. Browsers flagged the stream as prematurely closed/truncated, resulting in "Unexpected end of archive" when extracting with WinRAR / 7-Zip.
  - **Resolution**: `headers["Content-Length"]` and stream `limit` are omitted for full downloads (`status_code=200`) of encrypted or multi-part files. FastAPI uses HTTP `Transfer-Encoding: chunked`, allowing the browser to receive 100% of the decrypted archive data chunks until stream completion without waiting for phantom bytes.
  - Direct file downloads use `Content-Disposition: attachment` and high-speed multiplexed transport (`use_simple=False`, matching `downloadLocal`).
- **FloodWait Handling**: When an account receives a `FloodWait(seconds)` from Telegram API, `mark_flood(aid, duration)` temporarily disables the account for the required duration while streaming automatically fails over to remaining cluster members.
- **Graceful Upload Cancellation**:
  - `upload_stream` endpoint returns `200 OK` with `status: "canceled"` when cancellation occurs during HTTP stream reception (`handle_stream`), avoiding `500 Internal Server Error`.
  - `process_upload` background worker immediately breaks the part retry loop when `transfer_manager.is_canceled(job_id)` is set, marking the job status as `"canceled"` instead of `"error"` and preventing unnecessary 5-attempt retry delays.

## Пресеты загрузки и динамическое управление ёмкостью (Upload Presets & Live Capacity Switching)
- Внедрены настраиваемые пресеты загрузки: **Safe** (последовательная отправка, минимальная нагрузка), **Fast** (конвейер частей одного файла с общим бюджетом аккаунта) и **Risky** (параллельные файлы, высокий бюджет, риск длительного FloodWait).
- **`backend/services/upload_presets.py`**: Валидация профилей через Pydantic V2 (`UploadProfile`), поддержка ревизий для защиты от конфликтов параллельного редактирования (`RevisionConflict`), явное подтверждение рисков для агрессивных настроек (`RiskAcknowledgmentRequired`).
- Конфигурация сохраняется в одном env-ключе `UPLOAD_PRESETS_STATE` без необходимости изменения структуры базы данных.
- **Динамическое переключение**:
  - Лимиты скорости, частота RPC и параллелизм обновляются на лету в существующих политиках и семафорах без переподключения клиентов к Telegram API.
  - Уже начатые части и файлы не обрываются: при снижении лимитов слоты освобождаются по мере завершения текущей работы.
  - Полный `FloodWait` и пауза `cooldown` никогда не сбрасываются и безусловно соблюдаются.
- **Frontend (`UploadPresetsPanel.jsx` & `Settings.jsx`)**:
  - Панель управления пресетами в настройках с мониторингом активных задач, кулдаунов и шкалы адаптивной скорости.
  - Возможность возврата к прежним legacy-настройкам (`/api/auth/upload-presets/legacy`).
