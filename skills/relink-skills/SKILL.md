---
name: relink-skills
description: >-
  Re-link (junction) all of @jimb's personal skills into both skill folders —
  Copilot CLI (~/.copilot/skills) and Claude Code (C:\Files\Dev\.claude\skills) —
  by running Install-Skills.ps1. Self-healing: creates missing junctions, re-points
  stale ones, leaves real folders alone. Run after a git pull, on a new machine, or
  when a skill isn't loading. WHEN: "relink my skills", "re-link skills", "junction
  my skills", "reinstall my skills", "fix skill links", "my skills aren't loading",
  "link skills after pull", "install my skills on this machine".
argument-hint: (none)
---

# relink-skills — re-junction personal skills

@jimb's skills live in the **copilot** repo at
`C:\Files\Dev\main\copilot\skills\<name>\SKILL.md` and are surfaced to the tools
via **directory junctions** into two targets:

- **Copilot CLI:** `%USERPROFILE%\.copilot\skills`
- **Claude Code:** `C:\Files\Dev\.claude\skills`

`Install-Skills.ps1` creates/repairs those junctions. It is **self-healing**:
- missing link  → creates the junction (`+ Linked …`)
- junction pointing at a stale/old target → re-points it (`~ Re-linked …`)
- already correct → leaves it (`= … already linked`)
- a **real folder** (not a junction) with that name → **skipped with a warning**
  (won't clobber real data; remove it manually to let the junction take over)

## When to run
- After `git pull` in the copilot repo (new or renamed skills).
- On a freshly-cloned machine (one of @jimb's 3 computers).
- When a skill isn't being picked up by Copilot CLI or Claude Code.

## Run it
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
```
Junctions need no admin rights. Re-running is always safe (idempotent).

## Verify both targets
```powershell
$repo = 'C:\Files\Dev\main\copilot\skills'
$names = (Get-ChildItem $repo -Directory).Name
foreach ($t in @("$env:USERPROFILE\.copilot\skills", 'C:\Files\Dev\.claude\skills')) {
  "=== $t ==="
  foreach ($n in $names) {
    $link = Join-Path $t $n
    $ok = (Test-Path $link) -and ((Get-Item $link -Force).LinkType -eq 'Junction')
    "{0} {1}" -f $(if($ok){'OK '}else{'MISSING'}), $n
  }
}
```
Report any `MISSING` or any `not a junction` warning so @jimb can resolve it.

## Notes
- This only links **skill folders**; it does not pull. Run `git pull` first if you
  want the latest skill content.
- If a target shows "exists and is not a junction", a real folder is shadowing the
  skill — inspect it, and only remove it if it holds no needed data.
