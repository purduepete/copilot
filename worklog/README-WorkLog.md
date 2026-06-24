# Work Tracking Framework

A conversational, time-tracked work log. Designed to be driven through Copilot:
you say when you **start** work and what it is, when you **switch**, and when you
**stop** (with what you accomplished). It records timestamped sessions and rolls
them up into a **daily standup**, **weekly summary**, and an **interactive calendar
dashboard** — as HTML (to view) and Markdown (to paste into Teams / email / ADO).

The tool is **portable** (paths resolve from its own folder, so it runs wherever the
repo is cloned) and **profile-aware** — keep separate logs per context, e.g. `work`
and `personal`, that never mix.

## Files

| File | Purpose |
| --- | --- |
| `WorkLog.psm1` | Core module (all logic + report generators) |
| `Work.ps1` | Thin CLI wrapper (verbs) |
| `Edit-Dashboard.ps1` | Start/stop the live-edit dashboard server (`start` \| `stop` \| `status` \| `restart`) |
| `Get-VSCodeWork.ps1` | Parse VS Code Copilot chat transcripts into work blocks (exact times + commits) |
| `vscode\` | VS Code integration template (`tasks.json`, `keybindings.jsonc`, `README.md`) |
| `worklog.config.json` | Profiles + per-profile settings (e.g. ADO org) |
| `.profile` | This machine's default profile (git-ignored, not synced) |
| `data\<profile>\work-log.json` | Persistent state (the log) for that profile |
| `data\<profile>\work-dashboard.html` | Interactive calendar dashboard (with live search box) |
| `data\<profile>\standup.{html,md}` | Latest daily standup |
| `data\<profile>\weekly-summary.{html,md}` | Latest weekly summary |

## Profiles (work vs personal)

Each profile has its own log + reports under `data\<profile>\`, and its own settings
in `worklog.config.json` (the `work` profile links ADO items; `personal` has no org).

Profile resolution order: `-Profile <name>` on any command → `WORKLOG_PROFILE` env var
→ the `.profile` file in this folder → `defaultProfile` in `worklog.config.json` → `work`.

### Switching between work and personal

There are three ways to switch, from most temporary to most permanent. Pick whichever fits:

```powershell
# 0. Which profile am I on right now?  (always check first if unsure)
pwsh -File Work.ps1 profile

# 1. ONE command only — append -Profile (nothing else changes):
pwsh -File Work.ps1 start "Plan weekend hike" -Category Personal -Profile personal
pwsh -File Work.ps1 dashboard -Profile personal

# 2. THIS shell window only — set an env var, then run commands normally:
$env:WORKLOG_PROFILE = 'personal'
pwsh -File Work.ps1 status            # now targets personal
$env:WORKLOG_PROFILE = ''             # back to the machine default

# 3. THIS computer's default — persist it (writes the git-ignored .profile file):
pwsh -File Work.ps1 profile personal  # every command now defaults to personal
pwsh -File Work.ps1 profile work      # switch the default back to work
```

Tips:
- A `-Profile` flag (way 1) always wins, even if the machine default is the other profile.
- The two logs are completely separate, so it's safe to keep work as your default and just
  append `-Profile personal` for the occasional personal entry.
- Typical setup: **work computer** stays on `work`; **personal computer** is set once to
  `personal` (`Work.ps1 profile personal`) so you never have to think about it again.

```powershell
pwsh -File Work.ps1 profile                 # show the active profile + its paths
pwsh -File Work.ps1 profile personal        # set THIS machine's default profile
pwsh -File Work.ps1 status -Profile personal # run any command against a profile once
```

**Use on another computer:** clone the `purduepete/copilot` repo, then
`pwsh -File worklog\Work.ps1 profile personal` once to make that machine personal.
Pull/push the repo to sync your personal log across machines.

## Model

- **Parallel sessions** are supported. Starting or switching **never** closes
  another session — sessions stay open until you explicitly stop them.
- `current` is just the session that notes / `stop` default to; **switch** moves it.
- Work is either an **ADO item** (pass `-Ado <id>`, linked in reports) or **ad-hoc**
  (meeting / review / support / admin — pass `-Category`).
- Each session records: start, end, duration, your accomplishment, optional blocker,
  and timestamped notes captured while you work.

## CLI usage

```powershell
# start work (auto ad-hoc unless -Ado given). Other open sessions stay open.
pwsh -File Work.ps1 start "Fix MS Sales pull" -Ado 435324 -Category Dev
pwsh -File Work.ps1 start "Architecture review" -Category Meeting

