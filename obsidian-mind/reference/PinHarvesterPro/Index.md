---
type: index
topic: PinHarvesterPro
component: docs
description: Навигация по исходникам и знаниям о расширении PinHarvester Pro: архитектура, парсер, хранение, экспорт и возможные доработки.
tags:
  - chrome-extension
  - pinterest
  - pin-parser
  - obsidian-knowledge
related:
  - Architecture
  - Parser Model
  - Interception
  - Background & Downloads
  - Popup & Storage
  - Extensions & Ideas
  - Dataview Index
---

# PinHarvesterPro — индекс заметок

## С чего начать
- [[Architecture]] — общая архитектура и поток данных между компонентами.
- [[Parser Model]] — что такое Pin, какие поля извлекаются и из каких источников.
- [[Interception]] — как перехватываются ответы Pinterest и как строится DOM-парсинг.
- [[Background & Downloads]] — загрузка оригиналов, аналитика и экспорт.
- [[Popup & Storage]] — проекты, фильтры, UI и постоянное хранилище.
- [[Extensions & Ideas]] — гипотезы доработок, ограничения и направления.
- [[Dataview Index]] — сводная таблица по заметкам и ключевым сущностям.

## Источники в репозитории
- `manifest.json`
- `interceptor.js`
- `content.js`
- `background.js`
- `popup.html`
- `popup.js`

## Dataview
Смотри [[Dataview Index]] для сводных таблиц по компонентам, полям пинов и статусам загрузки.
