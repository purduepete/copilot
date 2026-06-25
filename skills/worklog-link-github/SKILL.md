---
name: worklog-link-github
description: >-
  Link a GitHub issue/PR to a WorkLog item as a clickable, markdown-linked task
  note (and optionally close the issue). Finds the matching issue when the user
  doesn't give a number, then attaches "[#N Title](url)" with state + milestone.
  WHEN: "add the GitHub task to item N", "link this task to its GitHub issue",
  "there is a gh task for it, add it as a task note", "attach issue #N to my
  worklog task", "close the issue when I close this task".
argument-hint: e.g. "link item 2 to webbookmarks #6" or "add the gh task to item 3"
---

# Link a GitHub Item to a WorkLog Task

Attaches a GitHub issue/PR to a time-tracked WorkLog session as a **clickable
markdown link**, so it renders as a real link in the dashboard note modal.

## Resolve the target task first

"Item N" / "task N" is the **Nth entry of the day** (positional, start-time order,
counting from 1) — **not** the WorkLog id. Resolve it via `Work.ps1 log -Days 1`,
filter to the date, sort by start, map position N → its real id. Don't ask the user
which item N is — figure it out.

## Find the GitHub item (when no number is given)

If the user says "there is a gh task for it" without a number, locate it:

1. Read the task's title/accomplishment from `work-log.json` for context.
2. Identify the repo (default owner `purduepete`; ask only if genuinely unknown).
3. Match by **commit history** and **title**:
   ```powershell
   gh api repos/<owner>/<repo>/commits --jq '.[0:10][] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
   gh issue list --repo <owner>/<repo> --state all --json number,title,url,state,milestone
   ```
   A release/commit whose message matches an issue title (e.g. a `v4.9.20` bump
   commit sitting right after a "Prioritize favorites…" commit ⇒ issue #6) is the link.
4. State which issue you picked so the user can correct it.

## Attach it as a markdown-linked task note

Use **`tasknote`** with a Markdown link (the dashboard renders `[text](url)`):

```powershell
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 tasknote `
  "GitHub: [#6 Prioritize favorites in command palette fuzzy search](https://github.com/purduepete/webbookmarks/issues/6) — state: closed" `
  -Id <resolvedId>
```

- **Always use a Markdown link** `[#N Title](url)` — never a bare URL (it won't be
  clickable in the note modal).
- Include **state** (open/closed) and, if present, **milestone**. Prefer **one**
  Markdown note over several small ones.

## When the task is being closed at the same time

If the user is closing the WorkLog item *and* wants the GitHub issue closed, do it in
one call instead of a separate note:

```powershell
pwsh -File C:\Files\Dev\main\copilot\worklog\Work.ps1 close "<accomplishment>" `
  -Id <resolvedId> -Issue <N> -RepoPath C:\Files\Dev\main\<repo> -CloseIssue
```

`close` bundles the gh-issue note + stop + a single dashboard rebuild.

## Verify

After writing, confirm the note landed on the right session:

```powershell
$j = Get-Content C:\Files\Dev\main\copilot\worklog\data\<profile>\work-log.json -Raw | ConvertFrom-Json
($j.sessions | Where-Object { $_.id -eq <resolvedId> }).notes
```

See the **worklog** skill for the full Work.ps1 command set and the **github-worklist**
skill to discover open issues to link.
