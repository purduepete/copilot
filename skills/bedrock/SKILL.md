---
name: bedrock
description: >-
  Work with the FDE_Revenue_Bedrock data-platform repo (C:\Files\Dev\msft\FDE_Revenue_Bedrock).
  Today it drives repo analysis — a fast inventory/structure report (folders, file
  types, skills & agents catalog, recent git activity) via Get-BedrockRepoInventory.ps1.
  Designed to grow toward Fabric lakehouse and Fabric semantic-model interactions.
  WHEN: "bedrock repo inventory", "analyze the bedrock repo", "what's in the bedrock
  repo", "bedrock repo structure", "bedrock skills and agents", "bedrock recent
  activity", "profile FDE_Revenue_Bedrock", "bedrock repo report", "work on bedrock".
argument-hint: optionally a repo path or "-Json"
---

# Bedrock

Helper skill for **@jimb's** work on the **FDE_Revenue_Bedrock** finance data
platform (Azure / Fabric, medallion architecture). Local clone:
`C:\Files\Dev\msft\FDE_Revenue_Bedrock`.

This skill starts focused on **repo analysis** and is built to expand toward
**Fabric lakehouse** and **Fabric semantic-model** interactions later. Keep new
capabilities as separate support scripts under this skill folder and document them
in the table below.

> The repo is **confidential** (see its `.github/copilot-instructions.md`): never
> surface connection strings, secrets/PATs, internal URLs/endpoints, or PII in
> output or examples.

## Capabilities

| Want to… | Run |
|---|---|
| Get a repo inventory / structure report | `Get-BedrockRepoInventory.ps1` (below) |
| Build the bronze source map / provisioning checklist | `Build-BronzeSourceMap.ps1` (below) |
| _Fabric lakehouse / semantic model_ | _planned — not yet implemented_ |

## Repo inventory / structure report

`Get-BedrockRepoInventory.ps1` profiles the local clone **without** cloning or
calling any remote service. It reports:

- **Folder layout** — each top-level folder with file + subfolder counts
  (`.github`, `docs`, `platform`, `shared`, `tenants`).
- **File-type breakdown** — counts by extension (`.git` excluded).
- **Skills catalog** — parsed from `.github/skills/*/SKILL.md` frontmatter
  (`name` + concise purpose, trigger lists trimmed).
- **Agents catalog** — parsed from `.github/agents/*.agent.md` frontmatter.
- **Recent git activity** — current branch + the last N commits.

```powershell
# Formatted report (default repo path)
pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Get-BedrockRepoInventory.ps1

# Machine-readable, for further reasoning
pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Get-BedrockRepoInventory.ps1 -Json

# Point at a different clone / more commits
pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Get-BedrockRepoInventory.ps1 -RepoPath D:\src\FDE_Revenue_Bedrock -Commits 20
```

**Parameters:** `-RepoPath` (default `C:\Files\Dev\msft\FDE_Revenue_Bedrock`),
`-Commits` (default `10`), `-Json` (emit one JSON object instead of text).

When the user asks about the repo, run the script first (use `-Json` to read it
yourself), then answer from the live report rather than guessing — the catalogs and
commit list change as the repo evolves.

## Bronze source map / provisioning checklist

`Build-BronzeSourceMap.ps1` distils every analysed solution's
`docs/exploratory/data-estate-analysis/solution/*/repo_inventory_io.csv` into one
**bronze provisioning picture** — the genuine upstream **external** inputs
(`type=input`, `external_internal=external`), rolled up to one row per **source
system** (the io `upstream` column):

- **Used by** — which solutions (arr / wcs / mwdetail / …) consume it.
- **Refs** — summed `dependency` weight (a sizing hint for what to onboard first).
- **Storage account(s)** — resolved from any `abfss://` path aliases (config-token
  paths are reported as *unresolved* — resolve them in the source repo first).
- **Bronze method** — `shortcut` (zero-copy OneLake shortcut, the default) vs
  `data copy (PME/elevated)` where shortcuts aren't permitted (account name contains
  `pme`/`spme`, or an elevated tenant like `msit-onelake`), vs `review` when it can't
  be auto-determined. **The PME/elevated flag is a heuristic — confirm it.**

```powershell
# Build CSV + visual HTML checklist and open it (writes to %TEMP%, never the repo)
pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Build-BronzeSourceMap.ps1

# Read the rolled-up systems yourself, no files
pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Build-BronzeSourceMap.ps1 -Json
```

**Parameters:** `-RepoPath` (default bedrock clone), `-OutDir` (default
`%TEMP%\bedrock-bronze-source-map` — kept out of the confidential repo), `-Json`,
`-NoOpen`. Outputs `bronze-source-map.html` (visual) + `bronze-source-map.csv`
(path-grain detail). Re-run as more solutions are analysed to refresh the picture.

## Repo conventions to honor

When editing inside FDE_Revenue_Bedrock, follow its `.github/copilot-instructions.md`:
Python 3.11+, **Ruff** (line-length 88), **pytest**, `click` for CLIs; new data
engineering as **PySpark notebooks** (Delta Lake, Bronze→Silver→Gold, Sangam
orchestration); branch names
`<author>/AB-<id>/<type>/<short-kebab-description>`; conventional commits linking
`AB#<id>`. That repo's **own** skills are instructions-only (`verb-noun`) with
runnable artefacts under `docs/exploratory/<name>/` — don't confuse them with this
personal CLI skill.

## Extending this skill

Add a new support script in this folder (e.g. a Fabric lakehouse query helper),
give it `-Json` output for agent consumption, add a row to **Capabilities**, then
commit to the copilot repo. No re-junction needed (scripts live inside the already
linked skill folder).
