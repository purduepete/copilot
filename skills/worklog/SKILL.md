---
name: worklog
description: >-
  Track the user's time with the cloud-hosted WorkLog CLI — start/stop/switch the running
  task, back-fill completed tasks, edit entries, add notes, and view the live web
  dashboard. Times map to WorkLog (NOT Outlook). WHEN: start work, stop work,
  switch task, log time, track time, add a task, "create task ending at HH:MM",
  back-date a task, "I worked on X", start/end of work day, "learning about X",
  "prepare for work day", "since my last item", recreate/rebuild the worklog html, dashboard,
  standup, weekly summary, start work log / open the web dashboard, set
  category/project/ADO id, lunch, commute to campus, create a note, jot a note,
  date-bound note, remember this, notes dashboard, "get calendar tasks",
  "get sessions tasks", "get session tasks", "get vscode tasks", "what am I working on",
  "log what I'm doing now", "propose a task", edit a task/entry, "delete item N",
  "delete task N", "delete entry N", "remove item N", delete/remove a session,
  "duplicate item N".
argument-hint: Describe the task plus any time/category/project (e.g. "log lunch 12:00-12:30" or "start 'Fix MS Sales pull' -Ado 435324 -Category development")
---

# WorkLog

Personal time tracking via a **cloud-hosted** PowerShell CLI (Azure Functions + SQL).
**Always use this for time-tracking requests — never Outlook.** All commands run through
one entry point, which calls the hosted API (auth via `az` token, no secret):

```
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 <command> [args]
```

