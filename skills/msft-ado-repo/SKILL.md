---
name: msft-ado-repo
description: >-
  Manage an Azure DevOps repository: clone or onboard it, create a linked work
  item, branch, and manage pull requests and policy checks with az repos and az
  boards. Ask for the organization, project, repository, and local path when
  they are not known. WHEN: "create an ADO branch", "start work on an ADO task",
  "new feature branch", "open an ADO PR", "create a pull request", "check PR
  status", "check PR policies", "create a work item", "link a work item",
  "clone an ADO repo", "manage an ADO repo", "ADO repo lifecycle", "the PR is
  approved", "PR approved", "complete the PR", "merge the PR", "close the task".
argument-hint: Optionally the task number, work-item title, and/or repo name
---

# msft-ado-repo — Azure DevOps repo lifecycle

End-to-end helper for @jimb's Microsoft **Azure DevOps** work: onboard the repo,
create a linked work item, branch, and manage PRs. This owns the *ADO plumbing*;
the actual **commit / push / deploy** is done by the **git-ship** skill — hand off
there once a branch exists and changes are staged.

## Config

Ask for any missing values. Use the user's existing local checkout when available.

| Setting | Value |
|---|---|
| Org URL | User-provided organization URL |
| Project | User-provided project |
| Repo | User-provided repository |
| Local path | Existing checkout, or a user-approved path under `C:\Files\Dev\msft` |
| Work-item **Area Path** | User-provided team area path |

Set once per session so every `az` call can reuse them:
```powershell
$Org  = '<organization URL>'
$Proj = '<project>'
$Repo = '<repository>'
$Area = '<work-item area path>'
$Local = '<local checkout path>'
```

## Auth — reuse the Git Credential Manager token (never print it)

Pull the cached OAuth token for the ADO host, then hand it to the `az devops` CLI
as its PAT. **Do not echo the token.**
```powershell
$adoHost = ([uri]$Org).Host
$inp = "protocol=https`nhost=$adoHost`n`n"
$tok = ($inp | git credential fill 2>$null | Where-Object { $_ -match '^password=' }) -replace '^password=',''
if (-not $tok) { throw "No cached ADO credential. Run 'git fetch' against the repo once first." }
$env:AZURE_DEVOPS_EXT_PAT = $tok       # consumed by `az repos` / `az boards`
az devops configure --defaults organization=$Org project=$Proj 2>$null
```
If authentication fails, verify that Git Credential Manager has a credential for
the host in `$adoHost`. Keep the token in the process environment and never print it.

> **JSON-parsing gotcha (bit me in testing):** `az` prints a cp1252 encoding
> `WARNING:` to **stderr** on this machine. **Never** merge stderr into a JSON
> pipeline — `az ... -o json 2>&1 | ConvertFrom-Json` fails with "Unexpected
> character". Parse without `2>&1`:
> `$x = az repos pr list ... -o json | ConvertFrom-Json`.

## 1. Clone / onboard (only if the repo isn't already local)

```powershell
if (-not (Test-Path $Local)) {
  git clone "$Org/$Proj/_git/$Repo" $Local
}
git -C $Local fetch --prune          # also primes the credential cache for auth above
```
Use the local path supplied for this repository. For work repositories, use
`C:\Files\Dev\msft` rather than a temp directory.

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
  --squash --delete-source-branch false ` # Fabric branch gate controls deletion
  --auto-complete true `                  # completes once policies pass
  -o json | ConvertFrom-Json | Select-Object pullRequestId, @{n='url';e={"$Org/$Proj/_git/$Repo/pullrequest/$($_.pullRequestId)"}}
```
Use the target repository's branch policies and any reviewer requirements @jimb
specifies. Do not apply a preset reviewer list to every PR. When a reviewer must be
required, set `isRequired` to `true` through the REST API:

```text
PUT .../pullRequests/<id>/reviewers/<reviewerId>?api-version=7.1
{"isRequired": true, "id": "<reviewerId>"}
```

Verify the reviewer list and required flags with:

```powershell
az repos pr show --id <prId> --org $Org `
  --query "reviewers[].{name:displayName, required:isRequired}"
```

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
The CLI adds reviewers as optional. Set each required flag through the REST API and
verify it; branch policy does not replace this check.

## 6. Complete (merge) & close out — once approved

**When @jimb says the PR is approved** (e.g. "the PR's approved", "PR approved",
"complete/merge the PR"), that is the go-signal to run this whole close-out
**without re-asking**: merge the PR, delete the feature branch, and close the work
item. The PR must be approved and its policies green. Check the target repository's
instructions before deleting a source branch. Database changes need the independent
model review required by the global instructions.

```powershell
# Merge without automatic branch deletion so repository-specific cleanup can run.
az repos pr update --id <prId> --org $Org --status completed --squash true --delete-source-branch false | Out-Null
```
- **Completion is ASYNC** — `az` returns immediately with `mergeStatus=queued`.
  Re-query `az repos pr show --id <prId>` until `status=completed` /
  `mergeStatus=succeeded` (a `Start-Sleep 5-6` then re-check works).
- After `mergeStatus=succeeded`, delete the remote branch if the target repository's
  rules allow it. Confirm deletion with `git ls-remote origin <branch>` (empty = gone).
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

## PR review requirements

- Before opening a PR, lint changed Python with
  `python -m ruff check --no-cache --select S <changed paths>`. Clear findings
  or explain them in the PR. Ask the independent reviewer to check relevant
  OWASP vulnerability classes, not only correctness.
- Before creating a PR, generate and open a dark/light HTML review of the exact
  `origin/main...HEAD` diff. Show the branch, HEAD, local generation time,
  commit and file counts, review decision, validation, intent, and remaining
  work. Group all changed files by purpose and include each summary and its
  searchable, expandable patch. Add expand-all and collapse-all controls.
  Regenerate and reopen it whenever HEAD changes. Use the squared, dark-first
  indigo/violet style with Inter and Lucide-style stroke icons.
- Set a multi-line PR description through the REST API after creation:
  `PATCH .../pullRequests/<id>?api-version=7.1` with
  `{"description": "..."}`. Read it back and verify its length. Verify that
  `--work-items` attached the work item; attach it separately if the list is
  empty.
- After PR creation, check comment threads. The GitOps PR Assistant may rewrite
  the description and post a review. Re-read and restore the description if
  needed. Triage non-system review threads, including their severity.
- Proof of presence is @jimb's to complete. Never complete it for him. The
  method is Microsoft. If a PR requires it, tell him and stop.

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
