---
date: 2026-07-27
description: "Added full credential mapping from Credential Generator to Anti Detect Profiles in Pinteregger, storing login, password, account_name, board_name, pro"
tags:
  - project-note
source_repo: p-combine
---

# Map Credential Generator Fields to Anti Detect Profiles

Added full credential mapping from Credential Generator to Anti Detect Profiles in Pinteregger, storing login, password, account_name, board_name, prokladka, make_api_key, description, pinterest_url, and hook_url (excluding avatar_prompt) in profile settings.

## What changed

- backend/app/models/schemas.py - Extended BrowserProfileSchema and BrowserProfileUpdateSchema with credential fields: login, password, account_name, board_name, prokladka, make_api_key, description, pinterest_url, hook_url.
- backend/app/services/pinteregger_service.py & backend/app/api/pinteregger.py - Updated update_profile service method and REST endpoint to accept and save all credential fields into profiles.json.
- frontend/src/types/index.ts & frontend/src/services/api.ts - Updated BrowserProfile interface and updateProfile API method to accept credential fields object.
- frontend/src/components/utilities/CredentialGenerator.tsx - Updated handleSendToPinteregger to parse generated credential lines (login:password, account_name, description, board_name, make_api_key, hook_url, pinterest_url, prokladka, excluding avatar_prompt per user request) and save them directly into the newly created Anti-Detect profiles.
- frontend/src/components/Pinteregger.tsx - Added Account Credentials Settings section to Edit Profile modal and rendered credential badges (login, board, prokladka) under profile name in the table view.


## Decisions

- Excluded avatar_prompt field when mapping generated credentials to Anti-Detect profiles per explicit user directive.
- Maintained backwards compatibility in api.updateProfile so it can accept either an object payload or positional parameters.


## Learned

- Grouping all account parameters directly on Anti-Detect profiles allows operators to inspect and manage logins, board names, Netlify landing pages, and Make.com API keys right within the Anti-Detect Profiles UI without switching tabs.


## Verification

Verified profile update via Python CLI script, and built frontend with npm run build (0 errors).




_Recorded 2026-07-27T14:17:41.605Z from `p-combine` via the om MCP server (routing: fallback)._