pwsh -File Work.ps1 switch -Id 1            # move 'current' to #1, nothing closes
pwsh -File Work.ps1 note  "Found root cause in the view definition"
pwsh -File Work.ps1 summary "High-level, fuzzy recap of the day's accomplishments"  # daily summary shown on the dashboard
pwsh -File Work.ps1 stop  "Patched view, validated counts" -Id 1 -Blocker "Need prod approval"

# edit a logged session after the fact (only the fields you pass change):
pwsh -File Work.ps1 edit -Id 5 "Better title"          # retitle (positional or -Title)
pwsh -File Work.ps1 edit -Id 5 -Category Dev -Status paused
pwsh -File Work.ps1 edit -Id 5 -Accomplishment "..." -Blocker "..."
pwsh -File Work.ps1 edit -Id 5 -Start "2026-06-16 14:00" -End "2026-06-16 15:30"  # back-date times
pwsh -File Work.ps1 edit -Id 5 -Reopen                 # clear end time, mark in-progress again

# forgot to log in real time? back-date a start/stop with -At:
pwsh -File Work.ps1 start "Architecture review" -Category Meeting -At "2026-06-16 16:00"
pwsh -File Work.ps1 stop  "Aligned on structure" -Id 7 -At "2026-06-16 16:23"

pwsh -File Work.ps1 status                  # all open sessions + time logged today
pwsh -File Work.ps1 search "fabric"         # search title/notes/project/accomplishment (all time)
pwsh -File Work.ps1 search "meeting" -Days 14 # limit search to the last 14 days
pwsh -File Work.ps1 standup                 # build + open daily standup (html), print md
pwsh -File Work.ps1 week                    # build + open weekly summary
pwsh -File Work.ps1 dashboard               # build + open interactive calendar dashboard
pwsh -File Work.ps1 add "Reviewed PR" -Start "2026-06-16 14:00" -End "2026-06-16 14:45" -Category Review  # log a finished session
pwsh -File Work.ps1 serve                   # live-edit dashboard at http://localhost:8787 (Ctrl+C to stop)
pwsh -File Work.ps1 log -Days 14            # recent sessions as a table

