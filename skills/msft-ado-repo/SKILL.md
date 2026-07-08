---
name: msft-ado-repo
description: >-
  Manage the full Azure DevOps repo lifecycle for @jimb's Microsoft work repo
  (default FDE_Revenue_Bedrock in org starlightagilebi / project AgBI): clone &
  onboard the repo under C:\Files\Dev\msft, create/confirm a linked work item
  FIRST (required), cut a feature branch named jimb/<tasknumber>/<task_title>,
  and open / update / complete PRs and check policy + build status via az repos /
  az boards (authed with the Git Credential Manager bearer token). The repo, org,
  project and paths are adjustable. Committing/pushing itself is handed off to
  git-ship. WHEN: "create an ADO branch", "start work on an ADO task", "new
  feature branch", "open an ADO PR", "create a pull request", "check PR status",
  "check PR policies", "create a work item", "link a work item", "clone the ADO
  repo", "set up the bedrock repo", "manage the ADO repo", "ADO repo lifecycle".
argument-hint: Optionally the task number, work-item title, and/or repo name
---

# msft-ado-repo — Azure DevOps repo lifecycle

End-to-end helper for @jimb's Microsoft **Azure DevOps** work: onboard the repo,
create a linked work item, branch, and manage PRs. This owns the *ADO plumbing*;
the actual **commit / push / deploy** is done by the **git-ship** skill — hand off
there once a branch exists and changes are staged.

## Config (defaults — all adjustable; confirm if the user names a different repo)

| Setting | Default |
|---|---|
| Org URL | `https://dev.azure.com/StarlightAgileBI` (aka `https://starlightagilebi.visualstudio.com`) |
| Project | `AgBI` |
| Repo | `FDE_Revenue_Bedrock` |
| Local path | `C:\Files\Dev\msft\FDE_Revenue_Bedrock` |
| Work-item **Area Path** | `AgBI\FDE\FDE FPA Revenue\FDE Revenue Bedrock` |
| Clone root | `C:\Files\Dev\msft` |

Set once per session so every `az` call can reuse them:
```powershell
$Org  = 'https://dev.azure.com/StarlightAgileBI'
$Proj = 'AgBI'
$Repo = 'FDE_Revenue_Bedrock'
$Area = 'AgBI\FDE\FDE FPA Revenue\FDE Revenue Bedrock'
$Local = 'C:\Files\Dev\msft\FDE_Revenue_Bedrock'
```

## Auth — reuse the Git Credential Manager token (never print it)

Same source as `Rebuild-OpenWorkItems.ps1`: pull the cached OAuth token for the
ADO host, then hand it to the `az devops` CLI as its PAT. **Do not echo the token.**
```powershell
$inp = "protocol=https`nhost=starlightagilebi.visualstudio.com`n`n"
$tok = ($inp | git credential fill 2>$null | Where-Object { $_ -match '^password=' }) -replace '^password=',''
if (-not $tok) { throw "No cached ADO credential. Run 'git fetch' against the repo once first." }
$env:AZURE_DEVOPS_EXT_PAT = $tok       # consumed by `az repos` / `az boards`
az devops configure --defaults organization=$Org project=$Proj 2>$null
```
**Verified 2026-07-08:** the GCM OAuth JWT is accepted as `AZURE_DEVOPS_EXT_PAT`
for `az repos`, `az boards`, and `az repos pr` against this org — no `az login` or
separate PAT needed. If a machine ever returns `TF400813 / unauthorized`, **fall
back to the REST API** with `Authorization = "Bearer $tok"` (the proven path in
`Rebuild-OpenWorkItems.ps1` and `git-ship`). Prefer `az`; use REST only if `az`
can't auth.

> **JSON-parsing gotcha (bit me in testing):** `az` prints a cp1252 encoding
> `WARNING:` to **stderr** on this machine. **Never** merge stderr into a JSON
> pipeline — `az ... -o json 2>&1 | ConvertFrom-Json` fails with "Unexpected
> character". Parse without `2>&1`:
> `$x = az repos pr list ... -o json | ConvertFrom-Json`.

## 1. Clone / onboard (only if the repo isn't already local)

```powershell
if (-not (Test-Path $Local)) {
  git -C C:\Files\Dev\msft clone "$Org/$Proj/_git/$Repo"
}
git -C $Local fetch --prune          # also primes the credential cache for auth above
```
Always clone under `C:\Files\Dev\msft` (never a temp dir) — @jimb's standing rule.

## 2. Work item is REQUIRED — create or confirm FIRST

**Every branch / PR must link a work item — no exceptions** (create one *before*
the branch so its number names the branch). If the user gave a task number, confirm
it exists; otherwise create one.

- **Ask the user for the work-item type each time** (Task / Bug / Product Backlog
  Item / …) — do not guess.
- Default the **Area Path** to `$Area` (and set Iteration to the team default unless
  told otherwise).

```powershell
# $Type from the user (e.g. 'Task'); returns the new id
$wi = az boards work-item create --title "<title>" --type "<Type>" `
        --org $Org --project $Proj --fields "System.AreaPath=$Area" -o json | ConvertFrom-Json
$TaskNum = $wi.id
```
Confirm an existing one instead:
```powershell
az boards work-item show --id <n> --org $Org -o json | ConvertFrom-Json |
  Select-Object -Expand fields | Select-Object 'System.Title','System.State','System.WorkItemType'
```

