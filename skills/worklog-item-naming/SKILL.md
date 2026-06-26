---
name: worklog-item-naming
description: >-
  Conventions for how WorkLog entries are worded: keep the item TITLE (the "Item"
  column) short and scannable, and put the detail/specifics in the ACCOMPLISHMENT
  field. When the user gives a long descriptive title, split it — concise title +
  detailed accomplishment. WHEN: creating/starting/closing a WorkLog task, "the
  item column should be simpler", "shorten the title", "carry this over to the
  accomplishment", "make the title cleaner", naming a task, writing an accomplishment.
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

## Notes

- This complements the `worklog` skill's rule 1 (capitalization) — it governs *how
  much* goes in the title vs. the accomplishment.
- Prefer **one** well-formed accomplishment over many tiny task-notes.
