---
date: 2026-07-27
description: "Added support for importing TXT anti-detect profile exports (like export_profile.txt) into Pinteregger Anti Detect Profiles with automatic hardware fi"
tags:
  - project-note
source_repo: p-combine
---

# Import TXT Anti-Detect Profiles Support

Added support for importing TXT anti-detect profile exports (like export_profile.txt) into Pinteregger Anti Detect Profiles with automatic hardware fingerprint generation, custom proxy extraction, and full session cookie injection.

## What changed

- backend/app/services/pinteregger_service.py - Added import_profiles_txt method to BrowserProfileManager to parse TXT exported profile files (like export_profile.txt), extracting profile name, group, user agent, proxy info, and cookie JSON arrays into separate cookies.json profile files.
- backend/app/core/browser_factory.py - Added automatic injection of stored cookies.json files into Chrome browser contexts upon launching persistent profiles.
- backend/app/api/pinteregger.py - Updated /profiles/import endpoint to auto-detect .txt files and delegate parsing to import_profiles_txt.
- frontend/src/components/Pinteregger.tsx - Updated file import dialog to accept both .zip and .txt profile export files.


## Decisions

- Supported TXT anti-detect profile exports with automatic generation of synthetic hardware fingerprints (canvas noise, WebGL renderer, hardware concurrency, device memory) while preserving original User-Agent, group, and cookie session tokens.
- Cookies are written to storage/profiles/{id}/cookies.json and injected dynamically via Playwright context.add_cookies upon launch, allowing session state restoration even if proxy IP address changes.


## Learned

- AdsPower and Undetectable TXT export formats break profile definitions into block sections separated by blank lines with key=value attributes. Cookies are provided as raw JSON arrays with expiry timestamps and domains intact.


## Verification

Verified parsing of export_profile.txt via python script (5 profiles successfully created with cookies saved), and compiled frontend using npm run build with 0 errors.




_Recorded 2026-07-27T13:22:55.170Z from `p-combine` via the om MCP server (routing: fallback)._
