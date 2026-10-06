---
date: 2026-07-27
description: "Fixed cookie injection for imported TXT anti-detect profiles and pushed all changes to GitHub branch browser_adjustments."
tags:
  - project-note
source_repo: p-combine
---

# Fix Cookie Expiration Parsing and Push Code to GitHub

Fixed cookie injection for imported TXT anti-detect profiles and pushed all changes to GitHub branch browser_adjustments.

## What changed

- backend/app/services/pinteregger_service.py & backend/app/core/browser_factory.py - Fixed cookie timestamp parsing in TXT import and launch_system_chrome. ISO dates are now converted to Unix float timestamps before calling context.add_cookies().
- Pushed commit ce3d4b3 to remote branch origin/browser_adjustments.


## Decisions

- Converted string ISO 8601 cookie expiration dates to float Unix timestamps to meet Playwright add_cookies strict schema requirements.


## Learned

- Playwright raises an exception when passed string expiry dates in add_cookies, which prevents all remaining cookies from being injected. Converting ISO strings to float timestamp seconds fixes session cookie persistence completely.


## Verification

Verified Pinterest login status via Playwright test script (Auth Cookie present: True) and pushed code to origin/browser_adjustments with exit code 0.




_Recorded 2026-07-27T14:05:25.048Z from `p-combine` via the om MCP server (routing: fallback)._
