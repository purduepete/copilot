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
  repo", "set up the bedrock repo", "manage the ADO repo", "ADO repo lifecycle",
  "the PR is approved", "PR approved", "complete the PR", "merge the PR", "close
  the task".
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
- **Assign the work item to @jimb and set it Active** — new work items land as
  `New` and unassigned; @jimb wants them **assigned to `jimb@microsoft.com` and
  moved to `Active`** so they show on his open-work list and reflect that work has
  started. Do this on create (or immediately after) unless told otherwise.

```powershell
# $Type from the user (e.g. 'Task'); returns the new id — assigned + Active
$wi = az boards work-item create --title "<title>" --type "<Type>" `
        --org $Org --project $Proj `
        --fields "System.AreaPath=$Area" "System.AssignedTo=jimb@microsoft.com" `
        --open false -o json | ConvertFrom-Json
$TaskNum = $wi.id
az boards work-item update --id $TaskNum --org $Org --state "Active" | Out-Null
```
> `az boards work-item create` can't set `System.State` directly (it starts at the
> type's initial state, e.g. `New`), so **set `Active` in a follow-up
> `az boards work-item update`**. `AssignedTo` can be set on create via `--fields`.
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
  --reviewers "janayavaldes@microsoft.com" "srvoru@microsoft.com" "shaneolson@microsoft.com" `
  -o json | ConvertFrom-Json | Select-Object pullRequestId, @{n='url';e={"$Org/$Proj/_git/$Repo/pullrequest/$($_.pullRequestId)"}}
```
**Default approvers** for this repo (add unless @jimb says otherwise):
`janayavaldes@microsoft.com`, `srvoru@microsoft.com`, `shaneolson@microsoft.com`.
Add them on create via `--reviewers` (above), or to an existing PR:
```powershell
az repos pr reviewer add --id <prId> --org $Org `
  --reviewers "janayavaldes@microsoft.com" "srvoru@microsoft.com" "shaneolson@microsoft.com"
```
Add any extra reviewers @jimb names; branch-policy default/required reviewers still
apply on top.

## 5. Manage & check status / policies

```powershell
# List active PRs, then filter to mine client-side (--creator wants a real
# identity, NOT @me). @jimb's UPN is jimb@microsoft.com.
$prs = az repos pr list --org $Org --project $Proj --repository $Repo --status active -o json | ConvertFrom-Json
$prs | Where-Object { $_.createdBy.uniqueName -eq 'jimb@microsoft.com' } | Select-Object pullRequestId, title, status
# Show one PR incl. status
az repos pr show --id <prId> --org $Org -o json | ConvertFrom-Json | Select-Object status, mergeStatus, isDraft
# Policy + build/branch-policy evaluations (the "will it merge" gate)
az repos pr policy list --id <prId> --org $Org -o table
# Update / set auto-complete / vote
az repos pr update --id <prId> --org $Org --auto-complete true
az repos pr set-vote --id <prId> --org $Org --vote approve
```
Add reviewers to an **existing** PR (e.g. the default approvers) with
`az repos pr reviewer add --id <prId> --org $Org --reviewers <a> <b> <c>` — they land
as **optional** reviewers (`isRequired` is blank); required reviewers come from branch
policy, not this flag.

## 6. Complete (merge) & close out — once approved

**When @jimb says the PR is approved** (e.g. "the PR's approved", "PR approved",
"complete/merge the PR"), that is the go-signal to run this whole close-out
**without re-asking**: merge the PR, delete the feature branch, and close the work
item. Only precondition: the PR is approved and policies are green. DB/schema-
affecting changes still need a Gemini second opinion first (@jimb's standing rule) —
not relevant to doc/skill PRs.

### Fabric branch deletion gate

Before deleting any remote Bedrock branch, check whether a Fabric developer
workspace is connected to it. For @jimb, resolve the exact workspace display name
`FDE_Bedrock_Engine_jimb`, then read:

```text
GET /v1/workspaces/{workspaceId}/git/connection
GET /v1/workspaces/{workspaceId}/git/status
```

If the connection names the branch being deleted:

1. Refuse deletion when either Fabric read returns any non-200 response (including
   `GitProviderResourceNotFound`, timeout, 404, or 5xx) or any workspace-side change exists.
2. Switch the existing connection to `main` without disconnecting the workspace. There is
   no verified REST endpoint for this operation in the current tooling: ask the user to switch
   it in **Fabric → Workspace settings → Git integration**, then stop until they confirm.
   Never improvise with `PATCH /git/connection`, and never disconnect/reconnect a branched
   workspace.
3. Run `updateFromGit` for the current remote `main` commit.
4. Verify the connection names `main`, workspace and remote heads match, and workspace-side
   changes are empty.
5. Only then delete the remote branch.

This gate also applies to manual cleanup requests outside PR completion. Never delete a
branch first and assume Fabric will recover. A deleted connected branch leaves the
workspace metadata on a missing ref and makes `git/status` return
`GitProviderResourceNotFound`.

```powershell
# Merge without automatic branch deletion.
az repos pr update --id <prId> --org $Org --status completed --squash true --delete-source-branch false | Out-Null
```
- **Completion is ASYNC** — `az` returns immediately with `mergeStatus=queued`.
  Re-query `az repos pr show --id <prId>` until `status=completed` /
  `mergeStatus=succeeded` (a `Start-Sleep 5-6` then re-check works).
- Run the Fabric branch deletion gate only after `mergeStatus=succeeded` is confirmed.
- After the Fabric gate passes, delete the remote branch explicitly with
  `git push origin --delete <branch>`, then confirm with `git ls-remote origin <branch>`
  (empty = gone).
- **Close the work item** (state names vary by type; Task/Bug use `Closed`):
  ```powershell
  az boards work-item update --id $TaskNum --org $Org --state "Closed" | Out-Null
  ```
- **Local cleanup** — the remote branch is gone but the local copy and its tracking
  ref remain:
  ```powershell
  git -C $Local switch main
  git -C $Local pull --ff-only
  git -C $Local branch -D <branch>
  git -C $Local fetch --prune
  ```

## Notes
- `az repos` / `az boards` need the **azure-devops** extension: `az extension add
  --name azure-devops` (once per machine).
- On @jimb's machine `az` streaming can crash client-side on a cp1252 char while the
  server op still succeeds — if a command "fails" mid-stream, re-query (`pr show` /
  `work-item show`) to confirm the real result before retrying.
- **A PR can be abandoned out-of-band** (by a person or policy). It then drops off
  `az repos pr list --status active` and `pr show` reports `status=abandoned`. The
  branch/commits are untouched — either reactivate (`az repos pr update --id <id>
  --status active`) or just open a fresh PR from the same branch (re-add reviewers +
  `--work-items`). Check the current status before assuming a PR is still live.
- Keep `git-ship` as the single place for commit/push/deploy; this skill owns the ADO
  plumbing from "branch pushed" through "PR merged + work item closed".
