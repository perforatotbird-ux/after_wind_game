---
date: 2026-08-18
description: "Identified the exact Netlify accounts, workspaces, and Site IDs where the 5 landing pages from the 'Halloween Crafts' profile group are deployed."
tags:
  - project-note
source_repo: p-combine
---

# Netlify Accounts Deployment Mapping for Halloween Crafts Profiles

Identified the exact Netlify accounts, workspaces, and Site IDs where the 5 landing pages from the 'Halloween Crafts' profile group are deployed.

## What changed

- Mapped 5 Halloween Crafts profiles to their respective Netlify deployments and accounts via Netlify API.


## Decisions

- Identified Netlify accounts: clocworkmail@gmail.com (3 sites: spookycraftspro, littlemonsterscrafts, spookycreationshub), techsupp.ray@outlook.com (1 site: littlemonsterscraftscjhc), chi89293duong@gmail.com (1 site: hauntedhavendecor).


## Learned

- Halloween Crafts sites are spread across 3 specific Netlify accounts rather than a single workspace.


## Verification

Direct API queries to https://api.netlify.com/api/v1/sites and /api/v1/user using stored authentication tokens.




_Recorded 2026-08-18T10:20:07.479Z from `p-combine` via the om MCP server (routing: fallback)._
