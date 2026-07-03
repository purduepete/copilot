---
name: webportfolio-update-deps
description: >-
  Update (or just report on) every library in @jimb's webportfolio monorepo in one
  pass — all 3 npm packages (root, frontend, backend) plus both Python requirements
  (stock_price, azure-functions/price-updater) — via
  scripts\update-dependencies.ps1. Modes: Report (default, non-destructive), Safe
  (within semver ranges / pins), Latest (bump to newest incl. majors). Report first,
  flag breaking majors, and remember webportfolio requires a GitHub issue + smoke
  tests before committing. WHEN: "update webportfolio libraries", "update all
  libraries", "update dependencies", "update the npm packages", "update python
  requirements", "what packages are outdated", "check for outdated dependencies",
  "bump webportfolio dependencies", "upgrade libraries", "are my dependencies up to
  date", "update packages under webportfolio".
argument-hint: optional "-Mode Report|Safe|Latest" and/or "-Ecosystem All|Npm|Python"
---

# WebPortfolio — update dependencies

Wraps the repo tool **`C:\Files\Dev\main\webportfolio\scripts\update-dependencies.ps1`**,
which updates or reports on **every** library in the webportfolio monorepo in a single
run. Local clone: `C:\Files\Dev\main\webportfolio`.

Covered manifests (all of them, in one pass):

| Ecosystem | Target | Manifest |
|---|---|---|
| npm | root | `package.json` |
| npm | frontend | `frontend\package.json` |
| npm | backend | `backend\package.json` |
| python | stock_price | `stock_price\requirements.txt` |
| python | price-updater (func) | `azure-functions\price-updater\requirements.txt` |

## Modes

| `-Mode` | npm | python | Writes? |
|---|---|---|---|
| **Report** (default) | `npm-check-updates` (list outdated) | query PyPI, list outdated pins | **No — safe any time** |
| **Safe** | `npm update` (honours `^`/`~` ranges) | `pip install -U -r` (honours `==` pins) | installs; may touch lockfiles |
| **Latest** | `ncu -u` + `npm install` (newest, incl. majors) | rewrite `requirements.txt` to newest PyPI pins | **edits manifests** |

Optional `-Ecosystem All|Npm|Python` narrows scope (default `All`).

## Run it

```powershell
# Report only — nothing changes (default). Best first step; read it back to the user.
pwsh -File C:\Files\Dev\main\webportfolio\scripts\update-dependencies.ps1

# Safe updates within existing ranges / pins
pwsh -File C:\Files\Dev\main\webportfolio\scripts\update-dependencies.ps1 -Mode Safe

# Latest — bumps to newest incl. majors (edits package.json / requirements.txt)
pwsh -File C:\Files\Dev\main\webportfolio\scripts\update-dependencies.ps1 -Mode Latest

# Narrow to one ecosystem
pwsh -File C:\Files\Dev\main\webportfolio\scripts\update-dependencies.ps1 -Mode Report -Ecosystem Python
```

The script prints a per-target **Summary** table at the end.

## How to use in a conversation

1. **Always run `-Mode Report` first** and summarise what's outdated — call out any
   **major** version jumps (e.g. React 18→19, Vite 4→8, Tailwind 3→4, Express 4→5,
   TypeScript 5→6), which carry breaking changes.
2. **Recommend `-Mode Safe`** for routine maintenance (stays inside declared ranges).
   Reserve **`-Mode Latest`** for a deliberate, issue-tracked upgrade — never as a
   surprise, since it rewrites manifests and pulls breaking majors.
3. **Respect the webportfolio workflow** (`.github/copilot-instructions.md`): work is
   tracked by a **GitHub issue** — confirm/create one before making changes. After any
   `Safe`/`Latest` run, validate before committing:
   ```powershell
   cd C:\Files\Dev\main\webportfolio
   git diff
   .\scripts\run-smoke-tests.ps1 -EnvironmentName azure-dev
   ```
   Commit referencing the issue (`Fix #<n>: …`) with the `Co-authored-by: Copilot`
   trailer. Do **not** commit or deploy without the user's OK.

> **Note:** the `update-dependencies.ps1` tool lives in the **webportfolio** repo (not
> this skill folder), so it ships and versions with that repo. This skill just knows how
> to drive it and the judgment around when each mode is appropriate.
