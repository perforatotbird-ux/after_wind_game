---
date: 2026-07-27
description: "Integrated Make.com registration, activation, and authorization workflows into Pinteregger Anti Detect Profiles. Profiles can now register, activate, "
tags:
  - project-note
source_repo: p-combine
---

# Integrate Make.com Registration and Authorization into Anti-Detect Profiles

Integrated Make.com registration, activation, and authorization workflows into Pinteregger Anti Detect Profiles. Profiles can now register, activate, and authorize Make.com accounts in the same browser contexts as Pinterest accounts.

## What changed

- backend/app/models/schemas.py & frontend/src/types/index.ts - Added make_status, make_message, make_email, make_password fields to BrowserProfile schemas.
- backend/app/services/pinteregger_service.py - Added register_make_for_profile, authorize_make_for_profile, and bulk_register_make_for_profiles methods to BrowserProfileManager. Make.com registration and activation now run directly inside persistent Playwright anti-detect browser contexts.
- backend/app/api/pinteregger.py - Added REST endpoints /profiles/{id}/register-make, /profiles/{id}/authorize-make, and /profiles/bulk-register-make.
- frontend/src/services/api.ts - Added registerMakeProfile, authorizeMakeProfile, and bulkRegisterMakeProfiles methods.
- frontend/src/components/Pinteregger.tsx - Added Make Reg and Make Auth buttons for each profile, Make.com status badges in table view, and 'Register Make.com Selected' button in the Bulk Actions bar.


## Decisions

- Integrated Make.com account registration, onboarding activation, and dashboard authorization directly into Pinteregger Anti Detect Profiles. Both Pinterest and Make.com now share the exact same browser profile, proxy, and session cookies.


## Learned

- Running both Make.com and Pinterest account workflows within single persistent Playwright user-data-dir folders preserves Cloudflare clearance and login sessions cleanly for downstream posting automation.


## Verification

Verified backend method execution via Python script and compiled frontend with npm run build (0 errors).




_Recorded 2026-07-27T15:21:53.465Z from `p-combine` via the om MCP server (routing: fallback)._
