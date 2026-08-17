---
name: relink-skills
description: >-
  Re-link (junction) all of @jimb's personal skills into the Copilot CLI skills
  folder (~/.copilot/skills) by running Install-Skills.ps1. Self-healing: creates
  missing junctions, re-points stale ones, leaves real folders alone. Run after a
  git pull, on a new machine, or when a skill isn't loading.
  WHEN: "relink my skills", "re-link skills", "junction my skills", "reinstall my
  skills", "fix skill links", "my skills aren't loading", "link skills after pull",
  "install my skills on this machine", "ignore a skill on this computer",
  "home-only skill", "work-only skill".
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
- skill listed in the machine-local ignore file → skips it and removes its junction
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

## Ignore skills by computer class

Edit `C:\Files\Dev\main\copilot\settings\machine-overrides.json`. Add skill folder
names to `ignoredSkills` under `work` or `home`:

```json
{
  "work": {
    "model": "gpt-5.6-sol",
    "ignoredSkills": ["plex"]
  }
}
```

The installer uses the same `Get-MachineClass` rules as `copilot-settings`. The
next run removes existing junctions for excluded skills. Real folders are left
untouched.

For an exception on one specific computer, add names to
`%USERPROFILE%\.copilot\skills-ignore.txt`, one per line. Blank lines and lines
beginning with `#` are ignored. These local names are combined with the class list.

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
Compare `MISSING` names with the active class's `ignoredSkills`. Report any other
missing skill or `not a junction` warning so @jimb can resolve it.

## Notes
- This only links **skill folders**; it does not pull. Run `git pull` first if you
  want the latest skill content.
- If a target shows "exists and is not a junction", a real folder is shadowing the
  skill — inspect it, and only remove it if it holds no needed data.

## CLI settings

Junctioning skill folders is this skill's only job. Syncing `settings.json` and
`permissions-config.json` between @jimb's computers belongs to the **copilot-settings**
skill. The one fact this skill still owns: `Install-Skills.ps1` also calls
`tools\Sync-CopilotSettings.ps1 -Mode Apply -IfMissing -NoGit`, which seeds those files
on a new machine only when they're absent, and never touches the network.