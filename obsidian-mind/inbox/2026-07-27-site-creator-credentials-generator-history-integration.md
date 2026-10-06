---
date: 2026-07-27
description: "Integrated Credential Generator history with Site Creator to auto-populate site URLs from Account Names, added custom template folder directory path a"
tags:
  - project-note
source_repo: p-combine
---

# Site Creator & Credentials Generator History Integration

Integrated Credential Generator history with Site Creator to auto-populate site URLs from Account Names, added custom template folder directory path and Randomize Templates checkbox, and automatically write deployed site URLs into the PROKLADKA column of Credential Generator history. Also added history loading dropdown to Credential Generator so users can inspect, export, and transfer history items to PinPoster, Pinteregger, etc.

## What changed

- backend/app/services/site_creator_service.py - Updated SiteCreator, TemplateManager, and ExcelSiteManager to support custom template directory, randomize templates checkbox, Netlify site subdomain slugification with Russian transliteration, and writing site URLs into PROKLADKA column of Credential Generator history.
- backend/app/services/credential_generator_service.py - Added update_entry_lines to CredentialHistoryManager for persisting updated PROKLADKA lines.
- backend/app/api/utilities.py - Updated /sites/templates and /sites/deploy endpoints to accept template_dir, randomize_templates, and history_id.
- frontend/src/components/utilities/SiteCreator.tsx - Added History dropdown, Template Directory input, Randomize Templates checkbox, and Deployed Sites list UI with clickable Netlify links.
- frontend/src/components/utilities/CredentialGenerator.tsx - Added History selection dropdown, allowing users to load previous generations, export to TXT/Excel, copy, and send to PinPoster or Pinteregger.


## Decisions

- Standardized site subdomain slugification across frontend and backend using Russian transliteration so site names generated from Account Names are clean DNS-compliant subdomains.
- Lazy-loaded NetlifyAPI in SiteCreator to avoid throwing configuration errors on initialization when Netlify tokens are not configured yet.


## Learned

- CredentialGenerationDB.lines stores JSON array of pipe-separated credential lines where index 7 is PROKLADKA / Link. Updating index 7 in history entries makes it automatically appear in Excel exports under column 9 ('Link').


## Verification

Created and executed unit test suite test_site_creator.py covering transliteration, site extraction, database, template manager, excel site manager, async deployment, and history PROKLADKA updates (all passed). Tested frontend build using npm run build with 0 errors.




_Recorded 2026-07-27T12:52:20.030Z from `p-combine` via the om MCP server (routing: fallback)._
