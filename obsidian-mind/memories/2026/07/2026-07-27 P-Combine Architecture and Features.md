---
date: 2026-07-27
description: "P-Combine is a web automation suite designed for semi-automated Make.com account registration/management and Pinterest integration."
tags: [memory]
source: mcp-capture
origin: "p-combine"
session: "2026-07-27T10:39:24.533Z"
scope: project
projects: ["p-combine"]
confidence: verified
---

# P-Combine Architecture and Features

P-Combine is a web automation suite designed for semi-automated Make.com account registration/management and Pinterest integration.

Key Features:
1. Make.com Registration: Automates signup & onboarding/activation via Playwright-stealth browser automation (frozen registration & onboarding core services). Toggles proxies, handles manual CAPTCHA solving, and integrates email verification URL retrieval.
2. Pinterest Parser: Scrapes Pinterest pins dynamically, exporting metadata to Excel.
3. Pinteregger: Automated Pinterest account registration using anti-detect browser profiles.
4. PinPosting System: Auto-posts pins to Pinterest via Make.com webhooks, supported by LLM content generation.
5. Text Unicalizer (Text Uniquizer): Rewrites/uniquizes text content.
6. Utilities: Includes Excel processor, credential generator, keyword generator, and Netlify site creator.

Tech Stack:
- Backend: Python 3.11+, FastAPI, SQLAlchemy + PostgreSQL (asyncpg) / SQLite (fallback), Playwright, SSE (sse-starlette) for real-time task progress.
- Frontend: React (Vite, TS), Tailwind CSS.
- Storage: Legacy JSON (accounts.json, settings.json, proxies.txt) and SQLAlchemy models.

Key Constraints & Rules:
- Windows Proactor Event Loop Policy is enforced at startup (run.py).
- Core registration services (registration.py, onboarding.py), authorization, account pool, and settings code are strictly frozen.
- Playwright instances must launch through browser_factory.py.
- The scenario importer uses system Chrome CDP (pyppeteer_factory.py).
