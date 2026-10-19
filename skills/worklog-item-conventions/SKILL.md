---
name: worklog-item-conventions
description: >-
  Resolve a WorkLog "item N" or "task N" as today's Nth entry by start time, mapped to its
  global id. Never fall back to a prior day; an empty day is a no-op. Keep item titles short
  and put concrete detail in an accomplishment, including for mined work. WHEN: creating,
  starting, stopping, or editing a WorkLog task; naming a task; writing an accomplishment;
  "shorten the title", "add accomplishments", "delete item N", "edit item N", "stop item N",
  "item N with no date", "which day does item N mean", "delete task 1".
argument-hint: the item/task number and/or the wording change (e.g. "shorten item 3's title and move detail to accomplishment")
---

# WorkLog Item Conventions

Two closely-related conventions for working with WorkLog entries: how to **resolve** an
"item N" reference to a real session, and how to **word** the entry once you have it.

---

## Part 1 — Resolving "item N" references

When the user says **"item N"** / **"task N"** (e.g. "delete item 1", "edit task 3")
without naming a date, resolve it carefully before acting — these verbs are
destructive or mutating, and `delete` reports success even for a nonexistent id.

### The rule

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

### How to resolve (when today has entries)

1. Read the active profile: `pwsh -File C:\Files\Dev\main\work-log\cli\wl.ps1 profile`.
2. List recent entries and **filter to today's date**, sorted by start:
   `pwsh -File C:\Files\Dev\main\work-log\cli\wl.ps1 log -Days 2`
   (`log -Days 1` can come back empty late in the day; use a small window and filter by
   today's date yourself). `status` shows `Logged today` — if it's `0m` and no open
   sessions, today is empty ⇒ rule 2 (no-op).
3. Map position **N** (1-based) among today's entries to that row's **actual global `Id`**.
4. Act on that global id: `delete -Id <id>`, `edit -Id <id> …`, `stop -Id <id> …`,
   `switch -Id <id>`, `tasknote -Id <id> …`.
5. **Verify the resolved id exists before deleting** — `delete` returns success even for a
   missing id, so never pass the raw position number straight through.

### Examples

```powershell
# "delete item 1" — today HAS entries: resolve today's 1st entry to its real id, then delete
pwsh -File C:\Files\Dev\main\work-log\cli\wl.ps1 log -Days 2   # filter to today, sort by start
pwsh -File C:\Files\Dev\main\work-log\cli\wl.ps1 delete -Id <resolvedTodayId>

# "delete item 1" — today has NO entries: do nothing, just report it
#   "There are no entries logged today, so there's no item 1 to delete."
```

---

## Part 2 — Item naming & accomplishment

How to word WorkLog entries so the dashboard stays scannable.

### The two fields, and what belongs where

| Field | Column | Holds | Style |
|---|---|---|---|
| **Title** | "Item" | The **what** — a short label for the task | A few words, scannable, no trailing detail |
| **Accomplishment** | (note/expander) | The **what was done** — specifics, sub-items, fixes | **Concise**; the key things done, tersely worded |

#### Title (the "Item" column) — keep it simple

- Aim for a **short, scannable label** (~3–7 words). It's a heading, not a summary.
- **No** comma/semicolon laundry-lists, parentheticals, or "A; B; C; D" enumerations.
- Drop trailing detail — that goes in the accomplishment.
- Capitalize the first word (lowercase only for category/project).

❌ `WorkLog dashboard UX: shift-click date range, modal dialogs (replace native prompt/confirm), themed goal stepper, detached serve`
✅ `WorkLog dashboard UX improvements`

#### Accomplishment — carry the detail here, but keep it tight

- Move the specifics out of the title into the accomplishment.
- **Be concise.** Aim for roughly a third of the length you'd naturally write —
  name the key things done, drop the narration, restatement, and filler.
- List the concrete things done, separated by `; ` (or Markdown bullets — the note
  modal renders basic Markdown).

✅ `Shift-click date-range selection; in-page themed modals replace prompt/confirm;
themed goal stepper; detached serve.`

### When the user gives a long title

If a `start`/`add` title is long and descriptive, **split it**: derive a concise
title and route the rest into `-Accomplishment`. For a running task, set/refine the
accomplishment when stopping (`stop "<accomplishment>"`) or via `edit`.

```powershell
# Tidy an existing entry: short title, detail to accomplishment
pwsh -File C:\Files\Dev\main\work-log\cli\wl.ps1 edit -Id <id> `
  -Title "WorkLog dashboard UX improvements" `
  -Accomplishment "Shift-click date-range selection; in-page modals replace native prompt/confirm; themed goal stepper; detached serve."
```

Resolve "item N" to its id positionally (Nth entry of the day) per **Part 1** above.

### Both fields are mandatory — dig deeper for mined work

Every entry needs **both** a representative title **and** an accomplishment — never
ship a title-only entry.

**The only exemptions** (an accomplishment is *not* required) are non-work / idle
entries:

- **Lunch** (and other breaks worded as such), and
- any entry whose **project is `n/a`** (e.g. "Away from work", breaks, idle time).

Start-of-day / end-of-day markers are also exempt (they carry no project and no
accomplishment by design). **Every other entry** — anything with a real project —
**must** have an accomplishment; if it's missing, fill it in (mine the transcript
if needed) before closing the entry or the day.

The miners (`Get-VSCodeWork.ps1` / `Get-CopilotWork.ps1`)
default the title to the block's *first* message and set **no** accomplishment, which
is almost never representative of the whole block.

When logging (or fixing up) a mined block, **read the underlying transcript** before
wording the entry — don't trust the first/last snippet:

- VS Code: `%APPDATA%\Code\User\workspaceStorage\<hash>\GitHub.copilot-chat\transcripts\*.jsonl`
  (the hash is the one the miner maps the folder to). Pull `user.message` events
  (`$o.data.content`) across the block's time window — a block can span multiple
  transcript files.
- Copilot CLI: `~/.copilot/session-state/*/events.jsonl` (`user.message` events).

Scan **all** the user messages, identify the recurring themes, and write:

1. A short, scannable **title** covering the dominant theme (split if multi-theme).
2. An **accomplishment** that tersely names the concrete things actually done
   across the block — concise, not a narrative.

Then verify both persisted (read back via `search`/`log`), per the worklog skill's rule 4.

### Notes

- This complements the `worklog` skill's rule 1 (capitalization) — it governs *how
  much* goes in the title vs. the accomplishment.
- Prefer **one** well-formed accomplishment over many tiny task-notes.
