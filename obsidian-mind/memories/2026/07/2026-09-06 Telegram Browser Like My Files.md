---
date: 2026-09-06
description: "TG Channels в том же браузере файлов: корень + каналы-папки + reuse FileGrid/FileList"
tags: [memory, cloudbyte, telegram-channels, frontend]
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# TG Channels как Мои файлы (2026-09-06, вечер)

- Новый `frontend/src/components/TelegramBrowser.jsx`: корень TG Channels (каналы как папки
  `tg-ch-{id}`, синие, custom_icon send) + внутри канала файлы в тех же `FileGrid`/`FileList`
  (маппинг в shape VFS: id `tg-file-{row}`, size, mime, created_at). Замороженные
  `FileGrid.jsx`/`FileList.jsx`/`ContextMenu.jsx`/`store.js` не тронуты — только reuse импортом.
- Read-only честно: drag-n-drop заглушки, Rename/Move/Delete/Share/Star → тост "read-only".
  Работают: Preview (нативный image/video/audio через Range-стрим), Download, Properties (info).
  Поиск по имени/caption, сортировка через общий SortDropdown (store sortKey/sortOrder),
  пагинация "Show more" по 50, хлебные крошки TG Channels / Channel, статусы канала.
- `Dashboard.jsx`: секция `telegram` (заголовок TG Channels), рендер TelegramBrowser вместо
  FileBrowserContainer, пропуск фонового refresh My Files в этой секции, скрыты New Folder /
  Select All / Refresh шапки (бессмысленны для read-only).
- `Sidebar.jsx`: пункт "TG Channels" в navItems + компактная `TelegramSection` (connect + список
  каналов со статусами; клик → секция telegram + событие `open-tg-channel`).
- Проверки: `vite build` OK (1817 модулей), `py_compile` бэкенда OK, dist подхватывается без
  рестарта (статика с диска). Бэкенд не менялся — рестарт не нужен.

# Like (= Star) + импорт в Saved Messages (2026-09-07)

- БД: `telegram_files.is_liked` (BOOLEAN DEFAULT FALSE), миграция через
  `ensure_tables()` (`ALTER ... ADD COLUMN IF NOT EXISTS`). Проверено на живой БД.
- Сервис `telegram_service.py`: `set_liked`, `ensure_liked_folder` (VFS `Liked` в корне
  через `FolderRepository.create_folder`), `import_to_vfs` (канал → temp →
  `TransferJob` + фон `UploadService.process_upload` — чанкинг/шифрование/Saved Messages),
  `like_and_import` (Like + автокопия в Liked, без дублей по имени).
- Роутер: `POST /files/{id}/like {liked}`, `POST /files/{id}/copy-to-vfs {folder_id|null}`
  (настоящий импорт, возвращает job_id), `GET files?liked_only=true`, `info.is_liked`.
- Фронт `TelegramBrowser.jsx`: `is_liked → is_starred` (звёздочка без правок замороженного
  меню), `star`=Like, `share`=«В Мои файлы» (дерево VFS), фильтр `❤ Liked`, кнопки в Properties.
- Замороженное не тронуто: FileGrid/FileList/ContextMenu меню, database.py VFile/Folder,
  tg/*, search.py, сортировка, app.env.
- Проверки: py_compile OK, pytest 10 passed, ensure_tables OK, vite build OK (1818 модулей).

# Системный плеер для ТГ-каналов + прекеш 2 файлов (2026-09-07, вечер)

- Локальный `TgPlayer` выведен из использования: аудио ТГ играет системный стек
  (`usePlayerStore.playTrack` → глобальный `AudioPlayer` + штатный `PlayerBar` снизу +
  штатный `MusicMode` на полный экран). Работает без правок движка, т.к.
  `fileApi.download('tg-file-{row}')` резолвит TG-стрим. Видео/картинки — системный
  `MediaPreview` (транскод `?transcode=` резолвится для tg-id).
- Прекеш следующих 2 TG-треков: подписка на `currentTrack` в `TelegramBrowser`,
  через 3с warm-up `Range: bytes=0-131071` следующих 2 из `getUpcomingTracks(2)`.
  Замороженные `playerStore.triggerPrecache`/`fileApi.precache` не тронуты.
- Правки только в `TelegramBrowser.jsx`. `TgPlayer.jsx` остался файлом, из бандла выпал
  (1818 → 1817 модулей). Проверки: `vite build` OK.
- Ограничение: Star/«в плейлист» внутри MusicMode для TG-треков — ошибка (VFS-only API);
  Like для TG — через Star в списке TG-браузера.
