---
date: 2026-07-27
description: "Implemented saving of generated credentials history to a JSON file on successful generation in Credential Generator. Added selection of these history "
tags:
  - project-note
source_repo: p-combine
---

# Add credential generation history to Credential Generator and integration with Site Creator

Implemented saving of generated credentials history to a JSON file on successful generation in Credential Generator. Added selection of these history entries in Site Creator to easily load past credentials as input data.

## What changed

- backend/app/services/credential_generator_service.py - Added CredentialHistoryManager to load, save, append and delete credential generation history items
- backend/app/api/utilities.py - Integrated CredentialHistoryManager into credentials_generate to save successful generations, and added GET/DELETE history endpoints
- frontend/src/components/utilities/SiteCreator.tsx - Added history states, fetch/delete handlers, and UI select dropdown to select and load credential history entries


## Decisions

- Decided to use a simple JSON file (credential_history.json) in settings.storage_dir to persist history rather than DB migrations, matching how settings and profiles are managed.
- Decided to populate the text input area when selecting a history item in Site Creator, allowing operators to easily inspect, modify, and confirm before deploying.



## Verification

Ran npm run build to compile the frontend application.




_Recorded 2026-07-27T11:11:25.258Z from `p-combine` via the om MCP server (routing: fallback)._
