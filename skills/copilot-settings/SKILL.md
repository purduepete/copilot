---
name: copilot-settings
description: >-
  Save or update @jimb's Copilot CLI preference files (settings.json,
  permissions-config.json) across his 3 computers via canonical copies in the
  copilot repo, using tools\Sync-CopilotSettings.ps1. Save copies this machine's
  config into the repo and commits + pushes it; Apply runs git pull first then
  copies the repo's config onto this machine; Status only reports drift.
  WHEN: "save my config", "save my copilot settings", "save my config to the repo",
  "push my copilot settings", "update my config", "update my copilot settings",
  "pull my config from the repo", "get the latest copilot settings", "is my config
  in sync", "are my copilot settings in sync", "my settings are different on my
  other computer", "persist my copilot config across computers", "share copilot
  settings between my machines", "/copilot-settings".
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

- `settings.json` — model, theme, colorMode, showReasoning, beeps, timestamps
- `permissions-config.json` — per-location tool auto-approvals (`az`, `pwsh`, …)

`config.json` is **not** synced. The CLI owns it and its contents are machine-local
(`firstLaunchAt`, `recentModelIds`, `askedSetupTerminals`, `trustedFolders`).

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
- **The commit is scoped to the 2 settings files by path**, using `git add --` plus
  `git commit --only --`. Anything @jimb already staged elsewhere cannot ride along.
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
