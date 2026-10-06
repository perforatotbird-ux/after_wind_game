---
date: 2026-09-06
description: "Telegram-канал как виртуальная read-only папка: проекция, щадящий скан, кеш, стрим"
tags: [memory, cloudbyte, telegram-channels, vfs]
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# Telegram Channel Virtual Folder (MVP 2026-09-06)

- Проекция без `VFile`: `telegram_channels` + `telegram_files` (`backend/models_telegram.py`), тот же Base, `ensure_tables()`.
- Слой: `routers/telegram_channels.py` → `services/telegram_service.py` → `tg/manager.py` (существующий Pyrofork кластер). `tg/*`, `database.py` VFile/Folder, `search.py` не тронуты.
- Скан: последовательно, batch 50, delay 3с, 20 req/min; при открытии — кеш + фон-инкрементал; шедулер `telegram_channel_incremental` 30 мин (`TG_CHANNEL_SCAN_INTERVAL_MIN`); pause/resume флагом `scan_status`; FloodWait → `rate_limited` + backoff 3→60с + ws broadcast.
- API: `/api/telegram-channels/*` (12 роутов), Range-стрим, copy = stage в temp + штатный upload flow.
- Фронт: `telegramApi.js` + `TelegramSection.jsx` в Sidebar; нативный preview image/video/audio; поиск SQL ILIKE по кешу (имя/caption/mime/ext).
- Конфиг: `TG_CHANNEL_REQ_PER_MIN=20`, `TG_CHANNEL_DELAY_S=3`, `TG_CHANNEL_BATCH=50`, `TG_CHANNEL_SCAN_INTERVAL_MIN=30` через env/AppConfig, без правок `app.env`.
- Ограничения MVP: только @username, без thumbnails/полнотекста/виртуализации/Bot API.
