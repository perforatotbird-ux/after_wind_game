---
type: security-remediation
project: t-music
status: done
date: 2026-09-11
tags:
  - security
  - owasp
  - tmusic
---

# T-Music — OWASP remediation

Проект: `K:\Test\tmusic`  
Ревью: OWASP Top 10, internet-facing music streamer.

## Решения

- **Ключи не ротируем** — только `.gitignore`.
- **Пункт 9 (rate limit wiring) — пропущен.**

## Внедрено

| # | Находка | Файлы |
|---|---------|-------|
| 1 | `.gitignore` | `K:\Test\tmusic\.gitignore` |
| 2 | CORS без `*` | `config.py` — explicit localhost origins |
| 3 | SSRF redirect | `cover_cache_service.py` — `_fetch_safe`, `allow_redirects=False` |
| 4 | JWT TTL 12h + revoke | `config.py`, `token_store.py`, `dependencies.py`, `auth_router.py` |
| 5 | Cookie auth, без localStorage | `auth_router.py` (`COOKIE_SECURE`), `client.js`, `authStore.js`, `stream.js` |
| 6 | Trusted proxy IP | `auth_router.py` + `TRUST_PROXY_HEADERS` |
| 7 | PIN → bcrypt | `security.py` + legacy upgrade in `auth_service.py` |
| — | Stream 503 без detail | `stream_service.py` |

## Проверка

- `compileall` OK, imports OK
- `test_security.py` 4 passed
- smoke: bcrypt PIN, JWT revoke (sqlite)

## Отложено

- [ ] Пункт 9: `limiter.is_rate_limited` на login/pin/cover/stream
- [ ] Ротация ключей
- [ ] CSP: убрать `unsafe-inline`
- [ ] Auth на `GET /cover?url=`
- [ ] python-jose → PyJWT
- [ ] Audit log / metrics

## Env (для прода)

```
COOKIE_SECURE=true
TRUST_PROXY_HEADERS=true   # только за доверенным reverse proxy
ALLOWED_ORIGINS=["https://music.example.com"]
ACCESS_TOKEN_EXPIRE_MINUTES=720
```
