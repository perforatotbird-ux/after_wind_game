---
date: 2026-07-27
description: "CloudByte/TGCloud database schema reference, PostgreSQL tables, Closure Table hierarchy, triggers, and VFS optimization."
tags: [memory, cloudbyte, tgcloud, database, postgresql, vfs, models]
source: mcp-capture
origin: "replit"
session: "2026-07-27T15:24:41.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte Database Schemas and VFS

## Database Entity Relationship & Table Schemas (`backend/database.py`)

### 1. `VFile` (`vfiles` table)
Represents a virtual file in the cloud storage system.
- `id` (Integer, Primary Key, Index)
- `name` (String, Index)
- `size` (BigInteger): Original unencrypted size in bytes.
- `mime_type` (String)
- `folder_id` (ForeignKey `folders.id`, Index): Parent folder ID.
- `is_encrypted` (Boolean, default True)
- `encryption_header` (LargeBinary): 32-byte header (16-byte salt + 12-byte base nonce + 4-byte block size LE).
- `msg_ids` (String): Comma-separated message IDs for primary account (`"101,102,103"`).
- `account_map` (JSON): Cluster mirror map (`{"41": {"msg_ids": "101,102"}, "42": {"msg_ids": "501,502"}}`).
- `is_trash` (Boolean, default False, Index)
- `pending_deletion` (Boolean, default False): Flagged by `AutoIntegrityService` if all mirrors are dead.
- `created_at`, `updated_at` (DateTime, `updated_at` DESC default sorting)

### 2. `Folder` (`folders` table)
Represents a virtual directory in the file system tree.
- `id` (Integer, Primary Key, Index)
- `name` (String, Index)
- `parent_id` (ForeignKey `folders.id`, Index, Nullable)
- `is_trash` (Boolean, default False, Index)
- `cached_file_count` (Integer, default 0): Cached file count maintained by PostgreSQL triggers.
- `cached_total_size` (BigInteger, default 0): Cached folder size in bytes.
- `created_at`, `updated_at` (DateTime)

### 3. `FolderClosure` (`folder_closures` table)
Implementation of the **Closure Table** pattern for fast, O(1) hierarchical tree queries without recursive CTE overhead.
- `ancestor_id` (ForeignKey `folders.id`, Primary Key, Index)
- `descendant_id` (ForeignKey `folders.id`, Primary Key, Index)
- `depth` (Integer): Distance between ancestor and descendant (0 for self-reference).

### 4. `MirrorJob` (`mirror_jobs` table)
Tracks background replication tasks across accounts.
- `id` (Integer, Primary Key)
- `vfile_id` (ForeignKey `vfiles.id`, Index)
- `source_account_id` (Integer)
- `target_account_id` (Integer)
- `status` (String: `"pending"`, `"in_progress"`, `"done"`, `"failed"`)
- `created_at`, `updated_at` (DateTime)

### 5. `TGAccount` (`tg_accounts` table)
Cluster Telegram account accounts.
- `id` (Integer, Primary Key)
- `phone` (String, Unique)
- `session_string` (String, AES encrypted)
- `is_active` (Boolean, default True)
- `is_primary` (Boolean, default False)

## VFS Optimizations
- **Closure Table Operations**: Moving/deleting folders updates `folder_closures` atomically via `rebuild_closure_table`.
- **PostgreSQL Triggers**: Automatic maintenance of `cached_file_count` and `cached_total_size` on file insert/update/delete prevents N+1 count queries on the web dashboard.

## DB Perf Audit 2026-09-11 (N+1 / SELECT* / pagination / cache)
Approved scope: all incl. frozen zones. No contract changes (additive limit/offset defaults only). app.env untouched.
N+1 fixed: integrity apply_repairs bulk IN; auto_integrity pending-MirrorJob prefetch; mirror bulk FOR UPDATE lock; music_library bulk metrics/candidates (7 queries vs 5-7xN) + selectinload albums + root-id cache 10m; file_download/sharing bulk VFile IN + path cache + throttled progress; file_service move/copy bulk trash UPDATE; upload batch_init id/name only.
SELECT* fixed: search/folders/playlists/integrity load_only; TGAccount id-only where session_string unneeded. Pagination: tracks-recursive (2000/0), playlist tracks (500/0), artists list (500/0), mirror GC yield_per(1000). Cache: memory TTL + cap 5000, session 72h.
Migration c7d8e9f0a1b2 (revises a1b2c3d4e5f6): 18 IF NOT EXISTS indexes. Tests: fixed pre-broken auto_integrity mock. Baseline-confirmed pre-existing failures: chaos upload_retry, folder_tree FK cleanup on shared dev DB, natural_sort trailing, mirror_stress mock sleep.
