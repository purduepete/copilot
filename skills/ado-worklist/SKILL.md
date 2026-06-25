---
name: ado-worklist
description: >-
  Regenerate the user's "Open Azure DevOps Work Items" dashboard
  (open-work-items.html) from live ADO data — items assigned to @Me in org
  StarlightAgileBI, excluding Closed/Done/Removed/Resolved, grouped by Area →
  Status, sorted by ID. WHEN: "regenerate my ADO work item list", refresh ADO
  work items, rebuild open-work-items.html, update my work item dashboard, show
  my open ADO tasks, what's assigned to me in ADO.
argument-hint: Optionally pass "-NoOpen" to skip opening the browser
---

# ADO Work-Item List

Rebuilds the local dashboard of the user's open Azure DevOps work items.

## Primary action

Run the saved generator (≈4 s) — this is the canonical path:

```powershell
pwsh -File C:\Files\Dev\main\copilot\Rebuild-OpenWorkItems.ps1
```

Add `-NoOpen` to skip auto-launching the browser. Output is written to
`C:\Files\Dev\main\copilot\open-work-items.html`.

## How it works (for debugging / scope changes)

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

## Scope is "assigned to @Me" by design

New items appearing in a team's area but **assigned to others** will NOT show — this
is intentional. If the user wants a broader view (whole area, any assignee, or an
extra assignee column), edit the WIQL in `Rebuild-OpenWorkItems.ps1` (e.g.
`[System.AreaPath] UNDER 'AgBI\FDE\FDE FPA Revenue\FDE Revenue Bedrock'`) and add an
assignee column to the row template. Confirm the desired scope before changing it.

## Notes

- The bearer token is short-lived; this only works while Git's cached credential is valid.
- Don't print the token. Treat it as a secret.
