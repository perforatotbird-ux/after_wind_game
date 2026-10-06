---
date: 2026-09-10
description: "Исправление потери обложек Music Library: перманентное кэширование, стабильный браузерный кэш, асинхронный DNS и in-flight дедупликация"
tags: [memory, cloudbyte, music-library, bugfix, permanent-cache, image-proxy, pydantic]
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# Устранение проблемы потери обложек Music Library и внедрение перманентного кэширования

## 1. Контекст проблемы
Пользователь зафиксировал баг: после перезагрузки сервера в модуле **Music Library** пропадали обложки альбомов и фотографии артистов, сменяясь генеративными цветными заглушками с первой буквой («буква на градиенте»).

Аудит показал, что:
1. В базе данных PostgreSQL ссылки на обложки сохранялись (2681 альбом, 243 артиста), но физические файлы на диск при обогащении не скачивались.
2. В `music_image_cache.py` действовал 48-часовой TTL. Переменная `_last_purge = 0.0` сбрасывалась при рестарте, и первая же проверка удаляла с диска все обложки старше 48 часов.
3. В `MusicLibrary.jsx` функция `imgSrc` использовала `const stamp = v || Date.now()`. В моделях Pydantic (`backend/schemas.py`) поля `enriched_at` не было, поэтому `v` всегда равнялся `undefined`, и на каждый рендер создавался новый URL с миллисекундами, убивая кэш браузера.
4. Синхронный `socket.getaddrinfo` в `_is_safe_host` блокировал event loop FastAPI, а сетевые задержки и блокировки `archive.org` из РФ приводили к ошибкам 502 Bad Gateway.
5. Тег `<img onError={() => setErr(true)}>` навсегда заменял обложку на букву без повторных попыток.

---

## 2. Реализованные изменения

### 2.1. Перманентное кэширование и сетевой слой (`backend/services/music_image_cache.py`)
- **Бессрочный кэш обложек (TTL=0 по умолчанию)**:
  Обложки релизов и артистов статичны во времени. `TTL_HOURS = env_get_int("MUSIC_IMAGE_CACHE_TTL_HOURS", 0)`. При `TTL_SEC == 0` файлы в `cache/music_images/` не протухают и сохраняются бессрочно.
- **Безопасная очистка (`purge_expired`)**:
  Очищает только зависшие временные файлы `*.tmp` старше 1 часа, не затрагивая валидные обложки. `_last_purge` инициализирован текущим временем (`time.time()`).
- **Асинхронный неблокирующий DNS (`is_safe_host`)**:
  Использует `loop.getaddrinfo(host, None)` для проверки SSRF в фоновом пуле потоков без блокировки asyncio event loop. Сохранена синхронная `_is_safe_host` для обратной совместимости.
- **Пул соединений и дедупликация (In-Flight Deduplication)**:
  - Единый `aiohttp.ClientSession` с коннектором `limit=16` и `ttl_dns_roundrobin=300`.
  - Семафор `asyncio.Semaphore(8)` для ограничения конкурентных запросов к внешним ресурсам.
  - Словарь `_in_flight: Dict[str, asyncio.Future]` гарантирует, что если несколько компонентов одновременно запрашивают одну обложку, внешний сетевой запрос выполняется ровно один раз.
  - Автоповтор (до 2 попыток) при сетевых ошибках 429/502/503/504/Timeout.

### 2.2. Контракт Pydantic-схем (`backend/schemas.py`)
- Добавлено поле `enriched_at: Optional[datetime] = None` в:
  - `MusicAlbumCard`
  - `MusicArtistCard`
  - `MusicArtistDetail`
- Позволяет бэкенду передавать временную метку обогащения клиенту для версионирования кэша.

### 2.3. Роутер библиотеки (`backend/routers/music_library.py`)
- В эндпоинтах `list_artists`, `get_artist`, `override_artist` обеспечен проброс `enriched_at`.
- В эндпоинте `/api/music-library/image`:
  - Удалён вызов `purge_expired()` из «горячего» пути запросов.
  - Установлены долгосрочные заголовки HTTP-кэша: `Cache-Control: public, max-age=604800, immutable` и детерминированный `ETag: f'"{key}"'`.
- В эндпоинте `set_cover` задействован асинхронный `await is_safe_host(u)`.

### 2.4. Планировщик сервера (`backend/main.py`)
- Первый запуск фоновой авто-сборки `run_scheduled_enrich` отложен с 1 до 5 минут после старта приложения (`timedelta(minutes=5)`), что исключает конкуренцию за системные ресурсы и сокеты в момент загрузки UI.
- Добавлено корректное закрытие HTTP-сессии `close_session()` при завершении работы сервера.

### 2.5. Фронтенд (`frontend/src/components/MusicLibrary.jsx`)
- **Стабильный `imgSrc`**:
  ```javascript
  function imgSrc(url, v) {
    if (!url) return url
    let src = url
    if (/^https?:\/\//i.test(url)) src = IMG_PROXY + encodeURIComponent(url)
    const stamp = v ? (typeof v === 'string' ? new Date(v).getTime() || v : v) : '1'
    return src + (src.includes('?') ? '&' : '?') + 'v=' + encodeURIComponent(stamp)
  }
  ```
  Исключён `Date.now()`, благодаря чему URL обложек неизменны между рендерами, и браузер полноценно использует свой дисковый HTTP-кэш.
- **Умный retry в `ImgWithFallback`**:
  При ошибке `onError` компонент производит до 2 повторных попыток с возрастающей задержкой (1.5с, 3с). Буквенная заглушка показывается только при стойкой недоступности изображения.
- Проброшен `enriched_at` во всех контекстах вызова `imgSrc`.

---

## 3. Результаты верификации
1. **Сборка фронтенда**: `npm run build` успешно завершена (`built in 19.52s`, 0 ошибок).
2. **Тесты модуля Music Library**: `pytest backend/tests/test_music_library.py` — 47 passed (100%).
3. **Регрессионные тесты БД**: `pytest backend/tests/test_database.py` — 3 passed (100%).
4. **Безопасность**: файл `app.env` остался абсолютно нетронутым; системные VFS-компоненты и логика корзины сохранены в неизменном виде.
