# Copilot instructions for the `copilot` repo

This repo holds **@purduepete's personal GitHub Copilot CLI skills**, plus the
**Copilot Reference Hub** (`instructions.html`) and two work-item dashboard
generators. There is **no application to build** — it's PowerShell scripts and
Markdown that get consumed by the Copilot CLI. Do not add build/test/lint tooling;
none exists by design.

## Architecture: how skills reach the Copilot CLI

- Each skill is a folder `skills/<name>/` containing a `SKILL.md` (and optional
  helper `.ps1` scripts referenced by **absolute path**, e.g.
  `C:\Files\Dev\main\worklog_web\cli\wl.ps1`).
- The Copilot CLI loads skills from `%USERPROFILE%\.copilot\skills`. Skills are **not
  copied** there — `skills/Install-Skills.ps1` creates a directory **junction** per
  skill folder so repo edits are picked up live. It is idempotent and self-healing:
  it links new folders, re-points stale junctions, and leaves real (non-junction)
  folders untouched. Run it after cloning on a new machine, after a `git pull`, or
  when a skill isn't loading:
  ```powershell
  pwsh -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
  ```
- `Install-Skills.ps1` also links skills from `$ExtraSkillRepos` (e.g. the confidential
  `bedrock_analysis\skills`) **only if that path exists** locally — so a
  machine without that repo simply skips it.
- `settings\machine-overrides.json` can exclude skill names for the shared `work`
  and `home` computer classes. A machine can add one-off exclusions through
  `%USERPROFILE%\.copilot\skills-ignore.txt`. The installer skips those skills and
  removes existing junctions while leaving real folders untouched.
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

## The Reference Hub must stay in sync

`instructions.html` is a self-contained HTML doc (the "Copilot Reference Hub") with a
**"My skills" catalog table** at `<h4 id="sk-catalog">`, `<table class="skills">`.

- **Whenever you add or remove a skill, add/remove its catalog row.** The table is
  sorted **alphabetically by skill name**; insert new rows in the correct position, do
  not append. Skill name goes in `<td><code>…</code></td>` (the `class="skills"` CSS
  keeps the first column from wrapping).
- Validate the HTML before committing — tags must balance and every nav `href="#id"`
  must resolve:
  ```powershell
  $h = Get-Content instructions.html -Raw
  "table: $(([regex]::Matches($h,'<table')).Count)/$(([regex]::Matches($h,'</table>')).Count)  tr: $(([regex]::Matches($h,'<tr>')).Count)/$(([regex]::Matches($h,'</tr>')).Count)"
  ```
- The end-to-end workflow for creating/removing a skill (scaffold → junction → commit
  → store memory → **update the hub catalog** → tell user to `/restart`) lives in the
  **`skill-authoring`** skill. Follow it; updating the hub is a required step.

## Dashboards

- `Rebuild-OpenWorkItems.ps1` → `open-work-items.html` (ADO work items assigned to @Me
  in org StarlightAgileBI; auth via the Git Credential Manager bearer token — never
  print it).
- `Rebuild-OpenGitHubItems.ps1` → `open-github-items.html` (open GitHub issues via the
  `gh` CLI; owner `purduepete` by default).
- Both **output HTML files are git-ignored** — they're regenerated on demand (by the
  `worklist` skill). The two dashboards intentionally share look/feel; change both
  generators together.

## Commits

Include the trailer on commits (matches repo history):
```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
