---
name: worklog-endday
description: >-
  Close out @jimb's WorkLog day correctly using the Get-DayClose readiness tool:
  check what's blocking endday, then resolve each blocker (stop the running task,
  fill untracked gaps, set the day summary) — each only with explicit confirmation —
  and finally run endday once the verdict is ready=true. WHEN: "end my work day",
  "end of day", "wrap up my day", "close out the day", "endday", "am I ready to
  close the day", "finish my work day", "end work day".
argument-hint: (none) — operates on today
---

# worklog-endday — close the day, the right way

This skill drives the **`Get-DayClose.ps1`** tool. The tool returns a single
verdict (`ready`) plus a `blockers[]` list; this skill's job is to resolve the
blockers, **confirming before every mutation**, then run `endday`.

> **Never** stop a task, add/edit an entry, set a summary, or run `endday`
> without explicit user confirmation.

## 1. Check readiness
```powershell
pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\src\Get-DayClose.ps1 -Json
```
Parse the JSON: `{ ready, blockers[], running, gaps[], totalGapMin, summarySet, dayOpen, dayClosed }`.

- If `dayClosed` is true → the day is already closed; say so and stop.
- If `dayOpen` is false → the work day never started; say so and stop (don't endday).
- If `ready` is true → skip to **step 3 (endday)**.
- Otherwise show the user the blockers briefly and resolve them (step 2).

## 2. Resolve blockers (each needs confirmation)
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

- **No day summary** (`summarySet:false`): generate a crisp highlights line (invoke
  the **worklog-highlights** skill) or ask the user, then:
  ```powershell
  pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 summary "<one-to-two line recap>"
  ```

- **Normalize projects (always, before endday):** any of today's entries with **no
  project** gets **`project = n/a`** — no need to ask. List today via
  `wl.ps1 state` (filter `sessions` to today), then for each projectless id:
  ```powershell
  pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 edit -Id <id> -Project "n/a"
  ```

Re-run `Get-DayClose.ps1 -Json` after resolving; loop until `ready:true`.

## 3. End the day
Only when `ready` is true and the user confirms:
```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 endday
```
Then give a one-line confirmation (day closed, total tracked, summary).

## Notes
- `Get-DayClose.ps1` thresholds: gaps count at **>= 10 min**; a **day summary is
  required** for readiness (by design).
- Tasks must fall within the start..end day boundary — don't add entries outside it.
- This is the same routine the 6 PM scheduled check (#1) offers; running it
  on-demand is identical.
