---
type: reference
topic: PinHarvesterPro
component: parser
description: Модель данных пина, поля, источники извлечения, fallback-цепочка объединения метаданных и ограничения перехвата.
tags:
  - chrome-extension
  - parser
  - pinterest
  - data-model
  - dedup
related:
  - Index
  - Architecture
  - Interception
  - Background & Downloads
  - Popup & Storage
---

# Parser Model

## Pin fields
- `key` — нормализованный идентификатор изображения/пина.
- `original` — прямой URL оригинала на `i.pinimg.com`.
- `preview` — URL превью.
- `title` — заголовок.
- `description` — описание.
- `author` — автор.
- `authorUrl` — URL профиля автора.
- `board` — название доски.
- `boardUrl` — URL доски.
- `repins` — количество репинов.
- `likes` — количество лайков.
- `comments` — количество комментариев.
- `hashtags` — хэштеги.
- `link` — внешняя ссылка.
- `linkDomain` — домен внешней ссылки.
- `siteName` — название сайта.
- `pinUrl` — URL пина на Pinterest.
- `width` / `height` — размеры изображения.
- `dominantColor` — доминантный цвет.
- `timestamp` — время создания.

## Sources
- SSR hydration: `__PWS_DATA__`, `__PWS_INITIAL_PROPS__`, `__PWS_ROUTES__`
- Window objects: `PWS_DATA`, `RELAY_DATA`, `INITIAL_STATE`, `__PWS_DATA__`
- `application/json` script tags
- Intercepted API bodies from `interceptor.js`
- React Fiber через `__reactFiber$` / `__reactInternalInstance$`
- DOM metadata: `data-test-id`, alt, meta description

## Merge priority
1. Image URL parsing → `key`, `original`, `preview`
2. Hydration merge → metadata, link, counts
3. Intercepted API merge → дополнительные поля
4. React merge → author, board, hashtags
5. DOM fallback → title, description, link, pinUrl, timestamp
6. Derived: `linkDomain`, `hashtags` из description, `dominantColor`

## Interception buffer limit
- `MAX_INTERCEPTED_RETURN = 120`: за один скан из перехваченного буфера возвращается не более 120 пинов.
- Это предотвращает ложный пересчёт 800+ пинов при 40 реальных элементах на странице.

## Title deduplication
- Нормализация: lowercase + collapse whitespace + truncate to 120 chars.
- Применяется в `content.js` после merge и в `popup.js` при добавлении в проект.
- Сохраняет первое вхождение, последующие дубли отбрасываются.
- Отдельно от глобального `ph-seen-db` ключевого дедупа.

## Quality filter
- На этапе экспорта можно отбросить пины без `title` или `description` или `original`.
- Фильтр не влияет на коллекцию, только на экспорт.
