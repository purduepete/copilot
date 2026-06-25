---
name: worklog-highlights
description: >-
  Generate a concise, specific daily "highlights" summary from the user's WorkLog
  entries and write it as that day's commentary. Reads each session's title +
  accomplishment, skips generic/empty ones, and produces NO MORE THAN TWO LINES.
  WHEN: "generate today's highlights", "write my highlights", "summarize my day",
  "day highlights", "set the highlights", "recap my day", "what did I accomplish today".
argument-hint: Optionally a date (defaults to today, e.g. "yesterday", "2026-06-24")
---

# WorkLog Highlights

Produces a **less generic**, specific highlights blurb for a given day and saves it
as that day's WorkLog commentary (shown at the top of the dashboard).

## Rules

- **Max two lines.** Be specific and concrete — name what shipped, what was decided,
  what was explored. **No filler** like "worked on various tasks" or "had meetings".
- Pull material from each session's **title** and **accomplishment** for the day.
- **Skip generic/empty items**: commute/travel, lunch, and entries with no title and
  no accomplishment. Don't list routine status meetings unless a real decision/outcome
  came out of them (use the accomplishment text).
- Group related work into a single clause rather than enumerating every task.
- Capitalize the first word (WorkLog convention — `summary` does this automatically).
- Lead with the most impactful outcome (something shipped/decided), then secondary items.

## Steps

1. **Read the day's sessions** from the profile's `work-log.json`:

   ```powershell
   $d = Get-Content C:\Files\Dev\main\copilot\worklog\data\work\work-log.json -Raw | ConvertFrom-Json
   $day = (Get-Date).ToString('yyyy-MM-dd')   # or the requested date
   $d.sessions | Where-Object { $_.start -like "$day*" } | Sort-Object start |
     ForEach-Object { "[$($_.category)/$($_.project)] title='$($_.title)' acc='$($_.accomplishment)'" }
   ```

   (For the `personal` profile, use `data\personal\work-log.json`.)

2. **Compose** a <=2-line highlights string following the Rules above, drawing on the
   titles/accomplishments and ignoring travel/lunch/empty rows.

3. **Save it** as the day's commentary:

   ```powershell
   pwsh -NoProfile -File C:\Files\Dev\main\copilot\worklog\Work.ps1 summary "<highlights text>"
   ```

   For a past day, set the date first via the module:

   ```powershell
   Import-Module C:\Files\Dev\main\copilot\worklog\WorkLog.psm1 -Force
   Set-DayCommentary -Text "<highlights text>" -Date "2026-06-23"
   ```

4. **Confirm** to the user with the final two-line text. If the live server is running
   (http://localhost:8787/), tell them to hard-refresh (Ctrl+F5) to see it.

## Notes

- The commentary is stored per-profile in `work-log.json` under `commentary[yyyy-MM-dd]`.
- `summary` / `commentary` both map to `Set-DayCommentary`; passing empty text removes
  that day's commentary.
- This is a refinement of the `worklog` skill — prefer it specifically when the user
  asks for "highlights" or a day recap, rather than logging or editing time.