Profiles keep logs separate: `work` and `home`. Each machine has a **default
profile** — **don't assume `work`**: read it first with
`pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile` (prints `Current profile: <name>`)
and use that as the active profile, overriding with `-Profile <name>` only when the user
asks for the other log. Everything persists to the cloud DB and is visible on the web
dashboard (https://func-worklog-umcla2.azurewebsites.net/).

## Commands

| Command | Purpose | Key args |
|---|---|---|
| `start "<title>"` | Begin a new running task | `-Category -Project -Ado -Tags -At <when> -AfterLast` |
| `startday` / `endday` | Mark the start/end of the work day (**0-minute marker** task) | `-At <when>` |
| `stop "<accomplishment>"` | Close the open task | `-Id -Blocker -Status <done\|paused\|in-progress> -At <when>` |
| `switch -Id <n>` | Switch active task to id n | |
| `add "<title>"` | Back-fill a **completed** task | `-Start <when> -End <when> -Category -Project -Ado -Tags -Accomplishment` |
| `edit -Id <n>` | Modify an entry | `-Title -Category -Project -Ado -Start -End -Accomplishment -Blocker -Status -Reopen` |
| `tasknote "<text>"` | Add a note to the open (or `-Id`) **task/session** | `-Id` |
| `note "<text>"` | Add a standalone **date-bound note** (not time-bound) | `-Date -Category -Tags` |
| `note -Id <n> ...` | Edit note n (`-Text -Date -Category -Tags`) or delete it (`-Remove`) | |
| `notes` | Rebuild + open the notes dashboard, then list recent notes | `-Days -NoOpen` |
| `close "<accomplishment>"` | Stop + optionally close a GitHub issue | `-Id -Issue -RepoPath -Commit -CloseIssue` |
| `summary "<text>"` | Set the day's commentary | |
| `status` | Show open sessions + time logged today | |
| `log -Days <n>` | List recent entries (ids, start, minutes, title) | |
| `delete -Id <n>` | Delete a session (`-Id` is the **actual global id**) | |
| `search "<q>"` | Search all sessions | `-Days <n>` |
| `standup` / `week` / `dashboard` | Regenerate the respective HTML report | `-NoOpen` |
| `serve` | Print the hosted dashboard URL (no local server — fully web) | |
| `profile [name]` | Show or set this machine's default profile | |

`<when>` accepts `[datetime]` strings, e.g. `-Start "2026-06-24 11:05" -End "2026-06-24 12:00"`.

## Rules & conventions

1. **Capitalize the first word** of every free-text field (title, accomplishment,
   blocker, task-note, standalone note, commentary). The module enforces this, but write it capitalized anyway.
   **Category and project are the exception: store them lowercase** (e.g. `development`,
   `webportfolio`) **unless the user explicitly asks for other casing** (e.g. `AI`).
   The module already lowercases these (with `ai`→`AI`); write them lowercase anyway.
   **Aliases:** `dev` means **`development`** — normalize it.
2. **`add` needs a Start.** If the user gives only an end time ("ending at HH:MM"),
   default the start to the **end of the last logged entry today** (check `log -Days 1`)
   so tasks chain without gaps. Confirm if the gap is large or ambiguous.
3. **Infer fields from history before asking.** When creating a task, if
   **category** or **project** is missing, first run
   `pwsh -File C:\Files\Dev\main\worklog_web\src\Suggest-WorkDefaults.ps1 -Title "<title>" -Json`.
   - If it returns `tier` ≠ `none`, **use the suggested `category`/`project`** (and
     `ado` if present); just state what you applied so the user can correct it. Prefer
     the top suggestion; mention an alternative only if `confidence` < 0.6.
   - Only if `tier` = `none` (no history for that title) **ask** the user for the
     missing field(s). Never silently guess without either history or the user.
   - **item (title)** must always come from the user — never invent it.
   (Time can still be inferred per rule 2.)
4. **Verify before/after.** Run `status` first when context is unclear; after a write,
   the command echoes the entry id (e.g. `+ Added #37`). Use that id for follow-up edits.
5. **Correct obvious typos** in category/project/title (e.g. "Investigatoin" → "Investigation"),
   and tell the user what you changed so they can revert.
6. **"Start work log"** = the hosted dashboard at
   https://func-worklog-umcla2.azurewebsites.net/ (sign in with Microsoft).
   **"Recreate / rebuild the html"** = `dashboard` (just opens that URL — the page is
   always live).
7. **"Item N" = per-day position, not the global id.** When the user says "item 5"
   (or "task 3", or just "task 1"), they mean the **Nth entry of that day**, counting from **1** in
   start-time order — **this is exactly the `Id` shown per-day on the web dashboard**, which
   restarts at 1 each day and is **not** the WorkLog global id. Resolve it by listing the day's entries
   (`log -Days 1`, filter to the target date, sort by start) and mapping position N
   to its **actual global id**, then act on that id. This applies to **every** id-taking verb —
   `edit`, `stop -Id`, `switch`, `tasknote -Id`, and **`delete -Id`**. E.g. "delete task 1" →
   resolve today's 1st entry to its real id, then `delete -Id <thatId>`.
   **Verify the resolved id exists before deleting** — `delete` reports success even for a
   nonexistent id, so never pass a raw number straight through without resolving it first.
8. **Workday boundaries are enforced (the module throws on violation) — per-profile,
   controlled by each profile's `enforceWorkday` flag (see the `worklog-profile` skill).
   By default **no profile enforces** (time bound OFF for all); opt a profile in with
   `profile <name> -Bounds on`. A profile with bounds OFF has no concept of start/end
   day, so none of these constraints apply to it:**
   - **Nothing can be logged until that day's `startday` marker exists** (bounds-on
     profiles only — a **bounds-off profile is exempt** and needs no start-of-day marker).
     If `start`/`add` errors with *"No start-of-day marker…"*, run `startday` (at the
     appropriate time) first, then retry.
   - **A task must fall entirely within the work-day window** (bounds-on profiles only). It **can't start (or occur)
     before the start-of-day marker**, and **can't start or end after the end-of-day marker**
     — applies to every entry path: `start`, `add`, `stop`, `edit -Start/-End`, duplicates,
     the session miners (`Get-CopilotWork`/`Get-VSCodeWork`), and the proactive proposer
     (`Suggest-CurrentWork`). A task that would fall **wholly outside** the day's bounds is
     rejected. Set/adjust the markers (`startday`/`endday -At <when>`) to widen the day if a
     task legitimately falls outside it. (To check/toggle a profile's bounds, use
     `profile [-Bounds on|off|default]`.)
