---
date: 2026-07-27
description: "Fixed page scrolling issue when navigating to the Utilities tab by replacing window-scrolling scrollIntoView() calls with inner container scrollTop up"
tags:
  - project-note
source_repo: p-combine
---

# Fix Utilities Tab Window Auto-Scroll Issue

Fixed page scrolling issue when navigating to the Utilities tab by replacing window-scrolling scrollIntoView() calls with inner container scrollTop updates.

## What changed

- frontend/src/components/utilities/ExcelProcessor.tsx, CredentialGenerator.tsx, KeywordGenerator.tsx, SiteCreator.tsx - Replaced scrollIntoView({ behavior: 'smooth' }) with containerRef.current.scrollTop = containerRef.current.scrollHeight when logs.length > 0.


## Decisions

- Isolated auto-scroll behavior to the internal scrollbars of log container divs instead of calling Element.scrollIntoView(), preventing the window viewport from shifting to the bottom on tab mount.


## Learned

- Calling Element.scrollIntoView() on log placeholders during React component mount triggers full window viewport scrolling. Using containerRef.scrollTop = containerRef.scrollHeight keeps page scroll position completely intact.


## Verification

Built frontend using npm run build with 0 compilation errors (exit code 0).




_Recorded 2026-07-27T15:50:48.938Z from `p-combine` via the om MCP server (routing: fallback)._
