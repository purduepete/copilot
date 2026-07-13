---
name: worklog-day
description: >-
  Manage @jimb's WorkLog day boundaries and recap. START: read the active profile, check
  whether today's start-of-day marker already exists (idempotent — never double-mark), run
  startday. HIGHLIGHTS: generate a concise (<=2 line) specific day recap from the day's
  sessions and save it as the day's commentary. END: use Get-DayClose to find blockers,
  resolve each with confirmation (stop running task, fill untracked gaps, normalize
  projects, set the day summary), then run endday once ready.
  WHEN: "start of day", "start of work day", "start my work day", "begin my work day",
  "startday", "open my work day", "clock in", "I'm starting work", "mark start of day",
  "generate today's highlights", "write my highlights", "summarize my day", "day
  highlights", "set the highlights", "recap my day", "what did I accomplish today", "end my
  work day", "end of day", "wrap up my day", "close out the day", "endday", "am I ready to
  close the day", "finish my work day", "end work day".
argument-hint: (none) — operates on today; pass a time only if back-dating start, or a date for highlights
---

# worklog-day — open, recap, and close the WorkLog day

Three phases of a WorkLog day, all driven off the same `wl.ps1` CLI and the
`Get-DayClose.ps1` readiness tool. Jump to the phase the user asked for:

- **Part 1 — Start the day** (`startday`, idempotent)
- **Part 2 — Highlights** (day recap → commentary)
- **Part 3 — End the day** (`Get-DayClose` blockers → `endday`)

> **Never** stop a task, add/edit an entry, set a summary, or run `startday`/`endday`
> without explicit user confirmation (starting a fresh day on request is fine).

---

## Part 1 — Start the day, the right way

Lays down the day's **`startday`** marker (a 0-minute divider) so bounds-on
profiles can log tasks and untracked-gap detection has a lower bound. Its whole
job is to do this **idempotently** — never stamp a second start marker on a day
that's already open.

### 1. Read the active profile
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile
```
Note the `Current profile:` and whether bounds are enforced. Use that profile
(override with `-Profile <name>` only if the user asks for the other log).

> A **bounds-off** profile has no concept of start-of-day, so a start marker is
> optional there — still fine to lay one down as a visual divider if asked, but
> don't treat its absence as a problem.

### 2. Check whether the day is already open (idempotent guard)
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\src\Get-DayClose.ps1 -Json
```
Parse `{ dayOpen, dayClosed, ... }`:

- If `dayOpen` is **true** → the start marker already exists. **Do not run
  startday again.** Tell the user the day is already open and stop.
