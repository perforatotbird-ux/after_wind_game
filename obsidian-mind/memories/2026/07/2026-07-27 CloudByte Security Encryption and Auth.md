---
date: 2026-07-27
description: "CloudByte/TGCloud security model, AES-256-GCM streaming encryption, Argon2id key derivation, authentication JWT, and zero-trust stream tickets."
tags: [memory, cloudbyte, tgcloud, security, encryption, auth, argon2]
source: mcp-capture
origin: "replit"
session: "2026-07-27T15:24:41.000Z"
scope: project
projects: ["cloudbyte", "replit"]
confidence: verified
---

# CloudByte Security Encryption and Auth

## Streaming Encryption Architecture (`backend/encryption.py`)
All files uploaded to CloudByte are encrypted on the fly before transmission to Telegram servers. Telegram only sees binary encrypted payloads.

### 1. 32-Byte Header Specification
Each encrypted file stores a fixed 32-byte header:
- **Bytes 0..15** (16 bytes): Per-file random Salt (`os.urandom(16)`).
- **Bytes 16..27** (12 bytes): Base Nonce / Initialization Vector (`os.urandom(12)`).
- **Bytes 28..31** (4 bytes): Block Size in Little-Endian integer (`1048576` bytes = 1MB).

### 2. Encryption Algorithm
- **Algorithm**: AES-256-GCM (Galois/Counter Mode).
- **Key Derivation**: Argon2id KDF derives key from `master_key` and per-file salt:
  `key = Argon2id(master_key, salt, time_cost=2, memory_cost=65536, parallelism=1, hash_len=32)`
- **Per-Block Nonce**: Counter incremented per block to ensure IV uniqueness across 1MB chunks:
  `nonce_block_i = base_nonce XOR int_to_bytes(block_index)`

### 3. Master Key Storage & Env Configuration
Master Key configurations are managed in `app.env`:
- `ENCRYPTION_MASTER_SALT`
- `ENCRYPTION_RECOVERY_KEY`
- `ENCRYPTION_WRAPPED_KEY`

### 4. UI Vault Unlock & FileDecryptModal
- **FileDecryptModal (`frontend/src/components/Modals.jsx`)**: Updated to decouple vault unlock (`encryptionApi.unlock` / `encryptionApi.unlockRecovery`) from post-unlock item actions. Prevents downstream streaming/network errors from falsely displaying "Incorrect password" toasts when the vault password (e.g. `1111`) is actually valid. Auto-detects Base64 recovery key inputs (>30 chars).
- **In-Memory Session Key Protection (`backend/encryption.py`)**: Fixed critical `set_session_key` bug where `get_session_key()` returning a mutable `bytearray` reference caused `clear_session_key()` during password changes / session updates to zero out the master key in-place (`b'\x00' * 32`), resulting in `AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` exported recovery keys and stream decryption failures (`InvalidTag`). `get_session_key()` now returns an immutable `bytes` copy.

## Authentication & Access Control (`backend/auth.py` & `backend/routers/auth_router.py`)
- **Single-User Auth Model**: Admin password authentication generating JWT access tokens.
- **Path Traversal Protection**: All file/folder operations sanitize input paths via `_sanitize_path` to prevent path traversal vulnerability vectors (`/../`).
- **Stream Authorization Tickets**: Audio streaming and track downloads generate short-lived signed authorization tickets (`?ticket=...`) allowing HTML5 `<audio>` tags and native Android players to stream media without risking JWT header exposure in query logs.

## Stream Ticket Auth Bypass — Fixed (2026-08-28)
**Уязвимость (OWASP A07, критическая)**: эндпоинты `GET /api/files/{file_id}/download` и `/stream` (`backend/routers/file_download.py`) позволяли скачивать файлы без аутентификации. Гейт `if not user and not ticket: 401` пропускал любой запрос с непустым `?ticket=`, а невалидный/протухший тикет не отклонялся — код молча продолжал стриминг с `file_password=None`. `file_id` — последовательный int, перебор тривиален; зашифрованные файлы отдавались расшифрованными, пока vault разблокирован на сервере (`EncryptionService.get_key(None)` → `get_session_key()`).

**Исправление**: валидация тикета перенесена к гейту аутентификации (начало `download_file`, до любых обращений к БД/Telegram). Инвариант доступа: `(валидная сессия) OR (тикет существует в stream_tickets И привязан к этому file_id)`. Без сессии: несуществующий/протухший тикет → `401`; тикет чужого файла → `403`; валидный тикет → доступ + пароль из тикета. Для аутентифицированных пользователей поведение не изменено (мусорный тикет → `file_password=None`, стрим через серверный session key). Эндпоинт `/stream` делегирует в `download_file` — покрыт автоматически.

**Регрессионные тесты**: `backend/tests/test_security.py`, класс `TestStreamTicketAuthBypass` (4 теста: без тикета / мусорный / протухший → 401, чужой файл → 403). Проверено: на старом коде 3 из 4 падают, на исправленном все проходят.

## Git History Purge (2026-08-28)
**Проблема**: `app.env` с реальными секретами (TG_SESSION_STRING, SESSION_SECRET, ENCRYPTION_*, APP_PASSWORD_HASH, DATABASE_URL) и три SQLite-БД (backend/vfs.db, tgvfs.db, app.db) находились в истории git (app.env удалён из отслеживания только в коммите cf8f9ef). Реальный пароль входа/vault также раскрывался в закоммиченных `frontend/tests/test_ui_flows.spec.js` и `security_audit/secrets_scan_100526.html`.

**Выполнено (git filter-repo --invert-paths)**: из всей истории удалены `app.env`, `backend/vfs.db`, `backend/tgvfs.db`, `backend/app.db`. Верифицировано: ни в одном рефе, ни на объектном уровне (`git rev-list --all --objects`) упоминаний нет; `app.env.example` сохранён. Все 5 веток force-pushed на origin (GitHub): final-refactoring 7471fda→cfb6de5 и др. Закрыт PR #1 («Update project files», старая история) и удалена его ветка v0/invalid49-9379-c0e88bed. Незакоммиченное состояние (36 файлов) пережило перезапись через WIP-commit + mixed reset.

**Остаточные риски**:
1. GitHub хранит unreachable-объекты старой истории до своей GC, и сервис-реф `refs/pull/1/head` (b07b9172) всё ещё указывает на старую историю — полная гарантия только через удаление и пересоздание репозитория или запрос в GitHub Support.
2. **Ротация секретов обязательна** — история считается скомпрометированной, пока TG_SESSION_STRING и ENCRYPTION_* не перегенерированы.
3. Backup-ремоут `gitsafe-backup` (`git://gitsafe:5418`, git-daemon без аутентификации/шифрования) на момент чистки недоступен (хост не резолвится) — старая история с секретами, вероятно, всё ещё на нём; при появлении хоста: перевести на SSH, force-push чистой истории (бэкап в `K:/Test/replit-history-backup-20260828.bundle`).
4. Bundle-бэкап содержит СТАРУЮ историю с секретами — удалить после завершения ротации.
