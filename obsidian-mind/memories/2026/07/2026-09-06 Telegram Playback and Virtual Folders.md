---
date: 2026-09-06
description: "TG-каналы: готовые плеер/preview через fileApi choke + виртуальные подпапки и переименование"
tags: [memory, cloudbyte, telegram-channels, frontend, playback]
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# TG: playback + виртуальные папки (2026-09-06)

## Playback без правок замороженного
- Все потребители (AudioPlayer, MediaPreview, ImageViewer) строят URL через
  `fileApi.download(id)`. В `frontend/src/api.js` добавлен choke: id `tg-file-{rowId}`
  → `/api/telegram-channels/files/{row}/stream` (inline). TG-файлы маппятся с такими id.
- `precache` для tg-id — тихий no-op (иначе 404 шумел бы из playerStore.triggerPrecache).
- Аудио: play-audio/двойной клик → `playerStore.playTrack/playFolder` + `addFolderToPlaylist`
  (только вызовы, сам `playerStore.js` не тронут). Видео/картинки → общий `MediaPreview`
  с onNext/onPrev. Тексты (txt/md/json/csv/log/yaml) → read-only оверлей (стрим как текст,
  срез 200К). Остальное — download.
- Замороженные `playerStore.js`, `AudioPlayer.jsx`, `useFileOperations.js`, `FileGrid/List`,
  `ContextMenu`, `store` не изменены.

## Виртуальные подпапки (локальные, в TG ничего не пишется)
- `telegram_folders(id, channel_id, parent_id, name)` + `telegram_files.folder_id NULL`
  (NULL = корень) + `telegram_channels.alias` (переименование папки канала).
- Миграция живой БД через `ensure_tables()` (create_all + ALTER ... ADD COLUMN IF NOT EXISTS).
- Service: CRUD + guard дублей среди сиблингов + запрет слэшей; delete рекурсивный,
  файлы поднимаются к родителю (без потерь); move файла; path для крошек; files-фильтр
  `folder_id` / `folder_set=all` (плеер папки). Удаление children-first (без SAWarning).
- Router: +7 эндпоинтов (итого 16 tg-роутов): folders CRUD, path, files/move, PATCH channel alias.
- Фронт `TelegramBrowser.jsx`: trail-крошки, New folder, rename/delete (свои модалки,
  замороженный ModalsProvider не тронут), move файла (пикер папок), rename канала (алиас,
  виден и в Sidebar). Даблклик/контекст как в Моих файлах; неподдерживаемое → 🔒-тост.

## Важно: рестарт бэкенда
- `reload=True` + hang shutdown (Mirror/AutoIntegrity/tg stop) = правки .py вешают сервер
  (порт занят, цикл мёртв; в логе стоп на `AutoIntegrityWorker stopped`, рестарт не происходит).
- Лечится только точечным `taskkill /F /PID <main.py> /T` + fresh `python main.py`.
  НЕ `stop.bat` (убьёт чужие python-процессы). После правок бэкенда всегда проверять
  `/api/auth/status` и при висе — килл+старт. Учтено: 11:00 ручной рестарт, всё UP, 16 роутов.

## Фикс стрима 11:27
- `routers/telegram_channels.py:download_or_stream` передавал в `_range_iter` саму
  async-функцию `gen` вместо генератора → `TypeError: 'async for' requires __aiter__`,
  ломал любое воспроизведение/скачивание TG-файлов. Исправлено на `gen_fn()` в обеих
  ветках (200 и 206). Проверено: `stream_media`/`get_chat_history` в pyrofork 2.3.69 есть.
- Релоадер снова завис на shutdown (3-й раз, лог стопорится на AutoIntegrityWorker stopped) —
  снова точечный килл+старт, сервер UP. Вывод: при любых правках backend/.py сразу
  готовиться к ручному рестарту, reload на этом проекте фактически неработоспособен.

## stop.bat: больше не убивает чужие серверы (2026-09-06)
- Причина: `taskkill /F /IM python.exe` убивал вообще все python-процессы (в т.ч. сервер на 5555).
- Новый stop.bat: только окна TGCloud_Backend* + дерево PID-слушателя порта 8000 (/T).
- Важно: write-инструмент сохранил .bat с LF — cmd его корёжил (кракозябры 'is not recognized').
  Починено конвертацией в CRLF. Все .bat править только с CRLF на выходе.

## Transcode для TG-видео/аудио (2026-09-06, фикс .avi)
- Браузеры не играют avi/mkv/wma/ape; видео-транскода в проекте не было вовсе.
- `telegram_service.ensure_transcoded(channel_id, row, fmt)`: скачивание целиком →
  ffmpeg (mp4: libx264 ultrafast crf23 + aac + faststart; mp3: как в cache_service) →
  кеш `CACHE_DIR/tg_transcode/tg_{ch}_{msg}.{fmt}.cache`, per-key asyncio.Lock, prune старше 7д,
  ws-broadcast transcode_status. Замороженные cache_service/download не тронуты.
- Роутер: `?transcode=video` + не-нативное расширение → FileResponse mp4 (Range из коробки);
  аудио wma/ape/opus/dsf/dff — авто как NEEDS_TRANSCODE_EXT в file_download.
- Фронт менять не пришлось: MediaPreview сам просит transcode=video, choke в fileApi.download
  параметр прокидывает. Первое воспроизведение .avi долгое (скачка+ffmpeg), повторы мгновенно.
- По пути: фикс `gen_fn()` вместо `gen` в download_or_stream (TypeError ломал весь TG-стрим).

## Примитивный TgPlayer + честная перемотка (2026-09-06)
- Причина битой перемотки: `stream_from_telegram.gen` при Range качал с нуля и скипал байты
  вручную — на больших файлах seek висел. Теперь используется нативный offset pyrofork
  `stream_media(msg, offset=chunk_index)`, чанки 1МБ + добивка extra_skip + честный limit.
- Новый `frontend/src/components/TgPlayer.jsx`: один файл (audio/video), свои контролы
  play/pause, seek-слайдер, время, volume-нативно, prev/next, download, close, error-фолбэк
  на скачивание. Общий playerStore для TG больше не используется (меньше связности).
- `TelegramBrowser`: audio/video (двойной клик, Play, Preview, play-folder) → TgPlayer;
  картинки остались на готовом MediaPreview. Не-нативные форматы идут через transcode-стрим.
- Фикс Content-Disposition: сырая кириллица в `filename*` роняла Starlette
  (UnicodeEncodeError latin-1) — ломался ЛЮБОЙ стрим с русским именем, включая mp4.
  Теперь `quote(fname)`. Транскод строго гейтован: видео только если ext вне
  VIDEO_NATIVE_EXT, аудио только wma/ape/opus/dsf/dff — mp4/webm/mov/mp3 идут as-is.
