---
type: reference
topic: PinHarvesterPro
component: ideas
description: Возможные доработки, ограничения, идеи интеграций и проверенных гипотез по расширению.
tags:
  - chrome-extension
  - ideas
  - roadmap
related:
  - Index
  - Architecture
  - Parser Model
  - Interception
  - Background & Downloads
  - Popup & Storage
---

# Extensions & Ideas

## Verified limitations
- Сбор зависит от текущей страницы Pinterest и её hydration.
- При смене DOM/имен классов часть селекторов может устареть.
- `chrome.downloads` ограничена браузером и политиками сохранения.
- Нет встроенного Obsidian-экспорта/синхронизации.
- Autoscroll может преждевременно останавливаться при плавной анимации скролла; исправлено переходом на остановку по пустым сканам.
- При переключении вкладок расширение не продолжает фоновый парсинг; решено частично через сохранение состояния автопрокрутки в session.

## Implemented
- Дедупликация по title в `content.js` и `popup.js`.
- Quality filter для экспорта: отбрасывание пинов без title/description/original.
- CSV с UTF-8 BOM для Excel.
- HTML analytics export с самодостаточным отчётом.
- Автопрокрутка по пустым сканам вместо скролл-done.
- Дебаунс фильтров 250 ms.
- Аналитика оптимизирована для 4000+ записей.
- Сохранение состояния автопрокрутки в `chrome.storage.session`.
- Остановка автопрокрутки при смене вкладки/перезагрузке.

## Ideas
- Наблюдатель за `history.pushState`/`fetch` для SPA-навигации Pinterest.
- Кэширование исходных JSON-ответов в `chrome.storage.session`.
- Dedup по `pinId` и нормализованному `link`.
- Пакетный экспорт в Obsidian: `.md`-заметки с frontmatter, preview, excerpt.
- Интеграция с QMD/OM для полнотекстового поиска по собранным пинам.
- Он_device OCR/классификация изображений через локальную модель.
- Автоматическое обогащение `dominantColor` кластерами.
- Поддержка board sections и richer `rich_metadata`.
- Вынос `MAX_INTERCEPTED_RETURN` и `EMPTY_SCAN_LIMIT` в настройки UI.
- Фоновая задача через `chrome.alarms` для периодического резюме сканирования.

## Open questions
- Нужна ли полная поддержка video pins?
- Следует ли сохранять raw intercepted bodies?
- Насколько агрессивно может работать autoscroll без бана/тормозов?
