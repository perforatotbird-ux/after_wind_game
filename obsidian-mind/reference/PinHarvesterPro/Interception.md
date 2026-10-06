---
type: reference
topic: PinHarvesterPro
component: interception
description: Механизм перехвата сетевых ответов Pinterest, обработка SSR/API, лимит буфера и сбор DOM-метаданных.
tags:
  - chrome-extension
  - interception
  - pinterest
  - dom
  - react
related:
  - Index
  - Architecture
  - Parser Model
  - Background & Downloads
  - Popup & Storage
---

# Interception

## interceptor.js
- Перехватывает `window.fetch` и `XMLHttpRequest`.
- Отбрасывает изображения, шрифты и CSS.
- Отправляет тела ответов через `window.postMessage({ type: '__PH_CAPTURED__', payload })`.
- Дополнительно собирает SSR из `__PWS_DATA__` / `__PWS_INITIAL_PROPS__`.

## content.js
- Слушает `window.message` и аккумулирует пины в `interceptedPins`.
- Сканирует:
  - SSR-теги и window-объекты.
  - `application/json` script-теги.
  - DOM-изображения через `document.images`.
  - React Fiber у изображений.
  - DOM-метаданные вокруг пинов.
- Возвращает не более `MAX_INTERCEPTED_RETURN = 120` пинов из буфера за один скан.
- После merge применяет дедупликацию по нормализованному title.

## DOM fallback
- Контейнеры: `[data-test-id="pin"]`, `[data-test-id="pinWrapper"]`, `.Pin`, `article`, `[role="listitem"]`.
- Поля: title, description, author, board, repins, link, pinUrl, timestamp.
- Очистка alt/description от шаблонных префиксов.

## React Fiber
- Достаёт `__reactFiber$` / `__reactInternalInstance$`.
- Поднимается до 40 уровней вверх по `fiber.return`.
- Ищет объект с `images.originals`, `images.736x` и пр.
- Строит pin из `pinner`, `board`, `rich_metadata`.

## Buffer management
- `interceptedPins` — Map с полными pin-объектами из API/SSR.
- При скане优先 возвращаются DOM/hydration пины, затем ограниченная порция из intercepted buffer.
- Это предотвращает насыщение popup ложными duplicates и перегрев памяти.
