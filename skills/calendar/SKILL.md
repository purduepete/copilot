---
name: calendar
description: >-
  Read the user's Outlook calendar on this Windows machine via the Outlook COM
  API (local, no Graph/login) and report the current or upcoming meeting(s) —
  subject, time, organizer, Teams join link, and agenda. Can hand the meeting to
  the worklog skill to log it. WHEN: read my calendar, what meeting am I in,
  what's my next meeting, what's on my calendar, meeting in the next hour, who
  organized this meeting, Teams link for my meeting, log this meeting to my worklog.
argument-hint: Optionally a time window (defaults to the whole day; e.g. "next hour", "rest of today", "now")
---

# Calendar (Outlook, local COM)

> **Machine gate:** Only attempt a calendar read when `$env:COMPUTERNAME` starts with
> `xfinjimb` (the work computer). On any other machine, Outlook COM is unavailable —
> report that calendar access isn't available here instead of trying (it will hang).

Reads the local Outlook desktop client's default calendar. Works offline against
the installed profile — **no Microsoft Graph, no separate auth**.

## Read meetings overlapping a window

Default window = **the whole of today** (midnight → midnight). Only narrow it
(e.g. "next hour", "now", "rest of today") when the user explicitly asks for a
different range. Adjust `$dayStart`/`$dayEnd` accordingly.

```powershell
$ol = New-Object -ComObject Outlook.Application
$ns = $ol.GetNamespace('MAPI')
$cal = $ns.GetDefaultFolder(9)            # 9 = olFolderCalendar
$items = $cal.Items
$items.IncludeRecurrences = $true          # REQUIRED for recurring meetings
$items.Sort('[Start]')
$now = Get-Date
$dayStart = $now.Date; $dayEnd = $dayStart.AddDays(1)
# Restrict needs US-format 'MM/dd/yyyy hh:mm tt' strings
$filter = "[Start] < '" + $dayEnd.ToString('MM/dd/yyyy hh:mm tt') + "' AND [End] > '" + $dayStart.ToString('MM/dd/yyyy hh:mm tt') + "'"
$id = 0
foreach ($a in $items.Restrict($filter)) {
  $id++
  "=== [$id] $($a.Subject) ==="
  "ID: $id"
  "Start: $($a.Start)   End: $($a.End)"
  "Location: $($a.Location)"
  "Organizer: $($a.Organizer)"
  $b = $a.Body; if ($b.Length -gt 1500) { $b = $b.Substring(0,1500) + ' ...[truncated]' }
  "--- Body ---"; $b; ""
}
```

Always include an **ID** column when listing meetings (a 1-based sequential
number in `[Start]` order). It lets the user refer to a meeting by ID (e.g.
"log #3 to my worklog") without retyping the subject.

## Interpreting results

- **All-day entries** with names like "<Person> OOF/OOO/OOO - …" are out-of-office
  markers, **not meetings** — skip them when the user asks "what meeting am I in".
- The real meeting is the timed event (e.g. 12:00–12:30). Surface its **ID,
  subject, time, organizer, Teams join link** (parse the `https://teams.microsoft.com/meet/…`
  or `…/l/meetup-join/…` URL from the body) and a short agenda summary.
- When presenting meetings as a table, the **first column must be the ID**.
- `IncludeRecurrences = $true` and `Sort('[Start]')` are both required or recurring
  meetings are missed.

## Hand off to worklog (optional)

If the user wants the meeting tracked, call the **worklog** skill — e.g.:

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 add "<Subject>" -Start "<yyyy-MM-dd HH:mm>" -End "<yyyy-MM-dd HH:mm>" -Category Meeting [-Project <p>]
```

Capitalize the first word of the title (worklog convention).

## Notes

- Requires the Outlook desktop client installed and signed in on this machine.
- If `New-Object -ComObject Outlook.Application` fails, Outlook isn't available —
  report that rather than attempting Graph/web fallbacks.
- Don't expose full meeting bodies with sensitive content unless asked; summarize.
