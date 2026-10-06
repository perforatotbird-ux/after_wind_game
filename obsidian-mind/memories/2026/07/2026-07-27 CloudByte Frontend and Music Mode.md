---
date: 2026-07-27
updated: 2026-08-29
description: "CloudByte/TGCloud frontend React architecture, Zustand state stores, Music Mode UI, player visualizers, and Android mDNS integration."
tags: [memory, cloudbyte, tgcloud, frontend, react, zustand, music-mode, player]
source: mcp-capture
origin: "replit"
session: "2026-07-27T15:24:41.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte Frontend and Music Mode

## Web Application Stack (`frontend/`)
- **Framework**: React 19 + Vite 6
- **State Management**: Zustand 5.0 (`frontend/src/store.js` and `frontend/src/playerStore.js`)
- **Styling**: Vanilla CSS + TailwindCSS 4.2 custom tokens (`index.css`)
- **Iconography**: Lucide React (`lucide-react`)

## Key Frontend Modules & State Stores

### 1. Main Store (`frontend/src/store.js`)
- `selectedItems`: Set of file/folder IDs selected in grid/list view.
- `currentFolderId`: Active navigation path.
- `conflict`: Conflict state object handling HTTP 409 responses during move/copy actions.
- `searchQuery`: Search input state.

### 2. Audio Player Store (`frontend/src/playerStore.js`)
- `mainPlaylist`, `userQueue` (Priority Queue), `shuffledList`, `currentTrack`, `isPlaying`, `isBuffering`, `volume`, `isRepeat` (`'all' | 'one' | false`), `isShuffle`.
- `lastPlaylistTrackId`: последний трек, игравший из основного списка; после трека из Priority Queue библиотека возобновляется с места прерывания, а не с начала.
- **Управление очередью (2026-08-16)**: `removeFromQueue(trackId, source)` — удаление трека из 'queue'|'library' (играющий трек доигрывает); `moveInQueue(trackId, direction, source)` — перемещение ↑/↓, при shuffle синхронно двигает `shuffledList`.
- **Pre-caching System**: Automatically initiates precache request (`POST /api/files/{id}/precache`, тело `{"password": ...}` опционально) 3 seconds after track playback begins to load the next 2 tracks. Пароль (`previewPw`) передаётся, чтобы фоновый прекешинг мог расшифровывать файлы при заблокированном серверном vault.
- **Additive Queueing**: Allows appending folders/tracks to active playback session without resetting queue.
- **Persist настроек** (с 2026-08-16): `volume`, `isRepeat`, `isShuffle`, `eqSettings` — в localStorage (`cloudbyte-player-settings`), вручную без middleware (чтобы не писать на каждый timeupdate).

### 3. Music Mode Component (`frontend/src/components/MusicMode.jsx`)
Features visualizers and interactive player themes:
- **Vinyl Visualizer**: Animated rotating vinyl record with groove arm.
- **Cassette Visualizer**: Dual-spool cassette tape animation with tape progress counter.
- **CD Visualizer**: Shiny iridescent compact disc with laser reflection effects.
- **WinampEqualizer (canvas)**: акцентный цвет и градиент кэшируются один раз на эффект (не на кадр), шкала бинов логарифмическая.
- **PlayerBar**: Sticky bottom audio control bar with progress scrubber (drag-seek через прозрачный range-оверлей), volume, and visualizer toggle.
- `visualMode` переживает перезагрузку (localStorage `musicVisualMode`).
- Play-кнопка показывает спиннер при `isBuffering && isPlaying`.
- **Очередь**: у каждого трека контролы ↑/↓/удалить (`QueueItem` — div role=button, вложенные кнопки невалидны). **Поиск по плейлисту** (2026-08-16): локальная строка «Search in current playlist…» в панели очереди фильтрует Priority Queue + From Library по имени (только представление, очередь не меняется); кнопки-лупы (мобильная шапка + компакт-панель) фокусируют её через `focusPlaylistSearch()`, а НЕ выходят в глобальный поиск; счётчик «найдено / всего» при фильтре; Esc очищает. Глобальный поиск (`useSearch.js`) не затронут.
- **PlaylistsManagerModal** (2026-08-16): управление сохранёнными плейлистами — Play, Rename (inline-инпут), Delete (двухшаговое подтверждение), редактор треков (нумерация, ↑↓ через `reorderTracks`, удаление). Кнопка ListMusic в шапке панели очереди.

