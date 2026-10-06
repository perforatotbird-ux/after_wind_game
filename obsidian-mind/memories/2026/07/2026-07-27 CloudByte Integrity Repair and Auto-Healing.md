---
date: 2026-07-27
description: "CloudByte/TGCloud integrity verification, AutoIntegrityService, IntegrityTool GUI, and automated mirror repair pipeline."
tags: [memory, cloudbyte, tgcloud, integrity, repair, mirroring, auto-integrity]
source: mcp-capture
origin: "replit"
session: "2026-07-27T15:24:41.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte Integrity Repair and Auto-Healing

## Background Integrity System Overview

To guarantee 100% data preservation and resilience against Telegram account bans, revoked sessions, or deleted messages, CloudByte includes a dual-tier integrity verification and self-healing subsystem.

## 1. Automated Background Verification (`backend/services/auto_integrity_service.py`)
- **Worker Loop**: Inspects `MirrorJob` entries with `status == "done"`.
- **Indexing Delay Buffer**: 30-second delay threshold after job completion to allow Telegram servers to index newly forwarded messages.
- **Expected Size Verification**: Calculates expected encrypted size including 32-byte header and GCM tag overheads (`expected_size = size + 32 + num_blocks * 16`).
- **Dead File Flagging**: If all account mirrors for a `VFile` are missing or corrupted, marks `VFile.pending_deletion = True` for audit review.

## 2. Interactive Audit Tool (`IntegrityTool/ict.py` & `backend/services/integrity_service.py`)
Tkinter GUI application and REST API endpoint for deep storage audits:
- **`FolderClosure` Subfolder Fetching**: Single-query recursive folder retrieval.
- **In-Memory Folder Caching**: `folder_cache` pre-fetches folder tree hierarchy to eliminate N+1 SQL queries during file path resolution.
- **Parallel Account Inspection**: Uses `asyncio.gather` across Telegram clients to verify message existence and byte size concurrently.
- **Configurable Batch Pause**: Operates with a 3–6 second pause interval between 200-file batches to avoid hitting API rate limits.

## 3. Bulk Mirroring Pipeline (`backend/services/mirror_service.py`)
Executes 3-stage replication when a broken mirror is detected:
1. **Stage 1 (Forward Source)**: Forwards message from healthy source account to target account.
2. **Stage 2 (Discovery on Target)**: Inspects target account "Saved Messages" to identify newly created message IDs.
3. **Stage 3 (Commit Result)**: Updates `account_map` JSON in database and marks `MirrorJob` as `"done"`.
