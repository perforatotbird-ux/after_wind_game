---
date: 2026-07-27
description: "Added Bulk Delete functionality to Anti Detect Profiles in Pinteregger, allowing users to select multiple profiles via checkboxes and delete them alon"
tags:
  - project-note
source_repo: p-combine
---

# Add Bulk Delete to Anti Detect Profiles

Added Bulk Delete functionality to Anti Detect Profiles in Pinteregger, allowing users to select multiple profiles via checkboxes and delete them along with their stored session contexts and cookies.

## What changed

- backend/app/services/pinteregger_service.py - Added delete_profiles async method to BrowserProfileManager for safely stopping active profiles, removing them from profiles.json, and cleaning up profile storage directories.
- backend/app/api/pinteregger.py - Added /profiles/bulk-delete API endpoint accepting a list of profile IDs.
- frontend/src/services/api.ts - Added bulkDeleteProfiles API wrapper function.
- frontend/src/components/Pinteregger.tsx - Added 'Delete Selected' button in the Anti Detect Profiles Bulk Actions bar and handleBulkDeleteProfiles function with confirmation dialog.


## Decisions

- Implemented thread-safe bulk deletion on BrowserProfileManager so multiple selected profiles can be stopped and wiped from storage in a single atomic lock operation.


## Learned

- Bulk deletion of Playwright persistent contexts requires stopping any active instances before removing the user-data-dir folders on Windows to avoid file lock errors.


## Verification

Verified frontend compilation using npm run build (0 errors) and backend method execution via python CLI.




_Recorded 2026-07-27T13:10:14.537Z from `p-combine` via the om MCP server (routing: fallback)._