9. **No overlapping tasks.** A new or edited task's time range must **not overlap** any
   existing task on that day (markers, which are 0-minute, don't count). Before any `add`,
   `start … -At`/`-End`, duplicate, or `edit -Start/-End`, list the day (`log -Days 1`,
   filter to that date, sort by start) and check the proposed `[Start, End)` against every
   other entry's `[start, end)`. Two ranges overlap when `Start < other.end` **and**
   `End > other.start`. If it would overlap, **do not write it** — tell the user which
   item(s) it collides with and ask how to resolve (e.g. shorten/move the new task, trim
   the existing one, or chain it after the last entry's end per rule 2). An in-progress
   task (no end) occupies from its start to *now* for this check.

## Phrase triggers

Natural-language phrases that map to specific actions:

- **"find gaps" / "untracked time" / "what did I miss" / "what's unaccounted"** → run
  `pwsh -File C:\Files\Dev\main\worklog_web\src\Find-WorkGaps.ps1 -Json` (add
  `-Date <yyyy-MM-dd>` for another day). Present the gaps, then **offer to fill each one**:
  ask the user what they were doing, infer category/project via rule 3
  (`Suggest-WorkDefaults.ps1`), and `add` it with the gap's exact `-Start`/`-End` (so the
  new entries chain cleanly and never overlap per rule 9).
- **"start of work day"** → `startday` (0-min marker). **"end of work day"** → first
  `stop` any open running item, then **run gap analysis**
  (`pwsh -File C:\Files\Dev\main\worklog_web\src\Find-WorkGaps.ps1`) and present any
  untracked gaps (>= 10 min), offering to fill them per the "find gaps" routine above;
  then **update the day's summary** (`summary "<text>"`,
  e.g. via the worklog-highlights routine), then `endday`
  (pass `-At "<yyyy-MM-dd HH:mm>"` to set a specific time). These bound the work day for
  untracked-gap detection and render as divider rows on the dashboard.
- **"learning about &lt;x>"** → `start "Learning about <x>" -Category education -Project personal`.
- **"get calendar tasks" / "import my calendar" / "import meetings" / "log my meetings" / "calendar to worklog"** →
  run `pwsh -File C:\Files\Dev\main\worklog_web\src\Import-CalendarDay.ps1 -Json` (add
  `-Date <yyyy-MM-dd>` for another day). It reads the day's Outlook meetings (organized/
  accepted, busy, already-started only — skips all-day OOO/holds, free/tentative/declined,
  and personal non-meeting blocks), infers project from history, and dedupes against
  existing entries. **Present the preview**, then on confirmation re-run with `-Apply` to
  add the `new` entries. For any `needproj` items, ask the user for the project (or infer
  via rule 3) and `add` them individually with the meeting's exact `-Start`/`-End`;
  `conflict`/`logged` items are left alone. For a **past day with no start-of-day marker**,
  add `-OpenDay` so it sets `startday` (anchored at the earliest kept meeting) before adding.
- **"prepare for work day"** → morning routine: show today's **calendar** (only on the
  work computer — see below), surface overnight items to address, then `start` a prep task
  (`-Category admin -Project work`).
