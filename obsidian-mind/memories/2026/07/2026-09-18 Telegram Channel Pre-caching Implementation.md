---
tags:
  - telegram
  - cache
  - performance
  - pre-cache
  - frontend
  - backend
date: 2026-09-18
---

# Telegram Channel Pre-caching Implementation

## Проблема

В режиме "Подключенные каналы Telegram" не работало предварительное кеширование (pre-caching) для медиа-файлов.

На клиенте файлы Telegram-каналов получали ID формата `tg-file-{row_id}`, которые фронтенд явно игнорировал (возвращал `{ skipped: true }`), когда `playerStore.js` или `MediaPreview.jsx` пытались вызвать `fileApi.precache`.

Кроме того, в `MediaPreview.jsx` и `TelegramBrowser.jsx` была предпринята попытка имитировать прекеширование, запрашивая первые 256 КБ стрима (`fetch` с заголовком `Range: bytes=0-262143`) и немедленно отменяя `reader`. Однако, на стороне бэкенда (`stream_from_telegram`) файлы стримились напрямую через Pyrogram API в память без локального дискового кеширования, что делало этот подход бесполезным (он просто сжигал трафик и не ускорял последующую загрузку трека).

## Решение

Была реализована полноценная система предварительного кеширования для Telegram-каналов с сохранением на диск.

### 1. Бэкенд (`backend/services/telegram_service.py` и `backend/routers/telegram_channels.py`)
- Добавлен механизм дискового кеширования в директорию `CACHE_DIR/tg_cache/`.
- Реализована функция `precache_file(channel_id, row_id)`, которая скачивает файл в фоне с использованием `tg_client.MultiClientManager.get_instance().get_file_semaphore()` для соблюдения лимитов Telegram.
- Скачивание атомарно: файл скачивается как `.tmp`, затем переименовывается в `.cache`.
- Добавлена функция очистки кеша `_prune_tg_cache(max_size_mb=2000)`, которая удаляет старые файлы, чтобы кеш не превышал 2 ГБ.
- В `telegram_channels.py` добавлен новый эндпоинт `POST /api/telegram-channels/files/{row_id}/precache` для инициации кеширования.
- Эндпоинт `GET /api/telegram-channels/files/{row_id}/stream` (и `download`) теперь проверяет наличие файла в локальном кеше (`is_cached(row_id)`). Если файл найден, он отдается через `FileResponse`, что обеспечивает нативную поддержку HTTP 206 Partial Content (перемотки) на уровне FastAPI / Starlette, минуя Pyrogram-стриминг.

### 2. Фронтенд (`frontend/src/api.js`, `telegramApi.js` и компоненты)
- В `telegramApi.js` добавлен метод `precache(rowId)`.
- В `api.js` обновлен метод `fileApi.precache`: теперь он корректно обрабатывает ID, начинающиеся с `tg-file-`, вырезая префикс и направляя запрос к `/api/telegram-channels/files/{row_id}/precache`.
- В компонентах `MediaPreview.jsx` и `TelegramBrowser.jsx` удалены хаки с "fake fetch"-стримингом, и теперь они просто вызывают стандартный `fileApi.precache()`, который корректно маршрутизируется как для файлов VFS, так и для Telegram-каналов.

## Итог

Теперь при прослушивании аудио или просмотре видео в Telegram-каналах следующие 2 файла прозрачно и полностью загружаются на сервер в фоновом режиме, сохраняясь в папку `tg_cache`. Когда пользователь переключает трек, файл отдается локально и мгновенно, с полноценной поддержкой seek (перемотки).
