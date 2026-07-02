---
name: worklist
description: >-
  Regenerate @jimb's open work-item dashboards from live data as self-contained dark-theme
  HTML reports (grouped, sorted, client-side text filter). Two sources kept in the same
  look/feel: (ADO) "Open Azure DevOps Work Items" (open-work-items.html) — items assigned to
  @Me in org StarlightAgileBI, excluding Closed/Done/Removed/Resolved, grouped by Area →
  Status, sorted by ID; and (GITHUB) "Open GitHub Items" (open-github-items.html) — open
  issues across the user's repos (owner purduepete by default), grouped by repository,
  sorted by issue number.
  WHEN: "regenerate my ADO work item list", "refresh ADO work items", "rebuild
  open-work-items.html", "update my work item dashboard", "show my open ADO tasks", "what's
  assigned to me in ADO", "show my open GitHub items", "open GitHub issues report", "what's
  open on GitHub", "rebuild open-github-items.html", "regenerate my GitHub work list",
  "GitHub issues assigned to me", "any open issues in my repos".
argument-hint: source (ADO or GitHub) plus optional switches, e.g. "-NoOpen", "-AssignedToMe", "-Owner <name>", "-IncludePullRequests"
---

# Work-Item Lists

Rebuilds @jimb's local "open items" dashboards from live data. Two sources, one shared
look/feel (dark-theme HTML, grouped/sorted, client-side text filter). Pick the section for
the source the user asked about — resolve ambiguous phrasing ("my work list") by asking
which source, or regenerate both if they want everything.

Both output files and both generators live under `C:\Files\Dev\main\copilot\`.

---

## Part 1 — ADO work items

Rebuilds the dashboard of the user's open Azure DevOps work items.

### Primary action

Run the saved generator (≈4 s) — this is the canonical path:

```powershell
pwsh -File C:\Files\Dev\main\copilot\Rebuild-OpenWorkItems.ps1
```

Add `-NoOpen` to skip auto-launching the browser. Output is written to
`C:\Files\Dev\main\copilot\open-work-items.html`.

### How it works (for debugging / scope changes)

1. **Auth** — reuses the OAuth bearer token cached by Git Credential Manager for
   `starlightagilebi.visualstudio.com`. No separate login. If it fails ("No cached
   ADO credential"), run any `git fetch` against an ADO repo (e.g. under
   `C:\Files\Dev\msft\FDE_Revenue_Bedrock`) to refresh the token, then retry.
   Retrieve the token with:
   ```powershell
   $inp = "protocol=https`nhost=starlightagilebi.visualstudio.com`n`n"
   $tok = ($inp | git credential fill 2>$null | Where-Object { $_ -match '^password=' }) -replace '^password=',''
   ```
2. **Query (WIQL)** — `POST https://dev.azure.com/StarlightAgileBI/_apis/wit/wiql?api-version=7.1`:
   `SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed','Done','Removed','Resolved') ORDER BY [System.Id]`
3. **Details** — batch `GET /_apis/wit/workitems?ids=...&fields=System.Id,System.WorkItemType,System.State,System.Title,System.AreaPath,System.TeamProject,System.ChangedDate`.
4. **Render** — group by Area-path leaf → State, sort by id; dark-theme HTML with a
   client-side text filter.

### Scope is "assigned to @Me" by design

New items appearing in a team's area but **assigned to others** will NOT show — this
is intentional. If the user wants a broader view (whole area, any assignee, or an
extra assignee column), edit the WIQL in `Rebuild-OpenWorkItems.ps1` (e.g.
`[System.AreaPath] UNDER 'AgBI\FDE\FDE FPA Revenue\FDE Revenue Bedrock'`) and add an
assignee column to the row template. Confirm the desired scope before changing it.

### ADO notes

- The bearer token is short-lived; this only works while Git's cached credential is valid.
- Don't print the token. Treat it as a secret.

---

## Part 2 — GitHub items

Rebuilds a dashboard of the user's **open GitHub items** (issues) using the GitHub CLI.

### Primary action

Run the saved generator — this is the canonical path:

```powershell
pwsh -NoProfile -File C:\Files\Dev\main\copilot\Rebuild-OpenGitHubItems.ps1
```

Output is written to `C:\Files\Dev\main\copilot\open-github-items.html` and opened
in the browser. Add `-NoOpen` to skip launching it.

#### Useful switches

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

### How it works (for debugging / scope changes)

1. **Auth** — reuses the `gh` CLI login (`gh auth status`). No separate token.
   If it fails, run `gh auth login` once.
2. **Repos** — `gh repo list <owner> --limit 100 --json nameWithOwner`.
3. **Issues** — per repo: `gh issue list --repo <owner/repo> --state open --json
   number,title,url,assignees,labels,updatedAt`. PRs are filtered out unless
   `-IncludePullRequests` is set (a PR's `url` contains `/pull/`).
4. **Render** — group by repo, sort by number; dark-theme HTML (matches the ADO
   dashboard) with a client-side text filter and a friendly empty state when there
   are no open items.

### GitHub notes

- **`gh search issues` + `@me` is unreliable from PowerShell** (the `@me` token gets
  mangled into the query). Prefer the per-repo `gh issue list` loop the script uses.
- To link one of these issues to a time-tracked task, use the **worklog-link-github** skill.

---

## Keep the two dashboards in sync

The ADO and GitHub reports intentionally share the same dark-theme layout, grouping
style, and client-side filter. When you change the look/feel of one generator, apply the
same change to the other so they stay visually consistent.
