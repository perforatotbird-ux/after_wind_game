---
date: 2026-07-27
description: "P-Combine Directory Structure & Components: 1."
tags: [memory]
source: mcp-capture
origin: "p-combine"
session: "2026-07-27T10:40:34.820Z"
scope: project
projects: ["p-combine"]
confidence: verified
---

# P-Combine Codebase Deep Dive Analysis

P-Combine Directory Structure & Components:

1. Backend Layout (backend/app/):
   - api/: REST Endpoint routers (accounts, registration, proxies, settings, parser, pinteregger, uniquizer, utilities, pin_posting, mail_accounts).
   - core/: Orchestration tools.
     * browser_factory.py: Playwright instances pool with SOCKS5/HTTP proxies and session cookie import converter.
     * pyppeteer_factory.py: Custom Chrome CDP helper for imports.
     * email_checker.py: Polls temporary mail services (maildrop, firstmail) to parse activations.
     * encryption.py: Fernet-based encryption for sensitive credentials.
     * uniquizer_pool.py: Engine for text rewriting.
     * progress.py: SSE events broadcaster.
   - services/: Task logic.
     * registration.py & onboarding.py: Automation sequences (Make.com accounts).
     * parser_service.py: Pinterest scraper worker.
     * pinteregger_service.py: Bulk Pinterest registrar.
     * credential_generator_service.py, excel_processor_service.py, site_creator_service.py, keyword_generator_service.py: Utilities package.
     * pin_posting_service.py, pin_account_service.py: Webhook postings and scheduling.
   - db/: Database core.
     * database.py: Async engine & async_sessionmaker setup.
     * models.py: Relational schema using SQLAlchemy (mapped to PostgreSQL or SQLite fallback).
       - AccountDB, ProxyDB, ParsedProjectDB, ParsedPinDB, PinPostingAccount, PinPostingPin, PinPostingError, PinTransmissionLog, MailAccountDB (not shown but present).

2. Frontend Layout (frontend/src/):
   - components/: React views for each tab.
     * Dashboard.tsx: Aggregated analytics.
     * Registration.tsx: Make.com accounts registration console.
     * AccountPool.tsx: Displays accounts, credentials, status, proxies, and handles manual/auto authorizations.
     * Parser.tsx: Scraper console with support for projects, tags, search queries, infinite scrolls, and downloads.
     * Pinteregger.tsx: Anti-detect browser profiles and registration controls.
     * ProxyManager.tsx: Validates and manages proxy sets.
     * PinPostingSystem.tsx: Panel for Make.com webhook configurations, LLM-based title/desc changes, and batch schedule.
     * Utilities.tsx & Unicalizer.tsx: Multi-tool suite.
   - services/api.ts: Unified API request module.
   - hooks/useSSE.ts: SSE stream hook.

Data-flow logic:
- REST API sets up commands -> SSE events transmit real-time details -> PostgreSQL stores active states.
- Anti-detection: browser_factory intercepts headers, user-agents, and utilizes playwright-stealth to prevent footprint leaks.