- **"since my last item" / "after my last task"** → use `start … -AfterLast` (auto-sets the
  start to the most recent session's end, so no overlap). Don't look up the prior end time manually.

## Operational conventions

- **Closing a task is one call.** Use `close "<accomplishment>" [-Id N] [-Issue G -RepoPath <repo> -CloseIssue]`
  — it bundles the gh-issue note + stop + a single dashboard rebuild. Don't call note/stop/dashboard separately.
- **GitHub-issue note format.** When a task maps to a GitHub issue, add a note with a markdown
  link `[#N Title](url)` plus **milestone, state, and commit hash**.
- **Prefer a single Markdown note** over many small notes — the dashboard note modal renders
  basic Markdown (bold, `code`, bullet lists, line breaks, links).
- **Logging from VS Code chat.** For "get vscode tasks" / "log my work from chat" / "what did I do in the last hour":
  run `pwsh -File C:\Files\Dev\main\worklog_web\src\Get-VSCodeWork.ps1 -Folder <repo> [-Date d | -LastMinutes N] [-GapMinutes 90] [-Json]`, present a
  numbered table (ID | work | start | end) — the script splits the session into blocks on idle gaps (`-GapMinutes`, default 90) —
  let the user pick an ID, then `-Create -Block <ID>` (logs the block with its exact start/end). Don't parse transcripts manually.
  - **Scan all repos, not just the cwd.** "get vscode tasks" means **every repo two levels under `C:\Files\Dev\` (i.e. `C:\Files\Dev\*\*`, e.g. `C:\Files\Dev\main\webbookmarks`), excluding any folder named `clustergit`** — don't ask for / assume a single folder. Enumerate VS Code `workspaceStorage` (`%APPDATA%\Code\User\workspaceStorage\*\workspace.json`), keep the folders that match that pattern and have a `GitHub.copilot-chat\transcripts` dir, then run `Get-VSCodeWork.ps1 -Folder <repo>` against each for the target day (default today). Present blocks grouped by repo; if a repo has no transcripts for the day, skip it. If **no** repo has activity for the day, say so and surface the most-recent untracked block as a fallback.
- **Logging from a Copilot CLI session.** For "get sessions tasks" / "get session tasks" / "log my Copilot work" / "create tasks from today's session" / "what did I do in this session":
  run `pwsh -File C:\Files\Dev\main\worklog_web\src\Get-CopilotWork.ps1 [-Date d | -Current | -LastMinutes N] [-GapMinutes 30] [-Json]`.
  It reads today's `~/.copilot/session-state/*/events.jsonl` (default = all of today's sessions; `-Current` = the live one), chunks `user.message`
  events on idle gaps, and presents a numbered table. Pick one, then `-Create -Block <ID> -Category <c> -Project <p>`.
- **Non-overlap boundary (both getters).** By default both `Get-VSCodeWork.ps1` and `Get-CopilotWork.ps1` **trim every block to untracked time** —
  the day's existing WorkLog entries are subtracted, so proposed/created blocks never overlap what's already logged (a block straddling a tracked
  span is split or dropped, marked `[trimmed]`). Pass `-AllowOverlap` only if the user explicitly wants the raw, untrimmed blocks. Blocks shorter than
  `-MinMinutes` (default 10) are omitted.
  - **Trimming is now cross-profile by default (no double-counting).** `Get-WorkLogBusy` unions the busy intervals of **all** profiles
    (`work` + `home`), so a block is trimmed to time untracked in **any** log regardless of which `-Profile` you preview/log under — the
    17:18-vs-18:08 cross-profile double-count is fixed. Pass **`-ProfileOnlyTrim`** to restrict trimming to the target `-Profile` only (legacy
    behavior). You still pass the `-Profile` you'll log under (it sets where the entry lands and which markers apply), but the trimmed start no
    longer shifts between profiles. Use `-AllowOverlap` for raw, untrimmed blocks.
  - **Never combine `-Json` with `-Create`.** `Get-CopilotWork.ps1`/`Get-VSCodeWork.ps1` `return` on `-Json` **before** the create branch, so
    `-Json -Create` prints JSON and logs **nothing**. Use `-Json` only to read blocks; drop it when creating.
- **Proactive proposal (zero-entry logging).** For "what am I working on" / "log what I'm doing now" / "propose a task" / a scheduled
  proactive check: run `pwsh -File C:\Files\Dev\main\worklog_web\src\Suggest-CurrentWork.ps1 [-Json]`. It fuses **live signals** — the active
  Copilot CLI session (`inuse.*.lock`) + recent **git** commits/dirty trees across your repos + WorkLog state — into a single confirm-ready
  entry for the current untracked stretch (window = first activity after the last tracked time -> now, trimmed by the non-overlap boundary).
  It **stays silent while a task is already running** and infers title/category/project (reporting a `confidence` of high/medium/low). Show the
  proposal, let the user confirm/edit, then log with `-Create` (or `-Create -Title "..." -Category <c> -Project <p>` to override). Best used from
  a scheduled prompt: run with `-Json`; if `propose` is true, surface it; otherwise say nothing.
- **Dashboard is always live.** The hosted dashboard reads the cloud DB on each load, so
  any write is visible on refresh — there is no HTML file to regenerate.
- **Data caveat.** In the stored state, `current` must be a **scalar session id or `null`**,
  never `[]` — an empty array breaks `Stop-Work`.
- **Calendar (work machine only).** Only read the Outlook calendar when `$env:COMPUTERNAME`
  starts with `xfinjimb` (the work computer); otherwise skip it. See the `calendar` skill.

## Common recurring tasks

| Item | Category | Project | Typical time |
|---|---|---|---|
| `Commute to campus` | travel | work | 07:00–09:30 |
| `Lunch` | lunch | — | user supplies the range |

Add these with `add "<Item>" -Start <s> -End <e> -Category <cat> [-Project <proj>]`.

## Common operations

**Duplicate an entry.** "Duplicate item N [to item M] [ending at HH:MM]" creates a
**new** entry copying the source's **title, category, and project**. Resolve item N
to its id (per rule 7), read those fields, then `add` a new entry. Start chains from
the **end of the last logged entry** (rule 2); use the provided end time (the target
"item M" is just the resulting per-day position, computed automatically — you don't set it).

```powershell
# Duplicate today's item 4 into the next slot, ending 12:45
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 add "<copied title>" -Start "2026-06-24 12:20" -End "2026-06-24 12:45" -Category <copied-cat> -Project <copied-proj>
```

## Notes (date-bound, not time-bound)

Notes are things to remember tied to a **calendar date**, with **no start/stop time** —
distinct from time-tracked sessions. They live in the same WorkLog state (so they honor
the `work` / `home` profile split) and render to their own **notes-dashboard.html**.

- **"Create / jot a note", "remember this", "note that…"** → `note "<text>"`. Defaults to
  **today**; pass `-Date <yyyy-MM-dd>` for another day, `-Category <c>`, `-Tags a,b`.
- **Edit** → `note -Id <n> -Text "…"` (and/or `-Date -Category -Tags`).
- **Delete** → `note -Id <n> -Remove`.
- **View** → `notes` (rebuilds + opens the standalone dashboard, then prints recent notes;
  `-Days <n>` window). Notes **also appear as a section below the work log** on the
  web `dashboard`, with inline **+ Add note** and per-note edit/delete.
- Ask for **category** only if the user implies one; tags and category are optional for notes
  (unlike tasks, a bare note text is enough).
- **`tasknote`** is different: it attaches a note to a running/`-Id` **work session**, not a date.

```powershell
# Jot a date-bound note for today
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 note "Ask Sri about the ADR split" -Category followup -Tags bedrock

# Note for a specific date, then view the dashboard
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 note "Renew ADO PAT" -Date 2026-07-01
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 notes
```

## Examples

```powershell
# Begin a task now, linked to an ADO item
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 start "Fix MS Sales pull" -Ado 435324 -Category development

# Stop the open task with an accomplishment
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 stop "Patched view, validated row counts"

# Back-fill a finished meeting, chaining from the last entry's end time
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 add "AI In-the-middle weekly open session" -Start "2026-06-24 12:00" -End "2026-06-24 12:30" -Category meeting -Project AI

# Fix a field on an existing entry
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 edit -Id 38 -Project AI

# Refresh dashboards
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 dashboard
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 serve        # live-edit ("start work log")
```
