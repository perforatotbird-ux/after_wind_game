---
title: "Android Music Mode Client (CloudByte / TGCloud)"
date: 2026-09-02
tags: [cloudbyte, android, music-mode, media3, exoplayer]
---

# Нативный Android-клиент CloudByte Music Mode

> Исходный репозиторий бэкенда: `K:\Test\Replit` (ветка `final-refactoring`).
> Код клиента: `K:\Test\Replit\android_app` (namespace `com.cloudbyte.music`).
> Аудит/контракты: `android_music_audit.md`, `android_api_contract.md`,
> `android_architecture.md`, `android_implementation_plan.md` (в корне репозитория).

## Назначение

Воспроизводим поведение веб Music Mode как **нативное** Android-приложение
(API 34, minSdk 24), без WebView:

- Библиотека: Artists / Albums / Compilations / Collections (те же 4 секции,
  что и в вебе);
- Плеер: play/pause/seek/next/prev/shuffle/repeat/buffering/volume/progress;
- Стриминг: HTTP Range + ticket-based (как в `backend/routers/file_download.py`);
- Плейлисты: создание/переименование/удаление/перестановка/удаление треков;
- MediaSession: lock-screen / Bluetooth / уведомление (фоновое воспроизведение);
- Поиск (клиентский фильтр — выделенного эндпоинта нет, как и в вебе);
- Персистентность: DataStore (настройки + очередь) и EncryptedSharedPreferences
  (сессионный токен + пароль vault, AndroidKeyStore).

## Стек

| Слой | Технология |
|------|-----------|
| UI | Jetpack Compose + Material 3 |
| Аудио | Media3 ExoPlayer (`exoplayer`/`exoplayer-common`/`exoplayer-dash`) |
| Фон/транспорт | Media3 `MediaSessionService` + `MediaNotification` |
| Сеть | Retrofit 2.11 + OkHttp 4.12 + kotlinx-serialization |
| Картинки | Coil 2.6 |
| Хранилище | DataStore Preferences + security-crypto (EncryptedSharedPreferences) |
| Асинхронность | Coroutines / Flow / StateFlow |

Версии фиксированы в `android_app/build.gradle.kts`: AGP 8.5.2, Kotlin 1.9.24,
Compose BOM 2024.06.00, Media3 1.3.1.

## Архитектура (пакеты)

```
core/        network (CookieInterceptor, ApiClient), auth (SessionStore),
             storage (SettingsStore, QueueStore), util (CoverUrl, PlaybackModes)
domain/      model (Track, Artist, Album, Playlist, MusicSection)
data/        remote (ApiService, Dto), mapper (Mappers), repository (Auth/Music/Playlist/Stream)
player/      QueueManager (чистый порт playerStore), PlayerEngine (ExoPlayer+оркестрация), PlaybackState
service/     MusicPlaybackService (MediaSessionService)
ui/          login / library / player / playlists / settings / navigation / theme + MainApplication/MainActivity
di/          AppContainer (ручная компоновка зависимостей)
```

Источник истины очереди — `QueueManager` (чистый Kotlin, покрыт тестами).
`PlayerEngine` готовит `MediaItem` и синхронизирует `PlaybackState`. MediaSession
живёт в `MusicPlaybackService` и подключён к тому же ExoPlayer-инстансу
(создаётся один раз в `AppContainer`, в `Application`), поэтому lock-screen
работает в фоне.

## Соответствие контрактам backend

- **Auth**: `POST /api/auth/login` → cookie `tgvfs_session` (HttpOnly,
  SameSite=Strict, 72ч). `CookieInterceptor` добавляет её к Retrofit-запросам;
  для ExoPlayer cookie проставляется в `DefaultHttpDataSource` (см. `PlayerEngine`).
- **Стриминг**: обычный файл → `GET /api/files/{id}/download` (cookie);
  зашифрованный → `POST /api/files/{id}/stream-ticket {password}` →
  `GET /api/files/{id}/download?ticket=<t>` (билет 1ч, привязан к file_id).
  Пароль vault берётся из `SessionStore`. При протухании ticket — 1 авто-retry.
- **Library**: `GET /api/music-library/artists?section=` возвращает
  `MusicArtistCard` для ВСЕХ 4 секций; `GET /api/music-library/artists/{id}`
  — артист + альбомы; `GET /api/files/tracks-recursive?folder_id=` — треки папки.
- **Playlists**: `GET/POST/PUT/DELETE /api/playlists`, `.../{id}/tracks`,
  `.../{id}/tracks/reorder` (track_id = vfile_id = `Track.id`).
- **Картинки**: `CoverUrl.resolve` — внешний https проксируется через
  `/api/music-library/image?url=<encoded>`, относительный дописывается к baseUrl.

**Бэкенд не менялся** — клиент лишь переиспользует существующие эндпоинты.

## Сборка

```bash
cd android_app
# gradle wrapper генерируется Android Studio при импорте проекта,
# либо: gradle wrapper --gradle-version 8.9
./gradlew assembleDebug      # debug APK
# или откройте android_app в Android Studio (SDK Platform 34, JDK 17)
```

`android_app/gradle/wrapper/gradle-wrapper.properties` уже указывает `gradle-8.9`.
Бинарный `gradle-wrapper.jar` + `gradlew`/`gradlew.bat` создаются средой
(Android Studio / `gradle wrapper`).

## Ограничения / что НЕ сделано

- **EQ и визуальные режимы винила** из веба не реализованы (только UI-заметка
  в настройках). ExoPlayer `MediaSession` не экспонирует кнопку shuffle на
  lock-screen (ExoPlayer не поддерживает shuffle; в приложении shuffle работает
  через `QueueManager`).
- **Добавление треков в плейлист из библиотеки** доступно на уровне
  `PlaylistRepository.addTrack`, но без UI-пикера (планируется).
- Сборка APK в песочнице агента **не запускалась** (нет Android SDK); код
  написан под проверяемые контракты и официальные паттерны Media3, но должен
  быть скомпилирован на машине разработчика.

## Безопасность

- Сессионный токен и пароль vault хранятся в `EncryptedSharedPreferences`
  (AndroidKeyStore, AES256-GCM) — не в открытом виде.
- Очередь и настройки — в DataStore (plain), чувствительных данных не содержат.
