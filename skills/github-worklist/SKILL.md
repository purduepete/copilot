---
name: github-worklist
description: >-
  Regenerate the user's "Open GitHub Items" dashboard (open-github-items.html)
  from live GitHub data via the gh CLI — open issues across the user's repos
  (owner purduepete by default), grouped by repository, sorted by issue number,
  each linking to the issue on GitHub. WHEN: "show my open GitHub items", "open
  GitHub issues report", "what's open on GitHub", "rebuild open-github-items.html",
  "regenerate my GitHub work list", "GitHub issues assigned to me", "any open
  issues in my repos".
argument-hint: Optionally "-AssignedToMe", "-Owner <name>", "-IncludePullRequests", or "-NoOpen"
---

# GitHub Work-Item List

Rebuilds a local dashboard of the user's **open GitHub items** (issues) using the
GitHub CLI.

## Primary action

Run the saved generator — this is the canonical path:

```powershell
pwsh -NoProfile -File C:\Files\Dev\main\copilot\Rebuild-OpenGitHubItems.ps1
```

Output is written to `C:\Files\Dev\main\copilot\open-github-items.html` and opened
in the browser. Add `-NoOpen` to skip launching it.

### Useful switches

| Switch | Effect |
|---|---|
| `-AssignedToMe` | Only issues assigned to the authenticated gh user |
| `-Owner <name>` | Scan a different owner/org (default `purduepete`) |
| `-IncludePullRequests` | Also include open PRs (issues-only by default) |
| `-NoOpen` | Don't auto-open the browser |

```powershell
# Only what's assigned to me, no browser pop
pwsh -NoProfile -File C:\Files\Dev\main\copilot\Rebuild-OpenGitHubItems.ps1 -AssignedToMe -NoOpen
```

## How it works (for debugging / scope changes)

1. **Auth** — reuses the `gh` CLI login (`gh auth status`). No separate token.
   If it fails, run `gh auth login` once.
2. **Repos** — `gh repo list <owner> --limit 100 --json nameWithOwner`.
3. **Issues** — per repo: `gh issue list --repo <owner/repo> --state open --json
   number,title,url,assignees,labels,updatedAt`. PRs are filtered out unless
   `-IncludePullRequests` is set (a PR's `url` contains `/pull/`).
4. **Render** — group by repo, sort by number; dark-theme HTML (matches the ADO
   dashboard) with a client-side text filter and a friendly empty state when there
   are no open items.

## Notes

- **`gh search issues` + `@me` is unreliable from PowerShell** (the `@me` token gets
  mangled into the query). Prefer the per-repo `gh issue list` loop the script uses.
- This is the GitHub sibling of the `ado-worklist` skill — keep their look/feel in sync.
- To link one of these issues to a time-tracked task, use the **worklog-link-github** skill.
