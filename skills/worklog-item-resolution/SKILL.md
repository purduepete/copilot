---
name: worklog-item-resolution
description: >-
  How to resolve a WorkLog "item N" / "task N" reference to a real session before
  acting on it (edit, stop, switch, tasknote, duplicate, delete): "item N" means
  the Nth entry of TODAY by start-time order, mapped to its actual global id — never
  fall back to a prior day, and if today has no entries treat the command as a no-op.
  WHEN: "delete item N", "edit item N", "stop item N", "item N with no date", "which
  day does item N mean", "delete task 1", "no day reference assume today".
argument-hint: the item/task number the user referenced
---

# Resolving WorkLog "item N" references

When the user says **"item N"** / **"task N"** (e.g. "delete item 1", "edit task 3")
without naming a date, resolve it carefully before acting — these verbs are
destructive or mutating, and `delete` reports success even for a nonexistent id.

## The rule

1. **No day reference = TODAY.** "item N" is the **Nth entry of today** in start-time
   order, counting from **1** — exactly the per-day `Id` shown on the web dashboard
   (which restarts at 1 each day and is **not** the WorkLog global id).
2. **Never fall back to another day.** If today has **no entries**, do **not** resolve
   "item N" against the most recent prior day. Treat the command as a **no-op** and tell
   the user there are no entries today to act on.
3. **A different day must be explicit.** Only resolve against another date when the user
   names one ("item 1 yesterday", "item 2 on 06/25").

> This was a real miss: with an empty today, "delete item 1" was wrongly resolved to the
> previous day's first entry and deleted it. The fix is rule 2 — empty today ⇒ no-op.

## How to resolve (when today has entries)

1. Read the active profile: `pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile`.
2. List recent entries and **filter to today's date**, sorted by start:
   `pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 log -Days 2`
   (`log -Days 1` can come back empty late in the day; use a small window and filter by
   today's date yourself). `status` shows `Logged today` — if it's `0m` and no open
   sessions, today is empty ⇒ rule 2 (no-op).
3. Map position **N** (1-based) among today's entries to that row's **actual global `Id`**.
4. Act on that global id: `delete -Id <id>`, `edit -Id <id> …`, `stop -Id <id> …`,
   `switch -Id <id>`, `tasknote -Id <id> …`.
5. **Verify the resolved id exists before deleting** — `delete` returns success even for a
   missing id, so never pass the raw position number straight through.

## Examples

```powershell
# "delete item 1" — today HAS entries: resolve today's 1st entry to its real id, then delete
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 log -Days 2   # filter to today, sort by start
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 delete -Id <resolvedTodayId>

# "delete item 1" — today has NO entries: do nothing, just report it
#   "There are no entries logged today, so there's no item 1 to delete."
```
