# 2026-09-10: Архитектурный план переноса Music Library в отдельное Standalone Web App

## Контекст и цель
Пользователь запросил детальный план переноса всего функционала музыкальной библиотеки (`Music Library`) и аудиоплеера в отдельное независимое веб-приложение на том же технологическом стеке (FastAPI + React 18 Vite + MTProto Telegram Streaming + PostgreSQL).

Основной интерактивный HTML-план сохранён по адресу:
`K:\Test\Replit\music_library_standalone_migration_plan.html`

---

## 1. Архитектурная стратегия

Выбрана стратегия **Shared Database & Telegram Streaming Cluster**:
- Новое приложение запускается на отдельных портах (`8005` бэкенд, `5175` фронтенд).
- Подключается к существующей базе данных PostgreSQL (контейнер `tgvfs-postgres` на порту 5433).
- Использует существующие таблицы `music_artists`, `music_albums`, `folders`, `folder_closures`, `vfiles`.
- Использует выделенные или разделяемые MTProto-сессии Telegram для параллельного стриминга аудио через `FastStreamer`.

---

## 2. Матрица переиспользования компонентов

### Бэкенд:
- **Перенос 1:1**:
  - `backend/tg/downloader.py`: `FastStreamer` с поддержкой HTTP Range, чанкирования и mid-stream failover.
  - `backend/tg/manager.py`: `MultiClientManager` с семафорами и параллельной инициализацией клиентов.
  - `backend/services/music_library_service.py`: Обогащение через MusicBrainz, Cover Art Archive, Wikipedia.
  - `backend/services/music_image_cache.py`: Бессрочный кэш обложек на диске, SSRF защита.
  - `backend/encryption.py`: Потоковая расшифровка AES-256-GCM на лету.
- **Адаптация**:
  - `backend/routers/music_library.py`: Центральный роутер каталога артистов, альбомов и ручной смены обложек.
  - `backend/routers/files.py`: Выделение эндпоинта стриминга аудио в отдельный `stream.py`.
  - `backend/database.py`: Легковесные модели без таблиц корзины, перемещения и зеркалирования.
- **Исключено**:
  - Все сервисы зеркалирования, авто-целостности (ICT, AutoIntegrity), торрент-воркеры, файловые операции VFS вне папки Music.

### Фронтенд:
- **Перенос 1:1**:
  - `MusicLibrary.jsx`: Zine-сетка (Артисты, Альбомы, Сборники, Коллекции), страница артиста, мобильные тач-стили.
  - `CoverPicker.jsx`: Drag & Drop, URL предпросмотр, сброс обложки.
- **Улучшение**:
  - `MusicLibraryPlayer.jsx` + `playerStore.js`: Добавление прекеширования следующих 2 треков, очереди и плейлистов.
  - PWA (Progressive Web App): Установка на мобильные устройства, Media Session API на экране блокировки.
- **Исключено**:
  - `FileExplorer`, `BatchBar`, `Sidebar` с дисками CloudByte, `MediaViewer` документов/видео.

---

## 3. Фазы миграции
1. **Фаза 1 (0.5 дня)**: Scaffolding проекта `tgmusic/`, зависимости, Docker Compose.
2. **Фаза 2 (1.5 дня)**: Экстракция бэкенда, моделей, стриминга и роутеров метаданных.
3. **Фаза 3 (1 день)**: Сборка фронтенда Vite + React, чистый Zine-лейаут без сайдбара.
4. **Фаза 4 (1 день)**: Аудио-оптимизации, pre-caching 2 треков, PWA и Media Session.
5. **Фаза 5 (0.5 дня)**: Сквозное тестирование FLAC/MP3, релизные скрипты запуска.
