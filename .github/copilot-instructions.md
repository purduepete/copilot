# Copilot instructions for the `copilot` repo

This repo holds **@purduepete's personal GitHub Copilot CLI skills** and the shared
global instructions. There is **no application to build** — it's PowerShell scripts and
Markdown that get consumed by the Copilot CLI. Do not add build/test/lint tooling;
none exists by design.

## Architecture: how skills reach the Copilot CLI

- Each skill is a folder `skills/<name>/` containing a `SKILL.md` (and optional
  helper `.ps1` scripts referenced by **absolute path**, e.g.
  `C:\Files\Dev\main\work-log\cli\wl.ps1`).
- Register this repository's skills root with Copilot CLI after cloning or when it is
  no longer available: `/skills add C:\Files\Dev\main\copilot\skills`.
- The CLI reads skills at startup, so tell the user to run `/restart` after any skill
  change for it to take effect.

## `SKILL.md` conventions (these are load-bearing)

Frontmatter is YAML between `---` fences:
```markdown
---
name: <name>                 # must match the folder name
description: >-
  <1–2 sentences on what it does> WHEN: "<trigger>", "<trigger>", "<trigger>".
argument-hint: <optional one-liner>
---
```
- The `WHEN:` trigger phrases inside `description` are what the CLI routes on — be
  generous and specific with phrasings.
- **Hard limit: `description` (whole block, WHEN: phrases included) must be ≤ 1024
  characters**, or the skill silently fails to load ("Skill description must be at
  most 1024 characters"). This bites when **merging** skills, since trigger phrases
  concatenate. Verify:
  ```powershell
  $raw = Get-Content skills\<name>\SKILL.md -Raw
  if ($raw -match "(?ms)^description:\s*>-\s*\r?\n(.*?)\r?\n[a-z-]+:\s") {
    "desc length: $((($matches[1] -replace '\s+',' ').Trim()).Length)  (must be <= 1024)"
  }
  ```
- Keep skills small and judgment-focused; reference scripts by absolute path rather
  than duplicating long logic in the Markdown body.

## Commits

Include the trailer on commits (matches repo history):
```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
