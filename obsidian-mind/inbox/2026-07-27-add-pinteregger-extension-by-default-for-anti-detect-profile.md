---
date: 2026-07-27
description: "Configured default installation of Pinteregger Chrome extension from storage/extensions/pinteregger/ for all Pinteregger Anti Detect profiles."
tags:
  - project-note
source_repo: p-combine
---

# Add Pinteregger Extension by default for Anti Detect Profiles

Configured default installation of Pinteregger Chrome extension from storage/extensions/pinteregger/ for all Pinteregger Anti Detect profiles.

## What changed

- backend/app/core/browser_factory.py - Added automatic detection and loading of Pinteregger Chrome extension from storage/extensions/pinteregger/ for all Pinteregger anti-detect profiles launched via launch_system_chrome and launch_persistent_profile.


## Decisions

- Added extension loading logic dynamically based on storage_dir / 'extensions' / 'pinteregger' / 'manifest.json' so any profile automatically receives the unpacked extension upon launch without mutating existing fingerprint or profile creation options.


## Learned

- Chrome unpacked extensions passed to Playwright persistent contexts require proper forward slash path normalization and combining via comma-separated --load-extension and --disable-extensions-except flags.


## Verification

Verified extension path resolution via Python CLI script (Path: K:\Test\P-Combine\backend\app\storage\extensions\pinteregger, Manifest exists: True).




_Recorded 2026-07-27T13:04:36.104Z from `p-combine` via the om MCP server (routing: fallback)._
