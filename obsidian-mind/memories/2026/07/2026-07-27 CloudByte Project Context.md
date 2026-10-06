---
date: 2026-07-27
description: "CloudByte (TGCloud) project context, tech stack, business logic, core features, and environment configuration."
tags: [memory, cloudbyte, tgcloud, architecture, overview]
source: mcp-capture
origin: "replit"
session: "2026-07-27T15:24:41.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte (TGCloud) Project Context

## Executive Summary
**CloudByte** (also known as **TGCloud**) is a self-hosted, single-user virtual file system (VFS) that uses Telegram "Saved Messages" as an unlimited binary storage layer, and PostgreSQL 16 for metadata, indexing, and folder hierarchy.

It includes:
1. **Web Application**: Built with React 19, Vite 6, TailwindCSS 4, and Zustand 5.
2. **Backend**: Powered by FastAPI 0.115.8 (Python 3.13) and SQLAlchemy 2.0.38.
3. **Android Client**: Native Kotlin application for streaming music and managing cloud files with mDNS local server discovery.

## Key Features & Capabilities
- **Chunking & Storage**: Bypasses Telegram's 2GB file size limit by splitting large files into encrypted 512KB/1MB chunks across multiple Telegram accounts.
- **Multi-Account Cluster**: Distributes file uploads/downloads across a cluster of Telegram accounts (`TGAccount`) to prevent `FloodWait` errors.
- **On-The-Fly AES-256-GCM Encryption**: Streaming encryption/decryption with Master Key protection derived via Argon2id.
- **Hierarchical VFS**: Fast folder operations using PostgreSQL `Closure Table` (`folder_closures`) and trigger-cached file statistics (`cached_file_count`, `cached_total_size`).
- **Music Mode & Player**: Web & Mobile audio player featuring Vinyl, Cassette, and CD visualizers, track pre-caching (3s buffer), equalizer, and mDNS discovery.
- **Auto-Healing & Integrity**: `AutoIntegrityService` and `IntegrityTool` (Tkinter GUI) for detecting missing Telegram parts and automatically repairing broken mirrors via `MirrorJob`.

## Tech Stack Quick Reference
| Layer | Technologies |
| --- | --- |
| **Backend API** | FastAPI 0.115.8, Python 3.13, Pydantic V2, Uvicorn |
| **Database** | PostgreSQL 16, SQLAlchemy 2.0.38, Alembic |
| **Telegram Transport** | Pyrofork (Pyrogram fork ≥ 2.3.60), MTProto |
| **Frontend UI** | React 19, Vite 6, TailwindCSS 4.2, Zustand 5.0 |
| **Mobile App** | Native Android (Kotlin), AsyncZeroconf (mDNS) |
| **Caching & Queue** | RAM Buffer (`MAX_RAM_BUFFER_MB`), Redis / In-Memory Queue |

## Core Configuration (`app.env`)
- `DATABASE_URL`: PostgreSQL connection string.
- `TG_API_ID`, `TG_API_HASH`: Telegram application credentials.
- `ENCRYPTION_MASTER_SALT`, `ENCRYPTION_RECOVERY_KEY`, `ENCRYPTION_WRAPPED_KEY`: Argon2id Master Key settings.
- `MAX_RAM_BUFFER_MB`: RAM limit for streaming and chunk buffering.
- `TG_MAX_CONCURRENT_TRANSMISSIONS`, `TG_UPLOAD_WORKERS`: Multi-client transmission concurrency settings.
- `CUSTOM_TEMP_DIR`: Temp directory strictly configured outside `backend/` to prevent Uvicorn reload loops.