- If `dayClosed` is **true** (day already ended) → say so; only re-open if the
  user explicitly wants to (that's unusual — confirm first).
- Otherwise (`dayOpen:false`, `dayClosed:false`) → proceed to step 3.

### 3. Mark the start of the day
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 startday
```
To back-date it, pass an explicit time (e.g. the user says "I started at 8"):
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 startday -At "2026-07-02 08:00"
```
No time given → use now (the default).

### 4. Verify it persisted
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 status
```
Re-running `Get-DayClose.ps1 -Json` should now show `dayOpen:true`. Give a
one-line confirmation (e.g. "Work day started on the *work* profile.").

**Start notes**
- "Prepare for work day" is a *richer* morning routine (calendar, overnight items,
  a prep task) — see the `worklog` skill's phrase triggers. This part only lays
  down the start marker; escalate to that routine only if the user asks for prep.
- Never lay down a second start marker — the step-2 `dayOpen` check exists to
  prevent exactly that.

---

## Part 2 — Highlights (day recap)

Produces a **less generic**, specific highlights blurb for a given day and saves it
as that day's WorkLog commentary (shown at the top of the dashboard). This is also
the source of the day summary used in Part 3.

### Rules

- **Max two lines.** Be specific and concrete — name what shipped, what was decided,
  what was explored. **No filler** like "worked on various tasks" or "had meetings".
- Pull material from each session's **title** and **accomplishment** for the day.
- **Skip generic/empty items**: commute/travel, lunch, and entries with no title and
  no accomplishment. Don't list routine status meetings unless a real decision/outcome
  came out of them (use the accomplishment text).
- Group related work into a single clause rather than enumerating every task.
- Capitalize the first word (WorkLog convention — `summary` does this automatically).
- Lead with the most impactful outcome (something shipped/decided), then secondary items.

### Steps

1. **Read the day's sessions** from the cloud via the CLI's `state` command:

   ```powershell
   $d = pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 state -Profile work | ConvertFrom-Json
   $day = (Get-Date).ToString('yyyy-MM-dd')   # or the requested date
   $d.sessions | Where-Object { $_.start -like "$day*" } | Sort-Object start |
     ForEach-Object { "[$($_.category)/$($_.project)] title='$($_.title)' acc='$($_.accomplishment)'" }
   ```

   (For the `home` profile, pass `-Profile home`.)

2. **Compose** a <=2-line highlights string following the Rules above, drawing on the
   titles/accomplishments and ignoring travel/lunch/empty rows.

3. **Save it** as the day's commentary:

   ```powershell
   pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 summary "<highlights text>"
   ```

   For a past day, pass `-Date`:

   ```powershell
   pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 summary "<highlights text>" -Date "2026-06-23"
   ```

4. **Confirm** to the user with the final two-line text, then tell them to refresh the
   web dashboard (https://func-worklog-umcla2.azurewebsites.net/) to see it.

**Highlights notes**
- The commentary is stored per-profile in the cloud DB under `commentary[yyyy-MM-dd]`.
- `summary` / `commentary` both map to `Set-DayCommentary`; passing empty text removes
  that day's commentary.
- Prefer this part specifically when the user asks for "highlights" or a day recap,
  rather than logging or editing time.

---

## Part 3 — End the day, the right way

Drives the **`Get-DayClose.ps1`** tool. The tool returns a single verdict (`ready`)
plus a `blockers[]` list; this part's job is to resolve the blockers, **confirming
before every mutation**, then run `endday`.

### 1. Check readiness
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\src\Get-DayClose.ps1 -Json
```
Parse the JSON: `{ ready, blockers[], running, gaps[], totalGapMin, summarySet, dayOpen, dayClosed }`.

- If `dayClosed` is true → the day is already closed; say so and stop.
- If `dayOpen` is false → the work day never started; say so and stop (don't endday).
- If `ready` is true → skip to **step 3 (endday)**.
- Otherwise show the user the blockers briefly and resolve them (step 2).

### 2. Resolve blockers (each needs confirmation)
Work the `blockers[]` — in this order — re-checking with the tool after fixes:

- **Running task** (`running:{id,title,minutes}`): ask whether to stop it and for
  an accomplishment, then:
  ```powershell
  pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 stop -Id <id> -Text "<accomplishment>"
  ```
  (Add `-At "<yyyy-MM-dd HH:mm>"` to back-date the stop.)

- **Untracked gaps** (`gaps[]`): by default, fill **every** untracked gap as a
  single non-work entry titled **"Away from work"** with **category `personal`**
  — no need to ask per gap:
  ```powershell
  pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 add -Text "Away from work" -Start "<yyyy-MM-dd HH:mm>" -End "<yyyy-MM-dd HH:mm>" -Category personal
  ```
  Only diverge from this default if the user has already told you what a specific
  gap was (then use that title/category instead). Never invent billable work.

- **Day highlights (always refresh at end-of-day):** ending the day **always**
  updates the day's highlights — regardless of whether a summary already exists.
  Compose a fresh crisp recap from the day's completed work (**Part 2** above:
  read the day's sessions, follow the Rules, skip lunch/travel/empty rows) and
  save it, overwriting any earlier summary so it reflects the *full* day:
  ```powershell
  pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 summary "<one-to-two line recap>"
  ```
  This resolves the `summarySet:false` blocker too, but do it even when
  `summarySet` is already `true` so the highlights aren't stale.

- **Normalize projects (always, before endday):** any of today's **work** entries
  with **no project** gets **`project = n/a`** — no need to ask. **Skip non-work /
  divider rows** (categories `lunch`, `personal`, and the `Day` start/end markers) —
  those legitimately have no project and should be left untouched. List today via
  `wl.ps1 state` (filter `sessions` to today, excluding those categories), then for
  each remaining projectless id:
  ```powershell
  pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 edit -Id <id> -Project "n/a"
  ```

Re-run `Get-DayClose.ps1 -Json` after resolving; loop until `ready:true`.

### 3. End the day
Only when `ready` is true and the user confirms:
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 endday
```
Then give a one-line confirmation (day closed, total tracked, summary).

**End notes**
- `Get-DayClose.ps1` thresholds: gaps count at **>= 10 min**; a **day summary is
  required** for readiness (by design).
- Tasks must fall within the start..end day boundary — don't add entries outside it.
- This is the same routine the 6 PM scheduled check (#1) offers; running it
  on-demand is identical.
- Start and end are mirror images; both bound the day for untracked-gap detection
  and render as divider rows on the dashboard.
