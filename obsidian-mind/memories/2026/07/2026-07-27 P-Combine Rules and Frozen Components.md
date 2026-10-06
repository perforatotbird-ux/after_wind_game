---
date: 2026-07-27
description: "This document details frozen structures and files that must NOT be modified in P-Combine."
tags: [memory]
source: mcp-capture
origin: "p-combine"
session: "2026-07-27T10:39:27.181Z"
scope: project
projects: ["p-combine"]
confidence: verified
---

# P-Combine Rules and Frozen Components

This document details frozen structures and files that must NOT be modified in P-Combine.

List of Frozen Backend Services & APIs:
- backend/app/services/registration.py (Make.com signup workflow)
- backend/app/services/onboarding.py (Make.com onboarding flow)
- backend/app/services/auth_service.py (Account pool auth)
- backend/app/api/accounts.py & backend/app/api/authorize.py (Account endpoints)
- backend/app/services/parser_service.py & backend/app/api/parser.py (Pinterest parsing logic)
- backend/app/services/pinteregger_service.py & backend/app/api/pinteregger.py (Pinterest accounts setup)
- backend/app/services/cookie_robot_service.py, backend/app/core/uniquizer_pool.py, backend/app/api/uniquizer.py & backend/app/services/uniquizer_service.py
- backend/app/services/pin_account_service.py, pin_content_service.py, pin_webhook_service.py, pin_posting_service.py, pin_llm_service.py, and backend/app/api/pin_posting.py (PinPosting system)
- backend/app/services/excel_processor_service.py, credential_generator_service.py, site_creator_service.py, keyword_generator_service.py, backend/app/api/utilities.py (Utilities tab)

Frozen Frontend Components:
- frontend/src/components/AccountPool.tsx, Parser.tsx, Pinteregger.tsx, Unicalizer.tsx, ProxyManager.tsx, Utilities.tsx, PinPostingSystem.tsx, Settings.tsx

State & Data Persistence:
- Relies on PostgreSQL (primary) via asyncpg & SQLAlchemy ORM.
- Fallback database: SQLite (backend/app/storage/app.db).
- Legacy accounts.json files are maintained only for backwards compatibility.
- Settings are in backend/app/storage/settings.json or handled by settings_api.py.
