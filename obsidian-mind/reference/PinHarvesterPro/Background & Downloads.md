---
type: reference
topic: PinHarvesterPro
component: background
description: Background service worker: загрузка оригиналов, батчинг, аналитика, экспорт CSV/JSON/HTML и устойчивость автопрокрутки.
tags:
  - chrome-extension
  - background
  - downloads
  - analytics
  - export
related:
  - Index
  - Architecture
  - Parser Model
  - Interception
  - Popup & Storage
---

# Background & Downloads

## Downloads
- Пакетная загрузка через `chrome.downloads.download`.
- Параметры: `BATCH = 5`, `DELAY = 1500` ms по умолчанию.
- Имя файла: `<index>-<key>.<ext>`.
- Папка загрузки по умолчанию: `pin-harvester-originals`.
- Подсчёт статусов: `done`, `failed`, `active`.
- После завершения загрузки `URL.revokeObjectURL` откладывается на 10+ секунд.
- Перед запуском загрузки фильтруются только пины с `original` URL.

## Analytics
- Вычисляется в `computeAnalytics(items)`.
- Агрегаты:
  - `totalPins` — только пины с `original` URL
  - `rawTotal` — все записи в проекте
  - `totalBoards`, `totalAuthors`, `withLinks`
  - `topDomains`, `authorDomains`
  - `topHashtags`, `topAuthors`, `topColors`
  - `repinDist`, `likeDist`, `sizeDist`
  - `timeline`, `boardsSummary`
- Цветовые кластеры через `hexDist` с порогом `60`.
- Оптимизирована для 4000+ записей: итеративный расчёт min/max/sum, предвычисление boards.
- HTML-отчёт показывает оба счётчика: `totalPins` и `rawTotal`.

## Export
- Форматы: `csv`, `json`, `html`.
- Поля выбираются через чекбоксы.
- CSV: разделитель `;`, экранирование строк, UTF-8 BOM.
- JSON: подмножество полей по выбору.
- HTML Analytics: самодостаточный HTML-отчёт со встроенным CSS, топ-списками, палитрой, таблицами и ссылкой на CSV.
- Scope: `all` или `filtered`.
- Quality filter: опционально отбрасывает пины без `title`/`description`/`original` на этапе экспорта.
- В `generateExport()` формат `html` корректно проходит через фоневой обработчик и не сводится к CSV.

## Storage keys
- `ph-batch-size`, `ph-delay` — настройки загрузки.
- `ph-autoscroll-state` — состояние автопрокрутки в `chrome.storage.session`.
