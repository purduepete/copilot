---
name: worklog-item-naming
description: >-
  Conventions for how WorkLog entries are worded: keep the item TITLE (the "Item"
  column) short and scannable, and put the detail/specifics in the ACCOMPLISHMENT
  field. When the user gives a long descriptive title, split it — concise title +
  detailed accomplishment. Both title AND accomplishment are mandatory — when logging
  mined work (vscode/session blocks) dig into the transcript to make both representative.
  WHEN: creating/starting/closing a WorkLog task, "the item column should be simpler",
  "shorten the title", "carry this over to the accomplishment", "make the title cleaner",
  "add accomplishments", "title isn't representative", "dig deeper", naming a task,
  writing an accomplishment.
argument-hint: e.g. "shorten item 3's title and move detail to accomplishment"
---

# WorkLog Item Naming & Accomplishment

How to word WorkLog entries so the dashboard stays scannable.

## The two fields, and what belongs where

| Field | Column | Holds | Style |
|---|---|---|---|
| **Title** | "Item" | The **what** — a short label for the task | A few words, scannable, no trailing detail |
| **Accomplishment** | (note/expander) | The **what was done** — specifics, sub-items, fixes | Longer; semicolon- or Markdown-separated list |

### Title (the "Item" column) — keep it simple

- Aim for a **short, scannable label** (~3–7 words). It's a heading, not a summary.
- **No** comma/semicolon laundry-lists, parentheticals, or "A; B; C; D" enumerations.
- Drop trailing detail — that goes in the accomplishment.
- Capitalize the first word (lowercase only for category/project).

❌ `WorkLog dashboard UX: shift-click date range, modal dialogs (replace native prompt/confirm), themed goal stepper, detached serve`
✅ `WorkLog dashboard UX improvements`

### Accomplishment — carry the detail here

- Move the specifics out of the title into the accomplishment.
- List the concrete things done, separated by `; ` (or Markdown bullets — the note
  modal renders basic Markdown).

✅ `Shift-click date-range selection on the calendar; replaced native prompt/confirm
with in-page themed modals; added a themed daily-goal stepper; serve now runs detached.`

## When the user gives a long title

If a `start`/`add` title is long and descriptive, **split it**: derive a concise
title and route the rest into `-Accomplishment`. For a running task, set/refine the
accomplishment when stopping (`stop "<accomplishment>"`) or via `edit`.

```powershell
# Tidy an existing entry: short title, detail to accomplishment
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 edit -Id <id> `
  -Title "WorkLog dashboard UX improvements" `
  -Accomplishment "Shift-click date-range selection; in-page modals replace native prompt/confirm; themed goal stepper; detached serve."
```

Resolve "item N" to its id positionally (Nth entry of the day) per the **worklog** skill.

## Both fields are mandatory — dig deeper for mined work

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
2. An **accomplishment** that lists the concrete things actually done across the block.

Then verify both persisted (read back via `search`/`log`), per the worklog skill's rule 4.

## Notes

- This complements the `worklog` skill's rule 1 (capitalization) — it governs *how
  much* goes in the title vs. the accomplishment.
- Prefer **one** well-formed accomplishment over many tiny task-notes.
