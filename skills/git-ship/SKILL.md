---
name: git-ship
description: >-
  Commit, push, and (when relevant) deploy @jimb's repo changes the careful way:
  stage the right files, write a structured commit message with the Co-authored-by
  trailer, and — BEFORE pushing worklog_web — warn whether the change will trigger
  the Azure Function deploy (per deploy.yml's paths filter) so a dev-script edit
  never deploys by surprise. WHEN: "commit", "commit and push", "commit/push/deploy",
  "ship it", "push this", "push my changes", "will this deploy".
argument-hint: Optionally the repo and/or a commit message
---

# git-ship — commit / push / deploy safely

@jimb's working repos live under `C:\Files\Dev\main\`: `worklog_web`, `copilot`,
`config`, `powershell`, `utility`, `work`. Only **worklog_web** has a deploy
pipeline; the rest are push-only.

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

## Notes
- Default branch is `main`; pushes go to `origin HEAD`.
- Never force-push or rewrite published history unless @jimb explicitly asks.
- Keep one logical change per commit; split unrelated edits into separate commits.
