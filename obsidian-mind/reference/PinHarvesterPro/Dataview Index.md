---
type: dataview
topic: PinHarvesterPro
component: index
description: Сводная таблица по заметкам и ключевым сущностям расширения для запросов Dataview.
tags:
  - dataview
  - chrome-extension
  - pinterest
related:
  - Index
  - Architecture
  - Parser Model
  - Interception
  - Background & Downloads
  - Popup & Storage
  - Extensions & Ideas
---

# Dataview Index

```dataview
TABLE
  type,
  component,
  description,
  related
FROM "reference/PinHarvesterPro"
```

## По компонентам
```dataview
TABLE
  component,
  description
FROM "reference/PinHarvesterPro"
WHERE component
SORT component ASC
```

## По темам
```dataview
TABLE
  topic,
  description
FROM "reference/PinHarvesterPro"
WHERE topic = "PinHarvesterPro"
SORT file.name ASC
```

## Связанные заметки
- [[Architecture]]
- [[Parser Model]]
- [[Interception]]
- [[Background & Downloads]]
- [[Popup & Storage]]
- [[Extensions & Ideas]]
- [[Index]]
