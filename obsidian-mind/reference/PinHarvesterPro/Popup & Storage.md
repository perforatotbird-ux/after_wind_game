---
type: reference
topic: PinHarvesterPro
component: popup
description: Popup UI, проекты, фильтры, автопрокрутка, экспорт, аналитика и хранение в chrome.storage.
tags:
  - chrome-extension
  - popup
  - storage
  - filters
  - autoscroll
  - export
  - analytics
related:
  - Index
  - Architecture
  - Parser Model
  - Interception
  - Background & Downloads
---

# Popup & Storage

## Storage
- Глобальная база распарсенных пинов: `ph-seen-db`.
- Проекты: `ph-projects`, `ph-current-project`, `ph-items-<id>`.
- Настройки: `ph-settings`.
- Экспорты: `ph-exports`.
- Состояние автопрокрутки: `ph-autoscroll-state` в `chrome.storage.session`.

## Projects
- Создание, переключение, переименование, удаление.
- Миграция legacy: `ph-items` → `Default` проект.
- Глобальная база сохраняется при удалении проекта.
- Дедупликация по title при merge: нормализация lowercase + collapse whitespace + truncate 120 chars.

## UI tabs
- `collection` — grid, фильтры, сортировка, первые 50 пинов.
- `analytics` — агрегаты по доменам, авторам, хэштегам, цветам, размерам.
- `boards` — доски, top author, домены, competitor URL.
- `export` — поля, формат, scope, quality filter, аналитика HTML.
- `settings` — тема, загрузка, проекты, сброс.

## Filters
- query: title, description, author, board, linkDomain, hashtags.
- board, author, minRepins.
- sort: date, repins, random.
- Дебаунс: 250 ms.

## Autoscroll
- Каждые ~2 сек: scroll-step + scan.
- Остановка после `EMPTY_SCAN_LIMIT = 4` пустых сканов подряд.
- Визуальный индикатор `auto-press` на кнопке Scan.
- Состояние сохраняется в `chrome.storage.session` при переходе между вкладками.
- При переключении вкладки или перезагрузке страницы автопрокрутка останавливается.

## Export & Analytics
- Quality filter checkbox: `export-only-complete` — экспортировать только пины с title + description + original.
- HTML Analytics: кнопка «Экспортировать аналитику HTML» генерирует самодостаточный отчёт.
- CSV: UTF-8 BOM для корректного открытия в Excel.
- Recent exports: до 20 последних экспортов в `ph-exports`.

## Statistics
- Основной счётчик в collection/analytics считает только пины с `original`.
- Рядом показывается `rawTotal` — общее число записей проекта.
- Скачивание отправляет в background только пины с `original`.
- Кнопка «Скачать» блокируется, если нет пинов с `original`.

## Theme
- `auto`, `light`, `dark`.
- CSS variables в `popup.html`.