# add -Profile <name> to any command to target a specific profile, e.g.:
pwsh -File Work.ps1 dashboard -Profile personal
```

## Module usage (what Copilot calls under the hood)

```powershell
Import-Module .\WorkLog.psm1 -Force
Start-Work -Title "..." [-AdoId 123] [-Category Dev] [-Tags a,b] [-At <datetime>]
New-WorkSession -Start <dt> [-End <dt>] [-Title ..] [-Category ..] [-Project ..] [-AdoId ..] [-Accomplishment ..]   # add a complete session
Switch-Work -Id <n>
Add-WorkNote -Text "..." [-Id <n>]
Set-DayCommentary -Text "..." [-Date <dt>]     # high-level daily summary on the dashboard
Edit-Work -Id <n> [-Title ..] [-Category ..] [-AdoId ..] [-Tags a,b] [-Accomplishment ..] [-Blocker ..] [-Status ..] [-Start <dt>] [-End <dt>] [-Reopen]
Stop-Work [-Id <n>] -Accomplishment "..." [-Blocker "..."] [-Status done|paused|in-progress] [-At <datetime>]
Get-OpenSessions
Get-WorkLog [-Since <dt>] [-Until <dt>]
Find-WorkLog -Query "..." [-Since <dt>] [-Until <dt>]   # search sessions (title/notes/project/etc.)
Show-WorkStatus
New-Standup [-Date <dt>] [-NoOpen]
New-WeeklySummary [-Date <dt>] [-NoOpen]
New-WorkDashboard [-NoOpen]
Start-WorkServer [-Port 8787] [-NoOpen]    # serve dashboard with in-page editing of sessions
Set-WorkProfile [-Profile <name>]          # switch profile for this session
Set-WorkDefaultProfile -Profile <name>     # persist this machine's default (.profile)
Get-WorkProfile                            # current profile + resolved paths
```

`-At` lets you back-date a start/stop if you forgot to log it in real time.

## Editing sessions from the dashboard

Click **+ New item** (top-right, by the search box) to log a brand-new session, or the
**&#9998; Edit** button next to any row's number to change an existing one. Either opens a
form for the **start time**, **end time**, **category** (pick an existing one or choose
**+ New…** to type a new one), **project** (same dropdown-or-new), **item** (title), and
**accomplishment**.

Two ways to save:

- **Live editing (recommended):** start the dashboard server, then edit in the browser
  tab it opens. Clicking **Save** writes the change immediately (via `Edit-Work`, or
  `New-WorkSession` for a new item), rebuilds the dashboard, and reloads the page.

  ```powershell
  pwsh -File Edit-Dashboard.ps1 start     # launch server (background) + open browser
  pwsh -File Edit-Dashboard.ps1 stop      # shut it down
  pwsh -File Edit-Dashboard.ps1 status    # is it running?
  # options: -Port <n> -Profile <name> -NoOpen
  ```

  (Equivalent foreground server: `pwsh -File Work.ps1 serve` — runs until Ctrl+C.)
- **Plain file:// fallback:** if you opened `work-dashboard.html` directly (not served),
  **Save** copies the equivalent `Work.ps1 edit …` (or `Work.ps1 add …`) command to your
  clipboard — paste it into a terminal to apply. The log and dashboard update automatically.

Either way, the usual normalization applies (categories title-cased, first word of text
fields capitalized).


## Typical day, via Copilot

> "Starting on the MS Sales pull, work item 435324."  → `Start-Work`
> "Switching to a review meeting."                    → `Start-Work` (435324 stays open)
> "Back on the pull."                                 → `Switch-Work -Id 1`
> "Done with the pull — patched the view, validated counts. Blocked on prod approval."
>                                                      → `Stop-Work` with accomplishment + blocker
> "Give me my standup."                               → `New-Standup`
> "Wrap up the week."                                 → `New-WeeklySummary`

## Logging work from VS Code chat history

`Get-VSCodeWork.ps1` turns "what did I work on?" into one command. It maps the repo
folder to its VS Code `workspaceStorage` hash, reads the Copilot chat transcript(s),
converts the UTC event timestamps to **local time**, and groups your prompts into
**work blocks** separated by idle gaps. For each block it prints the exact start/end
time, duration, first/last message, any git commits in that window, and a ready-to-run
`Work.ps1 start` command.

```powershell
# Today's work blocks for the current repo (run from the repo, or pass -Folder):
pwsh -File worklog\Get-VSCodeWork.ps1 -Folder C:\Files\Dev\main\webportfolio

# A specific date / idle-gap threshold (minutes that separate one block from the next):
pwsh -File worklog\Get-VSCodeWork.ps1 -Folder C:\path\to\repo -Date 2026-06-18 -GapMinutes 60

# Machine-readable (for piping into a create-item step):
pwsh -File worklog\Get-VSCodeWork.ps1 -Json

# One-shot: parse AND create the work item for a block (default: last/most-recent block):
pwsh -File worklog\Get-VSCodeWork.ps1 -Folder C:\path\to\repo -Create
pwsh -File worklog\Get-VSCodeWork.ps1 -Create -Block 2 -Title "Custom title"
```

Then create the item with the exact start time it reports, e.g.:

```powershell
pwsh -File worklog\Work.ps1 start "<title>" -Category Dev -Project webportfolio -At '2026-06-18 22:44:51'
```

Notes:
- Terminal-notification messages are filtered out by default (use `-IncludeTerminal` to keep them).
- Times use the machine's local offset via `.ToLocalTime()`, so DST is handled automatically.