### 4. AudioPlayer (`frontend/src/components/AudioPlayer.jsx`) — движок
- `prepareStream` — стабильный callback, читает состояние через `getState()` в момент вызова (устранён stale-closure, из-за которого зашифрованный трек молча не играл после ввода пароля в модалке).
- Repeat `'one'` обрабатывается в обработчике `ended` (перезапуск текущего трека).
- Счётчик последовательных ошибок аудио (макс. 5): останавливает воспроизведение с тостом вместо бесконечного цикла автоскипов.
- EQ: перестройка WebAudio-цепи только при toggle `eqSettings.enabled`; изменение полос — in-place (`filter.gain.value`). **Критично:** `analyser → ctx.destination` подключается один раз в `setupAudioContext`; потеря этой строки (регрессия 2026-08-16, исправлена в тот же день) давала полную тишину — `createMediaElementSource` заводит звук `<audio>` в граф, и без выхода в destination он не играет. Любые правки цепи обязаны сохранять путь до `destination`.
- Media Session API: метаданные + play/pause/prev/next/seek.

## Playlists API (2026-08-16)

`backend/routers/playlists.py`:
- `GET /api/playlists` — список с track_count; `POST` — создание (с позициями 1..N).
- `PUT /api/playlists/{id}` — **переименование** (пустое имя → 400).
- `DELETE /api/playlists/{id}` — удаление (каскад треков).
- `GET /{id}/tracks` — треки по `position, id`; `POST /{id}/tracks` — добавление в конец.
- `PUT /{id}/tracks/reorder` — **перестановка**: полный порядок `track_ids`, позиции 1..N, неизвестные id игнорируются, дубликаты без коллизий позиций.
- `DELETE /{id}/tracks/{vfile_id}` — удаление трека.
- Схемы: `PlaylistRename` (1–255), `PlaylistReorder` (1–500 id). Тесты: `backend/tests/test_playlists.py`.

## Mobile Client & mDNS Integration (`backend/main.py` & `android_app/`)
- **Service Registration**: Server registers Zeroconf service `_cloudbyte._tcp.local.` on port 8000.
- **Android App Auto-Discovery**: Android Kotlin client scans local Wi-Fi for `_cloudbyte._tcp.local.` service broadcasts to automatically connect to server without manual IP entry.
- **Recursive Audio Tracks Endpoint**: `GET /api/files/tracks-recursive` returns audio tracks under selected folder hierarchies for playlist rendering. С 2026-08-16 — детерминированный natural sort по имени (Track 1 < Track 2 < Track 10), паттерн как в `list_files`.

## Music Mode backend (2026-08-16)

- **Транскод** (`file_download.py`): `NEEDS_TRANSCODE_EXT = {'.wma', '.ape', '.opus', '.dsf', '.dff'}` — m4a/aac/ogg/flac/wav больше НЕ транскодируются (браузеры играют их нативно); в цикле ожидания транскода проверяется `request.is_disconnected()`; имя MP3 строится через `os.path.splitext`.
- **RAM-кэш аудио** (`services/ram_cache.py`, 512 МБ LRU): файлы больше лимита не кэшируются вовсе; `async_locks` чистятся от незанятых при превышении 128.
- **Stream tickets**: срок 1 ч, максимум 1000; тикет передаётся в query string (ограничение `<audio src>`); сам тикет пароль не валидирует — валидация пароля происходит в `encryptionApi.unlock` из `FileDecryptModal`.

## Music Library — Rebuild (2026-08-24)

Зона Music Library (отдельный режим поверх папки `Music`, id=295) НЕ заморожена — дорабатывается.

- **Кнопка Rebuild** (`frontend/src/components/MusicLibrary.jsx`, `handleRebuild`) вызывает `musicLibraryApi.enrich(true)` → `POST /api/music-library/enrich?force=true`.
- **Backend** `enrich_library(force)`:
  - `force=True` (Rebuild) — сбрасывает кэш обогащения у не-locked записей: `MusicArtist.mbid/image_url/bio/wikipedia_url/enriched_at = None` и `MusicAlbum.cover_url/mbid/enriched_at = None`, затем пере-тянет всё заново (MB-поиск артистов/групп, Wikipedia-био, обложки из Cover Art Archive). Без сброса повторный прогон был no-op (поля уже заполнены → пропуск).
  - `force=False` — обогащает только ещё не обогащённые артисты (`enriched_at IS NULL`); быстрый дозалив новых без перезапроса Wikipedia для готовых.
