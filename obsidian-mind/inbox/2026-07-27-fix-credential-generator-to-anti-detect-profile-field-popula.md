---
date: 2026-07-27
description: "Fixed profile credentials update error when transferring generated account data from Credential Generator to Anti Detect Profiles."
tags:
  - project-note
source_repo: p-combine
---

# Fix Credential Generator to Anti Detect Profile Field Population Error

Fixed profile credentials update error when transferring generated account data from Credential Generator to Anti Detect Profiles.

## What changed

- backend/app/services/pinteregger_service.py - Added missing make_status, make_message, make_email, make_password keyword parameters to BrowserProfileManager.update_profile method signature.
- frontend/src/components/utilities/CredentialGenerator.tsx - Added detailed addLog error notification inside catch block when updating profile credentials fails.


## Decisions

- Aligned BrowserProfileManager.update_profile method parameters in pinteregger_service.py with BrowserProfileUpdateSchema in schemas.py so FastAPI PUT requests with full credential payloads execute without TypeError exception.


## Learned

- When FastAPI automatically parses a Pydantic schema model_dump() and passes kwargs to a service method, all schema fields must be accepted by the target method signature to prevent unexpected keyword argument errors.


## Verification

Verified profile creation and full credential update end-to-end via Python CLI script, and built frontend with npm run build (0 errors).




_Recorded 2026-07-27T16:00:07.427Z from `p-combine` via the om MCP server (routing: fallback)._
