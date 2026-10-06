---
date: 2026-09-10
description: "TG Channels: устранение [400 CHANNEL_INVALID] через резолвинг пиров, транскодирование видео в MP4 (faststart), HTTP Range RFC 7233/9110 и unit-тесты"
tags: [memory, cloudbyte, telegram-channels, playback, bugfix, streaming]
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# TG Channels: Устранение CHANNEL_INVALID и ошибок воспроизведения видео (2026-09-10)

## 1. Проблема и симптомы
В разделе **TG Channels (Telegram-каналы как виртуальные папки)** при воспроизведении видео возникали критические сбои:
1. `[400 CHANNEL_INVALID] (caused by "channels.GetChannels")` — в multi-account кластере Pyrofork при обращении по integer `tg_chat_id` сессия аккаунта не содержала кэшированного `access_hash` пира. Это приводило к моментальному обрыву видеострима (0 байт), переводу каналов в статус `error` при сканировании и сбою фонового импорта.
2. `Unable to choose output format` в FFmpeg — при воспроизведении не-нативных для браузера форматов (`.avi`, `.mkv`) функция `ensure_transcoded` создавала файл с суффиксом `.tmp` без явного указания формата `-f mp4`, что вызывало сбой транскодера и откат на битый стрим.
3. `Content-Disposition` — `FileResponse` не задавал `content_disposition_type="inline"`, вынуждая браузер скачивать файл вместо отображения в `<video>`. Кроме того, сырая кириллица в заголовке без RFC 5987 / RFC 8187 кодирования вызывала падение Starlette (`UnicodeEncodeError: 'latin-1' codec can't encode characters`).
4. Ошибки парсинга `Range` — некорректный ответ при суффиксных диапазонах (`bytes=-N`) и несоблюдение стандарта HTTP (выдача `Content-Range` при статусе 200 OK).

## 2. Архитектурные решения и изменения
- **Резолвинг пиров (`_resolve_channel`, `_get_channel_message`)** в `backend/services/telegram_service.py`:
  - Доступ к каналу и сообщениям сначала выполняется по username (если доступен), что обновляет `access_hash` в локальной sqlite-сессии клиента.
  - При подключении канала (`connect_channel`) выполняется прогрев кэша пиров на всех активных клиентах кластера.
- **Транскодирование видео на лету (`ensure_transcoded`)**:
  - Явный флаг формата `-f mp4` и суффикс `.tmp.mp4`.
  - Оптимизация для веб-стриминга: `-movflags +faststart`, `-preset ultrafast`, `-crf 23`, `-c:a aac`.
  - Безопасные расширения временных файлов Windows (`mkstemp(suffix=safe_ext)`).
- **Централизованные хелперы в `telegram_service.py`**:
  - `_parse_byte_range(range_header, fsize)`: парсинг стандартных, открытых и суффиксных диапазонов, валидация границ с возвратом `None` для 416.
  - `_is_native_playable(fname, mime)`: определение потребности в ffmpeg транскодировании.
  - `get_extension(fname, mime)`: безопасное извлечение расширения с fallback на MIME-типы.
- **Роутер `backend/routers/telegram_channels.py`**:
  - `Content-Disposition` строго `inline` для `/stream` с RFC-кодированием имени через `quote(fname)`.
  - Заголовок `Content-Range` формируется строго при статусе `206 Partial Content`.
- **Фронтенд `frontend/src/components/TelegramBrowser.jsx`**:
  - В `<MediaPreview>` добавлен обработчик `onError`, показывающий всплывающее уведомление toast об ошибке вместо вечной загрузки.
  - Сборка фронтенда (`npm run build`) успешно верифицирована.
- **Тесты (`backend/tests/test_telegram_channels.py`)**:
  - 100% покрытие юнит-тестами хелперов Range, native formats и extension resolution.

## 3. Правила и незыблемые ограничения
- Файл `app.env` не затрагивался (абсолютный запрет).
- Модели VFS (`database.py`), транспорт `tg/*` и сервисы целостности/корзины сохранены без изменений.
- Все файлы перезаписаны целиком (`write_file`).