- **Cache-busting фронта**: `imgSrc(url, v)` добавляет `?v=<enriched_at>` к `image_url`/`cover_url` карточек и hero, чтобы браузер перезапрашивал обновлённые обложки (а не отдавал из HTTP-кэша).
- **Ограничение скорости**: MusicBrainz лимит ~1 запрос/с (`MB_RATE_LIMIT_SEC = 1.1`, последовательные `asyncio.sleep`), параллелить нельзя (риск бана). Полный force-Rebuild при сотнях альбомов объективно долог — это норма, не баг.
- **Фоновая авто-сборка (2026-08-24)**: `AsyncIOScheduler` в `main.py` раз в `MUSIC_LIBRARY_AUTO_ENRICH_MINUTES` (по умолчанию 15) запускает `run_scheduled_enrich()` из `routers/music_library.py` → `enrich_library(force=False)`. Подхватывает новые папки/треки, добавленные в Music через веб-UI (их записи имеют `enriched_at IS NULL` после `sync_structure`) и дотягивает обложки/био только для них. Прогресс шлётся с флагом `scheduled: true`, фронт (`MusicLibrary.jsx`, `onProgress`) тихо перезагружает секцию без тоста/спиннера. `enrich_library` защищён флагом `_enrich_running_flag` — одновременно идёт только одна сборка (ручная или фоновая). Интервал настраивается env-ключом (без правки app.env — работает дефолт).
- **Баг retry (2026-08-24, исправлен)**: `_enrich_one_artist` ранее всегда ставил `enriched_at = now`, даже при транзитном сбое MB (пустой `mbid`/нет обложек). Из-за этого проваленная запись считалась «готовой» и `force=False`-автообогащение (фильтр `enriched_at IS NULL`) её никогда не повторяло — био/обложки пропадали навсегда. Исправлено: `enriched_at` ставится только если реально подтянули `mbid` артиста или хотя бы одну обложку альбома; иначе запись остаётся `enriched_at IS NULL` и ретраится на следующем прогоне. Лог `_mb_get` теперь пишет тип исключения (`TimeoutError` и т.п.) вместо пустой строки.
- **Per-card Rebuild + окно прогресса (2026-08-24)**: появилась кнопка Rebuild на каждой карточке (`RefreshCw` в углу thumbnail, не для locked-артистов). Бэкенд: `POST /api/music-library/enrich/{folder_id}` → `enrich_entity_by_folder()` (сервис) — сбрасывает кэш одной сущности (артист + его альбомы, либо один альбом по folder_id) и пере-тянет обложки/био. Альбом-логика вынесена в `_enrich_single_album()` (переиспользуется в `_enrich_albums`). Прогресс шлётся с `entity=folder_id`. Фронт: глобальный компонент `MusicLibraryProgress.jsx`, смонтированный в `App.jsx` (вне роутов) — фиксированное окно в **левом нижнем углу**, переживает переходы между страницами, игнорирует `scheduled`-прогоны, авто-скрывается через 4с после done/error. Локальный центр-прогресс в `MusicLibrary.jsx` убран (одно окно — глобальное).
- **Баг: ручной Rebuild был silent-no-op (2026-08-24, исправлен)**: `enrich_library` держал модульный флаг `_enrich_running_flag`; пока фоновая auto-сборка (`run_scheduled_enrich`) крутилась часами по ещё не обогащённой библиотеке, флаг оставался `True` и ЛЮБОЙ ручной Rebuild (глобальный `force=True` и per-card через `enrich_library` не шли — per-card шёл через `enrich_entity_by_folder`, но общий эффект: «ничего не происходит, нет логов»). Исправлено: флаг удалён; конкурентность полных проходов теперь только на уровне роутера (`_enrich_running`) и планировщика (`_auto_enrich_running`), ручной Rebuild больше не блокируется долгой фоновой сборкой. Добавлены INFO-логи `enrich_library start (force=...)` и `enrich_entity_by_folder: folder_id=...` для видимости. Визуал: кнопка per-card перенесена из `overflow:hidden` thumbnail наружу (`.ml-card`), чтобы не обрезалась круглой обложкой артиста.
- **Нюанс структуры**: обложки не появляются для **generic-контейнеров** («Albums», «Singles & EP's» и т.п.) — MusicBrainz/CAA не найдёт release-group по таким именам. Реальные альбомные папки (с названием релиза) получают обложки. Это ожидаемо, не баг.
- **CSP-блокировка картинок (2026-08-24, исправлен)**: `img-src 'self' data:` в SecurityHeadersMiddleware (`main.py`) запрещал браузеру грузить внешние картинки — обложки/фото из БД НЕ ОТОБРАЖАЛИСЬ при живых URL (выглядело как «Rebuild ничего не скачал»). Исправлено: в img-src добавлены `https://*.wikipedia.org https://*.wikimedia.org https://*.wikidata.org https://coverartarchive.org https://*.archive.org`. После правки бэкенда пользователю нужен Ctrl+F5 (заголовок кэшируется на уровне страницы).
- **Наблюдаемость enrich (2026-08-24)**: консоль молчала часами. Теперь: `[ML enrich] i/N Name -> photo=… bio=… covers=X/Y` на каждого артиста (INFO), стартовая/итоговая сводка, WARNING при 409 «already running» (раньше ручной Rebuild во время фоновой авто-сборки отклонялся абсолютно тихо), INFO старта/финиша `run_scheduled_enrich`. Промахи MB/CAA — DEBUG (только файловый лог). Фронт: console.debug WS-событий в `MusicLibrary.jsx` (`[auto]`/`[manual]`).
- **https-нормализация CAA (2026-08-24)**: `_caa_cover_url` сохраняет thumbnail-URL сразу с `https://` (CAA отдаёт часть ссылок как http); разово нормализован существующий кэш (198 альбомов + 16 фото артистов). VFS/Telegram не затронуты.
- **Темп Rebuild — норма**: полный force-проход по 2260 альбомам при rate-limit MB ~1 req/s занимает ~1.5–3 часа; прерывание перезапуском бэкенда безопасно (обогащённое сохранено, хвост добирается авто-сборкой force=False или повторным Rebuild). Папки вида «Артист - Год - Альбом» целиком не матчатся (нормализация не отрезает префикс артиста) — кандидат на будущую доработку `_enrich_single_album`.
- **Умная очистка имён для MB-поиска (2026-08-24 вечер, этап 6)**: причина массовых `covers=0/N` — грязные имена в запросах. Теперь: `split_artist_album()` разбирает «Артист - Год - Альбом» / «Артист - Альбом» (два паттерна: обязательный год посередине → ленивый артист, иначе жадный сплит по последнему разделителю; ведущий год и дефисы внутри имени артиста не ломают разбор); `clean_artist_query()` срезает хвосты «- год - год» из имён артистов и сохраняет чистое имя в `search_name` (= artist_hint для альбомов); `_enrich_single_album` делает фолбэк-запрос БЕЗ artist-клаузы для сборников/VA (порог схожести 75%), приём кандидата только ≥55% по названию (был слепой groups[0]). Live-проба: `releasegroup:"72 Seasons" AND artist:"Metallica"` → MATCH.
- **Остановка вечных ретраев (2026-08-24 вечер)**: определённое «MB ответил, ничего не нашёл» теперь фиксируется `enriched_at` у альбома/артиста (раньше такие записи оставались NULL и переискивались каждым фоновым прогоном часами). Транзитные сбои сети (`_mb_get → None`) по-прежнему остаются на ретрай. Артисты, которых реально нет в MB/Wikipedia, остаются с генеративными карточками — граница данных; точечная подмена через override (mbid вручную, locked).
- **Тесты Music Library**: `tests/test_music_library.py` — 26 passed (нормализация/классификация/sync/endpoints + split_artist_album/clean_artist_query кейсы включая 'Pr-Mex - 2012 - 2012', ведущий год, чистые имена).
- **Аудит стабильности изменённых файлов (2026-08-28)**: 4 фикса. (1) `file_download.py` (`download_folder_local`): `body.get('password')` падал AttributeError→500 на валидном не-объектном JSON (`null`/`[..]`/`"str"`) — теперь `isinstance(body, dict)` (как в `precache_file`). (2) `main.py:229,248` — `int(env_get(...))` → `env_get_int(...)`: непустое нечисловое значение в `app.env` (напр. `15m`) раньше валило старт сервера ValueError'ом в lifespan. (3) `playlists.py`: `add_track` возвращает 404 для несуществующего vfile_id (был необработанный IntegrityError→500), `create_playlist` молча пропускает битые `track_ids` с сохранением порядка. (4) `MusicLibrary.jsx` — защитный `|| '?'` в `hashHue` для карточек без title. Проверка: tests playlists+api_files 9 passed, `npm run build` OK, сервер перезапущен.
- **Аудит асинхронного кода (2026-08-28)**: 5 фиксов. (1) Гонка флагов Music Library: `_enrich_running` ставился внутри корутины `_run` (после возврата эндпоинта → окно для второго запроса) и `_auto_enrich_running` был ОТДЕЛЬНЫМ флагом — ручной Rebuild и плановая авто-сборка шли одновременно (2 req/s к MusicBrainz → 503). Теперь ОДИН общий `_enrich_running`, ставится синхронно в эндпоинте/джобе ДО `create_task`, сбрасывается в `finally`; `_auto_enrich_running` удалён (запись выше про два флага устарела). (2) `maintenance.py rebuild_stats`: `asyncio.run(ws_manager.broadcast(...))` из синхронной фоновой задачи (threadpool → чужой event loop) → WS-send падал, уведомление терялось; теперь задача async, БД-пересчёт в `asyncio.to_thread`, broadcast — `await` в главном loop. (3) `zip_builder._zip_worker`: `progress_cb` вызывался вне try и до `queue.task_done()` — исключение навсегда подвешивало `queue.join()` (ZIP-задача «running» вечно); теперь `try/finally` гарантирует `task_done`. (4) `downloader.fetch_segment`: producer не гарантировал sentinel `q.put(None)` при вылете исключения → потребитель зависал на `q.get()`; тело вынесено в `_fetch_segment_body`, wrapper с `finally: put(None)`. (5) `Settings.jsx:393,423` — плавающие `stats().then()` без `.catch` (unhandled rejection после clear-cache/wipe) — добавлен `.catch(() => {})`. Проверка: ast 4 файлов OK, test_music_library 26 passed, `npm run build` OK, сервер перезапущен. Последовательные await в циклах (enrich/_send_folder_bg/TG-батчи) — осознанный rate-limit, НЕ рефакторить на gather.
- **Рекурсивный парсинг альбомов + карточка «Треки» (2026-08-29)**: причина «Artist/Albums/... → один большой альбом» — `_sync_albums_for` брал альбомами только ПРЯМЫХ детей папки артиста. Теперь альбомы = ВСЕ потомки с прямым аудио (любая глубина): `_album_candidates()` джойнит `folder_closures` (depth>0) с EXISTS по `vfiles.mime_type LIKE 'audio/%'` — контейнеры без своего аудио ('Albums', 'LP', 'Синглы', 'Artwork', 'Covers') проходятся насквозь и карточек не получают. Мультидиски ('Album/CD1','/CD2') — по ОТДЕЛЬНОЙ карточке на диск (решение пользователя от 2026-08-29), папка-обёртка без аудио карточки не получает. Треки прямо в папке артиста (вне альбомных подпапок) → отдельная карточка `TRACKS_CARD_TITLE='Треки'` с `folder_id` самой папки артиста; чтобы она не играла весь плейлист артиста, в `MusicAlbumCard` (schemas.py) добавлено поле `is_tracks: bool = False` — выводится в роутере (`_album_card`: `alb.folder_id == artist.folder_id and kind != standalone`) БЕЗ миграции БД; фронт (`MusicLibrary.jsx`, `playFolder(..., opts)`) при `is_tracks` играет папку обычным листингом `fileApi.list('/api/files?folder_id=')` (items — те же `FileResponseModel`, плеер совместим), замороженный `tracks-recursive` не тронут. Карточке «Треки» сразу ставится `enriched_at` (MB-поиск по слову «Треки» бессмыслен; иначе артист из-за `all_albums_attempted` вечно числится не обогащённым). Очистка фантомов (`valid_fids`) теперь работает от нового набора — старые карточки-контейнеры от прежней логики удаляются при следующем sync. Live-результат: sync создал 1776 карточек (Bloodhound Gang — 5 альбомов из-под 'Albums'; Metallica — альбомы + отдельные CD-карточки; «Вагинальная спазма» — 5 альбомов + «Треки»). Тесты: `test_music_library.py` 31 passed (+5: вложенность глубиной 2–3, мультидиск, «Треки», очистка фантомов, `is_tracks` в API).

## Правило зоны

Music Mode (`playerStore.js`, `MusicMode.jsx`, `AudioPlayer.jsx`, `PlayerBar.jsx`, `tracks-recursive`, stream tickets, precache, визуализаторы, playlists API для Music Mode) — замороженная зона: правки только по явному запросу пользователя. 2026-08-16 — две разовые разморозки: (1) пакет исправлений аудита, (2) управление плейлистами (см. `K:\Test\Replit\walkthrough.md`).

## Music Library — Last.fm фолбэк (2026-08-30)

Добавлен 4-й источник метаданных в `music_library_service.py` — **Last.fm** (опциональный, ключ `LASTFM_API_KEY` в `app.env`; shared secret хранится, но read-методам не нужен, callback URL не используется). Хелперы: `_lastfm_get`, `_lastfm_artist_fallback` (artist.getinfo, lang=ru), `_lastfm_album_cover` (album.getinfo), `_lastfm_image` (extralarge→mega→large), `_strip_html` (чистка bio-тегов Last.fm).

Точки подключения:
- `_enrich_one_artist`: после Wikipedia-блока — био/фото артиста, только если Wikipedia ничего не дал.
- `_enrich_single_album`: (1) ветка rg is None + data not None (MB не сматчил) — попытка обложки перед фиксацией enriched_at; (2) после CAA при найденном rg, если обложки нет.
- Без ключа фолбэк молча пропускается (`_lastfm_get` возвращает None) — код безопасен и без env.

Пользователь предоставил ключи 30.08.2026, но хост-сandbox блокирует запись в `app.env` — ключи пользователь добавляет вручную (бэкап `backups/app.env.backup-20260830-lastfm.txt` сделан). Тесты: test_music_library 36 passed.

## Music Library — Discogs фолбэк (2026-08-30)

Добавлен 5-й источник в `music_library_service.py` — **Discogs** (опциональный, `DISCOGS_CONSUMER_KEY`/`DISCOGS_CONSUMER_SECRET` в app.env). OAuth-флоу НЕ используется: для read-only `/database/search` ключи передаются query-параметрами `key`/`secret` (лимит 60 req/мин). Хелперы: `_discogs_get`, `_discogs_artist_fallback` (type=artist, profile-био + cover_image), `_discogs_album_cover` (type=release, release_title+artist; без artist-фильтра — защита по схожести названия ≥75%).

Порядок фолбэков: артист Wikipedia → Last.fm → Discogs; альбом MusicBrainz+CAA → Last.fm → Discogs. Без ключей все фолбэки молча пропускаются. Ключи предоставлены пользователем 30.08.2026; в app.env добавляются вручную (host-блокировка записи). Тесты: 36 passed, ключ проверен вживую.

## Music Library — v2: deep-clean имён + ускорение обогащения (2026-08-30)

Переработан `music_library_service.py` после скана БД (262 артиста / 3828 альбомов, было 1414 обложек = 37%).

**Deep-clean имён** (`_deep_clean` + `split_artist_album` v2): срезает ведущие номера дисков ('01 ', '05 - '), ведущий год ('1977 Kraftwerk - ...'), приклеенный год ('1980Слонолуние'), скобки/каталог-коды; хвостовой год срезается перед plain-сплитом; plain-сплит теперь ЛЕНИВЫЙ по первому дефису с пробелами ('Артист - Альбом'; 'Pr-Mex', 'Панк-Москва' не режутся); ', The'-хвосты ('Биты, The' -> 'Биты'). Карточки-диски ('(CD1)', '1', 'Disc 2') = `is_non_album_title`, в сеть не ходят.

**Скорость (главное):** (1) все MB-вызовы через глобальный гейт `_MB_GATE` 1.05 c вместо sleep'ов вокруг каждого вызова; (2) release-groups артиста выгружаются СПИСКОМ (browse, пагинация) и матчатся локально (`_match_release_group_locally`, порог 65 + годовой бонус 8) — 1-2 MB-запроса на артиста вместо per-album поиска; (3) CAA по всем альбомам артиста — параллельно (семафор 6); (4) фолбэки Last.fm -> Discogs параллельно (семафор 4); (5) bio/img артиста: Wikipedia + Last.fm + Discogs в одном gather, приоритет wiki -> LF -> D. Безуспешные попытки ретраятся не чаще RETRY_AFTER_HOURS=24 (плановый проход каждые 15 мин больше не бьёт по лимитам Discogs 60/мин); разовый полный ретрай — `enrich_library(retry_stale_hours=-1)`.

**Результат прогона 30.08.2026** (80 артистов / 1368 альбомов за 49 мин, retry_stale=-1): обложки 1414 -> 2288 (+874, 60%), био 87 -> 123, фото 184 -> 208, mbid 153 -> 169. Остаток без обложек (~1540) — орк-релизы (русский панк/кассетные рипы), отсутствуют у всех провайдеров; пороги схожести (55/65/75) намеренно не занижены ради защиты от чужих обложек. Отчёт с планом запросов: `music_metadata_scan_report.md` (в корне репо). Тесты: 45 passed (обновлены ожидания split, добавлены кейсы v2).
