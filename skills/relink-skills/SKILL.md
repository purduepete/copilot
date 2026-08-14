---
name: relink-skills
description: >-
  Re-link (junction) all of @jimb's personal skills into the Copilot CLI skills
  folder (~/.copilot/skills) by running Install-Skills.ps1, and sync the CLI's own
  settings.json / permissions-config.json across his computers via
  Sync-CopilotSettings.ps1 (Status/Save/Apply). Self-healing: creates missing
  junctions, re-points stale ones, leaves real folders alone. Run after a git pull,
  on a new machine, or when a skill isn't loading. WHEN: "relink my skills",
  "re-link skills", "junction my skills", "reinstall my skills", "fix skill links",
  "my skills aren't loading", "link skills after pull", "install my skills on this
  machine", "sync my copilot settings", "persist my config across computers",
  "share settings between my machines", "my settings are different on my other
  computer", "save my config changes", "set up copilot on a new machine".
argument-hint: (none)
---

# relink-skills — re-junction personal skills

@jimb's skills live in the **copilot** repo at
`C:\Files\Dev\main\copilot\skills\<name>\SKILL.md` and are surfaced to the
Copilot CLI via a **directory junction** for each skill into:

- **Copilot CLI:** `%USERPROFILE%\.copilot\skills`

`Install-Skills.ps1` creates/repairs those junctions. It is **self-healing**:
- missing link  → creates the junction (`+ Linked …`)
- junction pointing at a stale/old target → re-points it (`~ Re-linked …`)
- already correct → leaves it (`= … already linked`)
- a **real folder** (not a junction) with that name → **skipped with a warning**
  (won't clobber real data; remove it manually to let the junction take over)

## When to run
- After `git pull` in the copilot repo (new or renamed skills).
- On a freshly-cloned machine (one of @jimb's 3 computers).
- When a skill isn't being picked up by Copilot CLI.

## Run it
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
```
Junctions need no admin rights. Re-running is always safe (idempotent).

## Verify
```powershell
$repo = 'C:\Files\Dev\main\copilot\skills'
$names = (Get-ChildItem $repo -Directory).Name
$t = "$env:USERPROFILE\.copilot\skills"
"=== $t ==="
foreach ($n in $names) {
  $link = Join-Path $t $n
  $ok = (Test-Path $link) -and ((Get-Item $link -Force).LinkType -eq 'Junction')
  "{0} {1}" -f $(if($ok){'OK '}else{'MISSING'}), $n
}
```
Report any `MISSING` or any `not a junction` warning so @jimb can resolve it.

## Notes
- This only links **skill folders**; it does not pull. Run `git pull` first if you
  want the latest skill content.
- If a target shows "exists and is not a junction", a real folder is shadowing the
  skill — inspect it, and only remove it if it holds no needed data.

## CLI settings (settings.json, permissions-config.json)

`Install-Skills.ps1` also syncs the CLI's own preference files by calling
`tools\Sync-CopilotSettings.ps1`. These are **files**, so they are copied, not
junctioned (a single-file symlink on Windows needs admin or Developer Mode).
Canonical copies live in `C:\Files\Dev\main\copilot\settings\`:

- `settings.json` — model, theme, colorMode, showReasoning, beeps, timestamps
- `permissions-config.json` — per-location tool auto-approvals (`az`, `pwsh`, …)

`config.json` is **not** synced. The CLI manages it and its contents are
machine-local (`firstLaunchAt`, `recentModelIds`, `askedSetupTerminals`).

After changing settings on one computer (`/settings` or hand-editing):
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Save
```
Then commit and push. On another computer, `git pull` and:
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Apply
```
Then `/restart` to load them. With no `-Mode`, the script only reports drift and
changes nothing. Every overwrite writes a timestamped `.bak-` backup first, and the
script refuses to copy a file that isn't valid JSON.

The modes are **Save** (this computer is right) and **Apply** (this computer is
behind), never Pull/Push. "Push my config" reads as machine → repo to a human but
repo → machine by git analogy, and guessing wrong overwrites good settings with
stale ones. `Pull` and `Push` are rejected with an error listing the valid modes.

Inside `Install-Skills.ps1` the apply runs with `-IfMissing`, so onboarding a machine
seeds settings only when absent and never clobbers local preferences.
