---
type: reference
topic: PinHarvesterPro
component: architecture
description: Архитектура расширения, manifest, permissions, communication между background/content/popup и общий поток данных.
tags:
  - chrome-extension
  - architecture
  - manifest-v3
related:
  - Index
  - Interception
  - Background & Downloads
  - Popup & Storage
---

# Architecture

## Manifest
- `manifest_version`: 3
- Разрешения: `downloads`, `storage`, `tabs`, `unlimitedStorage`, `alarms`
- Хосты: `*://*.pinterest.com/*`, `https://i.pinimg.com/*`
- Content scripts:
  - `interceptor.js` — `document_start`, `world: MAIN`
  - `content.js` — `document_idle`
- Background: `service_worker` — `background.js`

## Компоненты
- `interceptor.js` — перехват `fetch` и `XHR`, отправка SSR/API тел в контент-скрипт.
- `content.js` — сбор пинов из SSR, window, React Fiber, DOM, API-буфера; лимит возврата перехваченных пинов; дедупликация по title.
- `background.js` — пакетные загрузки, аналитика, экспорт CSV/JSON/HTML.
- `popup.html` / `popup.js` — UI: проекты, фильтры, автопрокрутка, сканирование, экспорт, аналитика.
- `chrome.storage.local` — персистентное хранилище пинов и настроек.
- `chrome.storage.session` — текущая сессия и состояние автопрокрутки.

## Communication
- Content → Background: `chrome.runtime.onMessage`
- Interceptor → Content: `window.postMessage({ type: '__PH_CAPTURED__', payload })`
- Popup → Background: `chrome.runtime.sendMessage`
- Popup → Content: `chrome.tabs.sendMessage`
- Background ↔ Tabs: `chrome.tabs.onActivated`, `chrome.tabs.onUpdated` для устойчивости автопрокрутки

## Data flow
1. Открывается Pinterest.
2. `interceptor.js` ловит ответы API/SSR.
3. `content.js` сканирует DOM + hydration + intercepted buffer + React Fiber с лимитом `MAX_INTERCEPTED_RETURN`.
4. Результат отправляется в popup по запросу `scan`.
5. `background.js` выполняет скачивание/экспорт по команде.

## Export formats
- CSV: `;`-разделитель, QUOTE_ALL-style escaping, UTF-8 BOM.
- JSON: подмножество полей по выбору.
- HTML Analytics: самодостаточный отчёт со встроенным CSS и CSV-ссылкой.

## Autoscroll resilience
- Состояние автопрокрутки сохраняется в `chrome.storage.session` (`ph-autoscroll-state`).
- При переключении вкладок/перезагрузке страницы автопрокрутка корректно останавливается.
- Остановка по пустым сканам (`EMPTY_SCAN_LIMIT = 4`), а не по «скролл не сдвинулся».

## Performance
- Дебаунс фильтров: 250 ms.
- Аналитика оптимизирована для 4000+ записей: итеративный min/max/sum, предвычисление `boardsByBoard`.
- В коллекции показаны первые 50 пинов, остальные доступны через фильтры.

## Statistics
- Основной счётчик `totalPins` считает только пины с валидным `original` URL.
- `rawTotal` — общее количество записей в проекте, включая неполные.
- Скачивание фильтрует items по `original` перед отправкой в background.
- Download button отключён, если нет пинов с `original`.
- HTML-экспорт корректно передаётся через фоновый обработчик как `html`, а не сводится к `csv`.
