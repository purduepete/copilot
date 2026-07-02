---
name: git-ship
description: >-
  Commit, push, and (when relevant) deploy @jimb's repo changes the careful way:
  stage the right files, write a structured commit message with the Co-authored-by
  trailer, and — BEFORE pushing worklog_web — warn whether the change will trigger
  the Azure Function deploy (per deploy.yml's paths filter) so a dev-script edit
  never deploys by surprise. For the ADO repo (FDE_Revenue_Bedrock) a linked work
  item is REQUIRED: create/confirm an ADO work item first, branch + commit + PR
  reference it (AB-<id> / AB#<id>). WHEN: "commit", "commit and push",
  "commit/push/deploy", "ship it", "push this", "push my changes", "will this
  deploy", "open a PR", "create a branch", "create a work item".
argument-hint: Optionally the repo and/or a commit message
---

# git-ship — commit / push / deploy safely

@jimb's working repos live under `C:\Files\Dev\main\`: `worklog_web`, `copilot`,
`config`, `powershell`, `utility`, `work` (GitHub, push-only except worklog_web,
which deploys). A separate **Azure DevOps** repo lives at
`C:\Files\Dev\msft\FDE_Revenue_Bedrock` (org `starlightagilebi`, project `AgBI`)
— it has its **own rules** (see "ADO repo" below); only **worklog_web** has a
deploy pipeline.

## Steps

### 1. See what changed and stage deliberately
```powershell
cd C:\Files\Dev\main\<repo>
git status --short
git --no-pager diff --stat
```
Stage only files that belong to **this** change. Do **not** `git add -A` blindly
when unrelated edits are present — ask which scope to ship if it's ambiguous.

### 2. Write a structured commit message
- **Subject:** imperative mood, <= 72 chars ("Add X", "Fix Y" — not "Added"/"Fixes").
- **Body:** explain *why*, not just *what* (wrap ~72 cols). Optional for trivial changes.
- **Always append** the trailer (unless @jimb says not to):
  ```
  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
  ```
```powershell
git commit -q -m "Imperative subject" -m "Why this change exists." -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### 3. ⚠️ Deploy gate (worklog_web ONLY) — do this BEFORE pushing
`worklog_web\.github\workflows\deploy.yml` deploys the Function app on push to
`main` when the changed paths match its filter:
- `api/**`
- `infra/**`
- `.github/workflows/deploy.yml`
- `src/WorkLogStore.psm1`
- `src/WorkLog.psm1`
- `src/worklog.config.json`

Check the staged paths against that list:
```powershell
git diff --cached --name-only
```
- **If any staged path matches** → tell @jimb **"this WILL deploy the Function app"**
  and get explicit confirmation before pushing.
- **If none match** (e.g. only `src/*.ps1` dev scripts, `cli/**`, docs) → note
  **"dev-only, no deploy"** and proceed.

Everything in `src/` EXCEPT the three bundled modules above is a dev-only script
and must never be added back into the deploy `paths:` filter.

### 4. Push and report
```powershell
git push -q origin HEAD 2>&1 | Select-Object -Last 3
"pushed $(git rev-parse --short HEAD)"
```
Report the **short SHA**. For worklog_web, if the change was deploy-eligible,
confirm a run actually started (and only then):
```powershell
gh run list --limit 1 --json status,headSha,workflowName 2>$null
```

## `gh` auth gotcha (purduepete repos)
`git push` uses the stored **purduepete** credential, but `gh` is authed as
**jimb_microsoft**, which can't see private purduepete repos. Before ANY `gh`
API call (run list, issue, pr), source the purduepete token first:
```powershell
$cred = "protocol=https`nhost=github.com`n" | git credential fill 2>$null
$env:GH_TOKEN = ($cred | Select-String '^password=').ToString().Substring(9)
```

## utility repo — "ship it" ALSO means publish

For `C:\Files\Dev\main\utility` (the Jimler/WinUtility apps), shipping isn't done
at `git push` — the live apps are elevated installed copies in `exe\`, so a push
alone changes nothing on the machine. After the commit + push, **also publish (as a
release) and relaunch**. Here "publish" means cut a **gh release** (not `-NoRelease`):
```powershell
cd C:\Files\Dev\main\utility
.\Scripts\Publish.ps1 -ReleaseNote "<what changed>"   # stops the 4 procs, republishes Release to exe\, bumps <Version>, cuts a gh release
Start-ScheduledTask -TaskName WinUtility               # OR: Start-Process exe\WinUtility.exe (auto-elevates via UAC)
```
- **"ship it" for utility ⇒ a full release**: run with `-ReleaseNote "..."` (implies
  `-Release`, so it publishes a `gh` release). Only use `-NoRelease` when @jimb is
  merely testing locally and explicitly says "no release".
- **"debug release" ⇒ `-NoRelease`**: republish to `exe\` + relaunch WITHOUT cutting
  a `gh` release (local-only install). Use this phrasing to skip the release.
- `Publish.ps1` auto-bumps `WinUtility/WinUtility.csproj` `<Version>`; that bump is
  part of the same change, so stage + commit it together with the code fix.
- **Elevation:** relaunch does NOT need an elevated shell — `exe\WinUtility.exe` has a
  **RUNASADMIN** AppCompat layer, so `Start-Process`/the task auto-elevate it (and the
  trio it spawns) via UAC. Elevation is only needed for `Publish.ps1`'s `Stop-Process`
  step **when elevated instances are already running** (a Medium shell can't kill them,
  and their running exes stay locked so `dotnet publish` can't overwrite). If the apps
  aren't running, a non-elevated Publish works fine. See **jimler-utility-run** for the
  full why/how.

## ADO repo — FDE_Revenue_Bedrock (org `starlightagilebi`, project `AgBI`)

Path: `C:\Files\Dev\msft\FDE_Revenue_Bedrock`. This repo follows its own
`.github/copilot-instructions.md`. The non-negotiable extras vs the GitHub repos:

### A work item is REQUIRED (do this FIRST)
**Every branch / commit / PR here must link an ADO work item — no exceptions.**
Before creating the branch, **create or confirm a work item** and capture its id.
Create one via the REST API (auth = the **git credential Bearer token**, see below):
```powershell
$wi = @(@{ op="add"; path="/fields/System.Title"; value="<title>" }) | ConvertTo-Json
# work item type goes in the URL ($type below, e.g. Task / Bug); ask @jimb if unsure
Invoke-RestMethod -Method Post -Headers (@{ Authorization="Bearer $pw"; 'Content-Type'='application/json-patch+json' }) `
  -Uri "https://starlightagilebi.visualstudio.com/AgBI/_apis/wit/workitems/`$$type?api-version=7.0" -Body $wi
```
Confirm the **type** with @jimb if not given (don't guess silently).

### Branch naming (enforced)
```
<author>/AB-<id>/<short-kebab-description>     # author=jimb; description may start with a verb (fix-, add-, ...)
```
e.g. `jimb/AB-455549/fix-skill-description-length`. Three segments only —
**no separate type segment**. (A branch without the `AB-<id>` is allowed ONLY
when @jimb explicitly says there's no work item.)
> Note: the repo's `.github/copilot-instructions.md` documents a 4-segment
> `<author>/AB-<id>/<type>/<desc>` form; @jimb's standing preference is the
> 3-segment form above — follow it unless @jimb says otherwise.

### Commit messages (conventional commits)
`type(scope): description`, and link the work item in the body with **`AB#<id>`**.
Still append the `Co-authored-by: Copilot <…>` trailer.

### Open the PR via REST (not gh — this is ADO, not GitHub)
`az` tokens are usually a **different identity that 401s** on this org — use the
**git credential token as a Bearer** instead:
```powershell
$cred = "protocol=https`nhost=starlightagilebi.visualstudio.com`n`n" | git credential fill 2>$null
$pw = (($cred | Select-String '^password=').ToString()).Substring(9)   # this is the token
$body = @{ sourceRefName="refs/heads/<branch>"; targetRefName="refs/heads/main"
  title="<conventional title>"; description="<why> AB#<id>" } | ConvertTo-Json
$r = Invoke-RestMethod -Method Post -Headers (@{ Authorization="Bearer $pw"; 'Content-Type'='application/json' }) `
  -Uri "https://starlightagilebi.visualstudio.com/AgBI/_apis/git/repositories/FDE_Revenue_Bedrock/pullrequests?api-version=7.0" -Body $body
Start-Process "https://starlightagilebi.visualstudio.com/AgBI/_git/FDE_Revenue_Bedrock/pullrequest/$($r.pullRequestId)"
```
Then link the work item to the PR (artifact link) so the AB-<id> trail is complete.

## Notes
- Default branch is `main`; pushes go to `origin HEAD`.
- Never force-push or rewrite published history unless @jimb explicitly asks.
- Keep one logical change per commit; split unrelated edits into separate commits.
