---
name: worklog-startday
description: >-
  Open @jimb's WorkLog day the right way: read the active profile, check whether
  today's start-of-day marker already exists (idempotent — never double-mark), then
  run startday (optionally back-dated with -At), and confirm it persisted. WHEN:
  "start of day", "start of work day", "start my work day", "begin my work day",
  "startday", "open my work day", "clock in", "I'm starting work", "mark start of day".
argument-hint: (none) — operates on today; pass a time only if back-dating
---

# worklog-startday — open the day, the right way

This skill lays down the day's **`startday`** marker (a 0-minute divider) so
bounds-on profiles can log tasks and untracked-gap detection has a lower bound.
Its whole job is to do this **idempotently** — never stamp a second start marker
on a day that's already open.

## 1. Read the active profile
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile
```
Note the `Current profile:` and whether bounds are enforced. Use that profile
(override with `-Profile <name>` only if the user asks for the other log).

> A **bounds-off** profile has no concept of start-of-day, so a start marker is
> optional there — still fine to lay one down as a visual divider if asked, but
> don't treat its absence as a problem.

## 2. Check whether the day is already open (idempotent guard)
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\src\Get-DayClose.ps1 -Json
```
Parse `{ dayOpen, dayClosed, ... }`:

- If `dayOpen` is **true** → the start marker already exists. **Do not run
  startday again.** Tell the user the day is already open and stop.
- If `dayClosed` is **true** (day already ended) → say so; only re-open if the
  user explicitly wants to (that's unusual — confirm first).
- Otherwise (`dayOpen:false`, `dayClosed:false`) → proceed to step 3.

## 3. Mark the start of the day
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 startday
```
To back-date it, pass an explicit time (e.g. the user says "I started at 8"):
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 startday -At "2026-07-02 08:00"
```
No time given → use now (the default).

## 4. Verify it persisted
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 status
```
Re-running `Get-DayClose.ps1 -Json` should now show `dayOpen:true`. Give a
one-line confirmation (e.g. "Work day started on the *work* profile.").

## Notes
- This is the **mirror image** of the `worklog-endday` skill; both bound the day
  for untracked-gap detection and render as divider rows on the dashboard.
- "Prepare for work day" is a *richer* morning routine (calendar, overnight items,
  a prep task) — see the `worklog` skill's phrase triggers. This skill only lays
  down the start marker; escalate to that routine only if the user asks for prep.
- Never lay down a second start marker — the step-2 `dayOpen` check exists to
  prevent exactly that.
