---
name: copilot-settings
description: >-
  Save or update @jimb's Copilot CLI preference files (settings.json,
  permissions-config.json) across his 3 computers via canonical copies in the
  copilot repo, using tools\Sync-CopilotSettings.ps1. Save copies this machine's
  config into the repo and commits + pushes it; Apply runs git pull first then
  copies the repo's config onto this machine; Status only reports drift. `model`
  is a per-machine-class exception: work vs home can keep a different model.
  WHEN: "save my config", "save my copilot settings", "push my copilot settings",
  "update my config", "pull my config from the repo", "get the latest copilot
  settings", "is my config in sync", "my settings are different on my other
  computer", "persist my copilot config across computers", "share copilot
  settings between my machines", "set a different model for work vs home",
  "why is my model different on this computer", "/copilot-settings".
argument-hint: "[save|apply|status]"
---

# copilot-settings — one command per direction

The CLI's own preference files live in `%USERPROFILE%\.copilot`. They're machine-local
by default, so a change made on the laptop never reaches the Cloud PC. Canonical copies
live in the **copilot** repo at `C:\Files\Dev\main\copilot\settings\`, and
`tools\Sync-CopilotSettings.ps1` moves them in either direction.

They're **files**, so they're copied rather than junctioned. A single-file symlink on
Windows needs admin or Developer Mode, and junctioning all of `.copilot` would wrongly
share machine-local state like `session-store.db`.

## Word to mode

| @jimb says | Mode | What happens |
|---|---|---|
| save my config, push my copilot settings | `Save` | machine → repo, then commit and push |
| update my config, pull my config | `Apply` | `git pull` first, then repo → machine |
| is my config in sync | `Status` | reports drift, changes nothing, runs no git |

`/copilot-settings save` / `apply` / `status` map to the same 3 modes.

## Run it

```powershell
# This computer is right. Copy to the repo, commit, push.
pwsh -NoProfile -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Save

# This computer is behind. Pull, then copy onto this machine.
pwsh -NoProfile -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Apply

# Just tell me whether they differ.
pwsh -NoProfile -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1
```

After `Apply`, tell @jimb to run **`/restart`** so the CLI loads the new settings.

## What's synced

- `settings.json` — theme, colorMode, showReasoning, beeps, timestamps, and (with a
  per-machine-class exception, see below) `model`
- `permissions-config.json` — per-location tool auto-approvals (`az`, `pwsh`, …)

`config.json` is **not** synced. The CLI owns it and its contents are machine-local
(`firstLaunchAt`, `recentModelIds`, `askedSetupTerminals`, `trustedFolders`).

## Per-machine-class keys: `model` differs by work vs home

Everything in `settings.json` syncs identically everywhere **except** the keys listed
in the script's `$PerMachineKeys` array (today just `model`). Those are allowed to
hold a different value on work machines than on home machines, on purpose — @jimb runs
Claude Sonnet 5 at home and GPT-5.6 Sol at work.

**Machine classification** is by `$env:COMPUTERNAME` (`Get-MachineClass` in the
script):

| Class | Computers |
|---|---|
| `work` | `XFINJIMBLAPTOP`, `XFINJIMBHW`, `CPC-jimb-M4XXGV` (prefix `XFINJIMB*` / `CPC-jimb-*`) |
| `home` | `JIMBROWNLAPTOP`, `JIMBROWNHOME` (prefix `JIMBROWN*`) |

**Where it lives**: `copilot\settings\machine-overrides.json` — a repo-only file
(there's no copy of it on `%USERPROFILE%\.copilot`; the CLI doesn't read it, only the
settings sync and skill installer scripts read it):
```json
{
  "work": { "model": "gpt-5.6-sol", "ignoredSkills": [] },
  "home": { "model": "claude-sonnet-5", "ignoredSkills": [] }
}
```

`ignoredSkills` controls which skill junctions `Install-Skills.ps1` removes for
that machine class. The settings sync leaves this list unchanged.

**How it behaves:**

- **Invariant: the repo's `settings.json` never contains `model`.** It's stripped
  before every write to the repo, so the shared file only ever holds keys that are
  genuinely identical everywhere.
- **`Save`** copies `settings.json` machine → repo as usual, minus `model`. It also
  compares your live `model` to this machine class's stored override: if this is the
  first time that class/key combo has been seen, it's *seeded* from your current
  value (safe for an existing machine that already had its own model set); if an
  override already exists and differs, it's updated to your new value. Either way,
  `machine-overrides.json` rides along in the same commit as the other 2 files.
- **`Apply`** pulls the shared `settings.json`, then overlays this machine's class
  override onto `model` before writing the local file. **Fail-safe:** if this
  computer isn't in the classification table, or that class has no override yet,
  `Apply` leaves whatever `model` is already set locally untouched rather than
  guessing — it's never silently replaced by a repo default or the other class's
  value.
- **`Status`** reports `settings.json` drift ignoring `model` (so a legitimately
  different model is never flagged as "DIFFERS"), plus a dedicated line per
  per-machine key, e.g. `= model (home): claude-sonnet-5 (matches override)` or
  `? model : machine class not recognized for <name> — add this COMPUTERNAME to
  Get-MachineClass`.

**Adding another per-machine key later** (e.g. `theme`): add it to
`$PerMachineKeys` in `Sync-CopilotSettings.ps1` and add an entry for it under both
classes in `machine-overrides.json` (or let the first `Save` from each class seed it).

## Save and Apply, never Pull and Push

"Push my config" reads as machine → repo to a human but repo → machine by git analogy.
Guessing wrong overwrites good settings with stale ones. `Pull` and `Push` are rejected
by the `ValidateSet` with an error listing the valid modes.

## Safety

The script is built to never lose a good config:

- **`Save` fetches and compares to upstream before writing anything.** If the branch is
  behind or diverged it aborts and tells you to run `Apply` first, so a stale machine
  can't publish over a newer canonical copy.
- **`Apply` aborts if the pull fails**, before any file is written. Diverged, dirty
  tree, no upstream, offline and auth failure each get their own message.
- **The commit is scoped to the settings files by path** (`settings.json`,
  `permissions-config.json`, and `machine-overrides.json` when it changed), using
  `git add --` plus `git commit --only --`. Anything @jimb already staged elsewhere
  cannot ride along.
- **A rejected push is a clean stop**, never an auto-rebase. The commit stays local and
  recovery steps are printed.
- Refuses on detached HEAD or a mid-merge / mid-rebase / mid-cherry-pick tree, detected
  with `git rev-parse --git-path` so it's correct inside a git worktree too.
- Refuses to copy a file that isn't valid JSON.
- Every machine-side overwrite writes a timestamped `.bak-` copy first. The repo side
  gets no `.bak-` file, because git history is the backup.

Verified by a 41-assertion sandbox matrix over throwaway repos with a bare origin.

## Gotchas

- **`Apply` pulls the whole repo checkout**, not just `settings\`. Unrelated dirty work
  in the copilot repo will make the pull fail, and then nothing is written.
- **`-NoGit` means "run no git commands", not "read-only".** `Apply -NoGit` still
  overwrites local files. "Just look" is `Status`.
- `Install-Skills.ps1` calls `-Mode Apply -IfMissing -NoGit`, so onboarding a machine
  seeds settings only when absent, never clobbers local preferences, and never touches
  the network.
- Junctioning skill folders is a different job. That's `relink-skills`.
