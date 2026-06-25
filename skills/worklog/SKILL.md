---
name: worklog
description: >-
  Track the user's time with the local WorkLog CLI — start/stop/switch the running
  task, back-fill completed tasks, edit entries, add notes, and regenerate the
  dashboard. Times map to WorkLog (NOT Outlook). WHEN: start work, stop work,
  switch task, log time, track time, add a task, "create task ending at HH:MM",
  back-date a task, "I worked on X", recreate/rebuild the worklog html, dashboard,
  standup, weekly summary, start work log / serve the live-edit dashboard, set
  category/project/ADO id, lunch, commute to campus, create a note, jot a note,
  date-bound note, remember this, notes dashboard.
argument-hint: Describe the task plus any time/category/project (e.g. "log lunch 12:00-12:30" or "start 'Fix MS Sales pull' -Ado 435324 -Category Dev")
---

# WorkLog

Personal time tracking via a local PowerShell CLI. **Always use this for time-tracking
requests — never Outlook.** All commands run through one entry point:

```
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 <command> [args]
```

Profiles keep logs separate: `work` (default) and `personal`. Add `-Profile personal`
to any command to target the personal log.

## Commands

| Command | Purpose | Key args |
|---|---|---|
| `start "<title>"` | Begin a new running task | `-Category -Project -Ado -Tags -At <when> -AfterLast` |
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
| `search "<q>"` | Search all sessions | `-Days <n>` |
| `standup` / `week` / `dashboard` | Regenerate the respective HTML report | `-NoOpen` |
| `serve` | Launch the localhost live-edit dashboard | `-Port` (default 8787) |
| `profile [name]` | Show or set this machine's default profile | |

`<when>` accepts `[datetime]` strings, e.g. `-Start "2026-06-24 11:05" -End "2026-06-24 12:00"`.

## Rules & conventions

1. **Capitalize the first word** of every free-text field (title, accomplishment,
   blocker, task-note, standalone note, commentary). The module enforces this, but write it capitalized anyway.
2. **`add` needs a Start.** If the user gives only an end time ("ending at HH:MM"),
   default the start to the **end of the last logged entry today** (check `log -Days 1`)
   so tasks chain without gaps. Confirm if the gap is large or ambiguous.
3. **Ask for missing fields.** When creating a task, if **category**, **project**, or
   **item (title)** was not provided, ask the user for the missing field(s) before adding —
   do not guess. (Time can still be inferred per rule 2.)
4. **Verify before/after.** Run `status` first when context is unclear; after a write,
   the command echoes the entry id (e.g. `+ Added #37`). Use that id for follow-up edits.
5. **Correct obvious typos** in category/project/title (e.g. "Investigatoin" → "Investigation"),
   and tell the user what you changed so they can revert.
6. **"Start work log"** = `serve` (live-edit dashboard at http://localhost:8787).
   **"Recreate / rebuild the html"** = `dashboard`.
7. **"Item N" = per-day position, not the global id.** When the user says "item 5"
   (or "task 3"), they mean the **Nth entry of that day**, counting from **1** in
   start-time order — not the WorkLog id. Resolve it by listing the day's entries
   (`log -Days 1`, filter to the target date, sort by start) and mapping position N
   to its id, then act on that id. E.g. today's 5th entry → its actual id for `edit`.

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
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 add "<copied title>" -Start "2026-06-24 12:20" -End "2026-06-24 12:45" -Category <copied-cat> -Project <copied-proj>
```

## Notes (date-bound, not time-bound)

Notes are things to remember tied to a **calendar date**, with **no start/stop time** —
distinct from time-tracked sessions. They live in the same WorkLog state (so they honor
the `work` / `personal` profile split) and render to their own **notes-dashboard.html**.

- **"Create / jot a note", "remember this", "note that…"** → `note "<text>"`. Defaults to
  **today**; pass `-Date <yyyy-MM-dd>` for another day, `-Category <c>`, `-Tags a,b`.
- **Edit** → `note -Id <n> -Text "…"` (and/or `-Date -Category -Tags`).
- **Delete** → `note -Id <n> -Remove`.
- **View** → `notes` (rebuilds + opens the standalone dashboard, then prints recent notes;
  `-Days <n>` window). Notes **also appear as a section below the work log** on the
  `dashboard` / `serve` page, with inline **+ Add note** and per-note edit/delete.
- Ask for **category** only if the user implies one; tags and category are optional for notes
  (unlike tasks, a bare note text is enough).
- **`tasknote`** is different: it attaches a note to a running/`-Id` **work session**, not a date.

```powershell
# Jot a date-bound note for today
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 note "Ask Sri about the ADR split" -Category followup -Tags bedrock

# Note for a specific date, then view the dashboard
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 note "Renew ADO PAT" -Date 2026-07-01
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 notes
```

## Examples

```powershell
# Begin a task now, linked to an ADO item
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 start "Fix MS Sales pull" -Ado 435324 -Category Dev

# Stop the open task with an accomplishment
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 stop "Patched view, validated row counts"

# Back-fill a finished meeting, chaining from the last entry's end time
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 add "AI In-the-middle weekly open session" -Start "2026-06-24 12:00" -End "2026-06-24 12:30" -Category Meeting -Project AI

# Fix a field on an existing entry
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 edit -Id 38 -Project AI

# Refresh dashboards
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 dashboard
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 serve        # live-edit ("start work log")
```