## 3. Feature branch — `jimb/<tasknumber>/<task_title>`

**Format: `jimb/<tasknumber>/<task_title>` — no `AB-` prefix; spaces become
underscores** (e.g. work item 455549 "Fix skill description length" →
`jimb/455549/Fix_skill_description_length`). Sanitize the title: replace spaces (and
other path-illegal chars) with `_`.
```powershell
$title = "<task title>"
$slug  = ($title -replace '[^\w.-]+','_').Trim('_')      # spaces/punct -> underscore
$Branch = "jimb/$TaskNum/$slug"
git -C $Local switch -c $Branch                          # branch off the up-to-date default branch
git -C $Local push -u origin $Branch
```
Branch off the repo's **default branch** (detect it, don't assume `main`):
```powershell
$Default = (az repos show --repository $Repo --org $Org --project $Proj -o json | ConvertFrom-Json).defaultBranch -replace '^refs/heads/',''
```
> Now hand off to **git-ship** for staging + the conventional-commit message
> (`type(scope): description`, work item linked in the body as `#<TaskNum>`, plus the
> `Co-authored-by: Copilot <…>` trailer).

## 4. Create the PR (sensible defaults)

```powershell
az repos pr create --org $Org --project $Proj --repository $Repo `
  --source-branch $Branch --target-branch $Default `
  --title "<PR title>" --description "<what & why>" `
  --work-items $TaskNum `                 # auto-links the work item
  --squash --delete-source-branch true `  # tidy merge + cleanup
  --auto-complete true `                  # completes once policies pass
  -o json | ConvertFrom-Json | Select-Object pullRequestId, @{n='url';e={"$Org/$Proj/_git/$Repo/pullrequest/$($_.pullRequestId)"}}
```
Add reviewers only if the user names them (`--reviewers <alias|email> …`); otherwise
leave branch-policy default reviewers to apply.

## 5. Manage & check status / policies

```powershell
# List active PRs, then filter to mine client-side (--creator wants a real
# identity, NOT @me). @jimb's UPN is jibrown@microsoft.com.
$prs = az repos pr list --org $Org --project $Proj --repository $Repo --status active -o json | ConvertFrom-Json
$prs | Where-Object { $_.createdBy.uniqueName -eq 'jibrown@microsoft.com' } | Select-Object pullRequestId, title, status
# Show one PR incl. status
az repos pr show --id <prId> --org $Org -o json | ConvertFrom-Json | Select-Object status, mergeStatus, isDraft
# Policy + build/branch-policy evaluations (the "will it merge" gate)
az repos pr policy list --id <prId> --org $Org -o table
# Update / set auto-complete / vote
az repos pr update --id <prId> --org $Org --auto-complete true
az repos pr set-vote --id <prId> --org $Org --vote approve
```

## Notes
- `az repos` / `az boards` need the **azure-devops** extension: `az extension add
  --name azure-devops` (once per machine).
- On @jimb's machine `az` streaming can crash client-side on a cp1252 char while the
  server op still succeeds — if a command "fails" mid-stream, re-query (`pr show` /
  `work-item show`) to confirm the real result before retrying.
- Keep `git-ship` as the single place for commit/push/deploy; this skill stops at
  "branch pushed" and "PR opened/managed".
