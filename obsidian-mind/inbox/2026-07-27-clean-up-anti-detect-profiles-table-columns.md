---
date: 2026-07-27
description: "Updated Anti-Detect Profiles table to show only Name, Status, Proxy, Fingerprint, Created At, and Actions columns."
tags:
  - project-note
source_repo: p-combine
---

# Clean Up Anti-Detect Profiles Table Columns

Updated Anti-Detect Profiles table to show only Name, Status, Proxy, Fingerprint, Created At, and Actions columns.

## What changed

- frontend/src/components/Pinteregger.tsx - Updated profile table header and cell rendering to display strictly the requested columns: Name, Status, Proxy, Fingerprint, Created At, Actions.


## Decisions

- Cleaned up the Anti-Detect Profiles table layout per user request to maintain a streamlined view showing only Name, Status, Proxy, Fingerprint, Created At, and Actions.


## Learned

- Keeping table columns strictly aligned with operator preferences provides a cleaner UI for bulk account management.


## Verification

Built frontend using npm run build with 0 compilation errors (exit code 0).




_Recorded 2026-07-27T16:05:51.419Z from `p-combine` via the om MCP server (routing: fallback)._
