---
applyTo: '**'
description: "@jimb's global workflow, tooling, and review preferences. Apply in every repository."
---

# Personal global Copilot instructions (@purduepete)

Shared across **all** repositories and machines. The canonical copy lives in the
`copilot` repo at `global-instructions\personal.instructions.md`. Edit here,
commit/push, then update the instruction location configured on other machines.
Repo-specific rules still belong in each repo's
`.github/copilot-instructions.md`, which take precedence for that repo.

## Preferences

- When cloning source/solution repos for analysis, clone them under
  `C:\Files\Dev\msft` (not a temp directory). On the work computer, new repos are
  most often written to `C:\Files\Dev\msft`.
- Treat the WorkLog category alias `dev` as `development`.
- When @jimb says "commit," interpret it as commit and push by default. Commit only when he
  explicitly says not to push or asks to keep the commit local.
- **VS Code Marketplace publisher is `lerxst`.** Set `"publisher": "lerxst"` in any
  extension `package.json`, and publish with `npx @vscode/vsce login lerxst` then
  `npx @vscode/vsce publish`. My GitHub account is `purduepete` and is unrelated to the
  marketplace publisher, so `repository`/`bugs`/`homepage` URLs still point at
  `github.com/purduepete/...`. The marketplace PAT comes from Azure DevOps with
  **All accessible organizations** and the **Marketplace > Manage** scope. Never ask me
  for the token in chat or put it in a command; I enter it at the `vsce login` prompt.
- **Always display times in my local time zone**, never UTC. When a data source
  stores timestamps in UTC (e.g. the Copilot session store's `created_at`), convert
  to local time before showing them, and label them as local.
- **Anything that alters a database** (schema migrations, data-fix scripts, or any
  write/DDL against a live DB) **requires an independent model review** before it is
  run. Use the validation models below, then proceed (see `## Models`). **WorkLog is
  exempt for routine writes** (`start`, `stop`, `add`, `edit`, day markers, summaries,
  and notes); only an explicit WorkLog deletion/removal requires review.

## Models

When I want a **second opinion, accuracy review, or cross-check**, invoke a review
sub-agent with a model override, not a separate external CLI. **The reviewer must
come from a different model family/provider than the primary model** so it is less
likely to repeat the same assumptions: GPT/ChatGPT primary → Claude or Gemini;
Claude primary → GPT/ChatGPT or Gemini; Gemini primary → GPT/ChatGPT or Claude.

- **Claude Sonnet 5** (`Claude Sonnet 5 (copilot)`): Anthropic model for every
  independent review when the primary model is not Claude, including routine checks,
  code review, architecture, and higher-stakes validation.
- **Gemini 3.5 Flash** (`gemini-3.5-flash`): fast validation when the primary model
  is Claude, and large-context reading.

A narrow validation gets 60 seconds. Ask for a verdict from the supplied evidence
without extra investigation or tool calls. If it has not returned after 60 seconds,
request an immediate verdict and stop waiting.

Never use the same model family as the primary for an independent review, including
routine checks.

When 2 or more independent reviews are requested, every reviewer must also come from
a different model family/provider than every other reviewer. Different variants from
one family do not count as independent families: Sonnet plus Opus counts as Claude,
and two GPT versions count as GPT. For two reviews, route GPT primary to Claude plus
Gemini, Claude primary to GPT plus Gemini, and Gemini primary to GPT plus Claude.
Record the exact model and verdict for every validation.

The `## Preferences` rule for DB-altering changes is satisfied by an independent
review from Claude Sonnet 5 or Gemini 3.5 Flash, subject to the model-family rule
above.

### Route cheap work to a cheap model

Don't burn a premium model on a task that doesn't need one. You **cannot** change your
own model mid-session (only I can, via `/model`), but you *can* delegate the expensive
part: hand the bulk reading to a sub-agent with a `model` override and spend premium
tokens only on the final synthesis.

| Kind of work | Model |
|---|---|
| Read-only Q&A, doc/repo lookups, summarizing existing files, "what does X say / where does Y live" | Delegate to `explore`, or a `task` sub-agent overridden to `gemini-3.5-flash` / `gpt-5.4-mini` |
| Code changes, debugging, architecture & design judgment, PR review, anything touching a live DB | Keep the premium model |

Rule of thumb: if the task is read-only, the answer already exists in docs or config,
and no cross-file reasoning about *behavior* is required, delegate it. Producing a
substantial artifact from what was read (e.g. a themed HTML report) still justifies the
premium model for that step. When it's genuinely borderline, delegate and check the
result rather than defaulting to expensive.

## Long-running jobs: the 5-minute rule

Written after a **2.5-hour stall** (2026-08-09): a Spark diff was launched through a
runner that printed nothing until completion, on a session Fabric had silently sized at
**1 executor / 8 cores** while the job it validated ran on **384 cores**. It was only
caught because I asked. Wasted time is unaffordable. These are hard rules, not
suggestions.

**Before launching anything expected to take >5 minutes:**

1. **State an estimate and an abort threshold, out loud, before starting.**
   "I expect this to take ~4 min; if it passes 12 min (3×) I will stop and diagnose."
   Without a pre-declared number there is nothing to notice a breach against.
2. **Verify the resources actually granted match what was requested.** Cloud schedulers
   silently downsize. Read the allocation back and **fail closed** if it's short. Never
   assume a session/pool/cluster gave you what you asked for.
3. **Sanity-check the work against the compute.** Roughly: how much data, how many
   passes, on how many cores? If the arithmetic doesn't support the estimate, fix the
   job before launching, not after.
4. **Right-size the tool for the job.** A helper written for a metadata operation
   (dropping a table) is not automatically fit for a billion-row scan. Re-check its
   sizing assumptions whenever it's reused at a different scale.

**While it runs:**

5. **No black boxes. A long job must emit a heartbeat** with elapsed time. If the
   runner can't stream progress, add that first. Remote APIs that only return output at
   completion (e.g. Livy statements) need an explicit poll-and-print loop.
6. **Polling is not progress.** Repeatedly waiting on a silent job is not work. If two
   consecutive checks show no new information, **stop waiting and start diagnosing.**
7. **Breach the threshold → abort and investigate.** Do not extend the wait. Kill it,
   find out why, fix it, relaunch. "It's probably almost done" is not evidence.
8. **Tell @jimb as soon as something exceeds its estimate**, and don't absorb the delay
   silently. A 10-minute heads-up is worth hours.

**Efficiency, before hitting run:**

9. **Minimise full passes over large data.** Fuse aggregations into a single scan rather
   than one scan per check; prune to the columns actually needed.
10. **Don't `cache()` anything that won't comfortably fit in memory.** On wide,
    hundred-million-row frames it forces spill *and* defeats columnar pruning. Reading
    the source twice is usually faster.

### Notify on completion (Pushover)

@jimb does not sit and watch a running turn. **Any turn of 5 minutes or more ends with a push
notification** so the result reaches his phone instead of sitting in a chat tab he has walked
away from. The script is `C:\Files\Dev\main\copilot\tools\Send-Pushover.ps1`.

- **Stamp the clock in the first terminal command of the turn**, before any real work:
  `& C:\Files\Dev\main\copilot\tools\Send-Pushover.ps1 -Stamp`
- **Send as the last action** before handing the turn back:
  `& C:\Files\Dev\main\copilot\tools\Send-Pushover.ps1 -Title '<outcome>' -Message '<what happened, what is next>'`
- **Call it unconditionally.** The 5-minute threshold is enforced inside the script, which
  exits quietly under it, so elapsed time never has to be judged by eye. `-ThresholdMinutes`
  tunes it, `-Force` sends regardless, `-Priority 1` bypasses quiet hours (use for a failure
  or a question that blocks everything else).
- **Write the title to read on a lock screen with no other context**, e.g.
  `ferry_tracker: deployed, arrivals landing in 3 min`. Put the decision @jimb needs to make
  in the message body.
- A long turn that ends by **asking a question** still gets a notification. Waiting on an
  unread question is the exact failure this prevents.
- Credentials are the `PUSHOVER_USER_KEY` and `PUSHOVER_APP_TOKEN` environment variables, user
  scope. Never put them in a repo, a command line, a chat message, or the question tool. A
  missing key makes the script warn and exit 0, so it can never fail the work.
- **The keys are per machine.** @jimb works across several laptops and copies chats between
  them, so the repo can be current here while the environment is empty. Check before assuming
  the notifier will fire, and say so plainly when it will not.
- **Warn him to set the keys from a terminal outside VS Code.** The `Last Command` line is
  attached to the chat context, so a `SetEnvironmentVariable` call run in a watched terminal
  writes the secret straight into the transcript and forces a rotation.

## Communication style

- **Writing rules live in `writing-style.instructions.md`** (same folder, loaded every
  session). It covers voice, banned vocabulary and phrase shapes, the negative-parallelism
  ban, and analogy limits. It applies to everything: chat, commits, PR text, work items,
  reports, and code comments. The source of truth is
  `G:\My Drive\ai\anti-ai-writing-style.md`; re-run `copilot\tools\Sync-WritingStyle.ps1`
  after editing it. Two rules I get wrong most often: **no em dashes**, and **bold at most
  1 or 2 moments per section**.
- **Be concise; lead with the answer, minimal preamble.**
- **Plan first, then implement.** I don't do well when work jumps straight to
  implementation. Lay out a short plan and let me confirm before you build.
- **I'm a visual person, and dense text is not great.** HTML is by far the best way to
  share information; prefer it for anything substantial.
- **For any HTML you produce, include both a dark and a light theme** (with a way to
  toggle / respect the system preference).
- **Always open the HTML for me, every time.** Don't hand me a path or a link and wait.
  Open it in the browser as soon as it is written, and reopen it after every regeneration
  so what I'm looking at is never a stale render.

## Pull requests

- **Lint changed Python for the security ruleset before opening a PR.** Run
  `python -m ruff check --no-cache --select S <changed paths>` (`ruff` is not on PATH here,
  so use the module form). Clear every finding or state in the PR why each one stays.
- **Point the independent review at OWASP classes, not only correctness.** Ruff and bandit
  have no zip-slip rule, so a path-traversal write in an archive extractor reached PR 216619
  untouched. Ask the reviewer how the change breaks, not whether it is right.
- **Before creating a PR, show an HTML of all changed files** (dark/light themed, per
  the communication-style rules above). Present it and let @jimb review the change set
  *before* the PR is opened, not after.
- **Keep changed-files review HTML consistent with recent ARR status reports.** Use the
  squared, dark-first visual system with an indigo/violet accent, a light theme, system
  preference support, a persisted theme toggle, the Inter font, and Lucide-style stroke
  icons. Generate it from the exact reviewed `origin/main...HEAD`, then show the branch,
  HEAD, local generation time, commit and file counts, review decision, validation
  evidence, change intent, and work still pending. Group files by purpose and list every
  changed file with a plain-language summary plus its full searchable, expandable patch.
  Include expand-all and collapse-all controls. Regenerate and reopen the report whenever
  HEAD changes. Do not fall back to the rounded, light-first raw-diff template.
- **Reviewers: Jesus Anaya Valdes and `v-ssfikas` only, and both REQUIRED.** Do not add
  anyone else as an approver, and never leave a reviewer optional. `az repos pr reviewer add`
  creates *optional* reviewers, so set `isRequired` afterwards via the REST API:
  `PUT .../pullRequests/<id>/reviewers/<reviewerId>?api-version=7.1` with
  `{"isRequired": true, "id": "<reviewerId>"}`. Verify with
  `az repos pr show --query "reviewers[].{name:displayName, required:isRequired}"`.
- **Proof of presence is @jimb's to complete, never mine.** It is a human-presence
  attestation, so automating it defeats the control. When a PR needs it, say so plainly and
  stop. The method is **always Microsoft**.
- **Set the PR description over REST, not the CLI.** `az repos pr create --description`
  silently truncates a multi-line body to its first line. Create the PR, then
  `PATCH .../pullRequests/<id>?api-version=7.1` with `{"description": "..."}` and read the
  length back. `--work-items` on create can also no-op; verify with
  `az repos pr work-item list` and attach separately if it is empty.
- **After creating a PR, always check its comment threads**. Don't assume a fresh PR has
  none. The `GitOps` **PR Assistant** posts an automated AI code review within a minute or
  two, and it **also rewrites the PR description** with its own generated summary, silently
  discarding whatever description was set at creation. So: re-read the description after it
  runs and restore it if it was clobbered, and triage its review threads (they carry a
  severity, and the high-severity ones are often legitimate). Fetch threads via
  `GET .../pullRequests/<id>/threads?api-version=7.1` and filter out `commentType == "system"`.

## Developer branch and shipping

@jimb develops on `jimb/main` in `FDE_Revenue_Bedrock` and pushes it to origin. Feature
branches are cut from `origin/main` and carry cherry-picks. Written after PR 216619, where a
cherry-pick took one commit of a two-commit change and the missing half surfaced only as a
merge conflict, and the branch had drifted 18 commits before anyone looked.

- **One shippable change is one commit on `jimb/main`.** Amend or squash before shipping so
  every cherry-pick is self-contained. If a change grew across commits, collapse it first.
- **Cut the feature branch from `origin/main`, never from `jimb/main`.**
- **Verify the cherry-pick before opening the PR.** For every path being shipped,
  `git diff origin/main...<feature> -- <paths>` must equal
  `git diff origin/main...jimb/main -- <paths>`. Any difference means part of the change was
  left behind. This is the gate; skipping it is what let PR 216619 go out incomplete.
- **Keep personal-only files off `jimb/main`.** Emptied developer shortcut manifests and
  Fabric's own "Committing N items from workspace" commits rewrite shared files and make the
  branch unmergeable. Park them where they can never be a cherry-pick source.
- **Never treat the `jimb/main` tip as the source for a shared file.** Fabric's workspace
  export writes to the same branch, so a file can look repaired there and still be stale
  against main. The `setup_catalog` seeds read as restored on the branch and were 383 lines
  behind `origin/main`. Compare against `origin/main` before shipping any shared file.
- **Reset `jimb/main` onto `origin/main` after every merge** and re-apply only the personal
  overlay. Drift is what forced the 18-commit cleanup after PR 216619.

## Naming conventions

**Fabric notebooks** (the `FDE_Revenue_Bedrock` data platform) are named:

```
nb_<layer>_<solution>_<schema>_<entity>
```

e.g. `nb_silver_arr_revenue_nuancearr`, `nb_silver_arr_bridge_nonearemaining`,
`nb_silver_arr_dim_tenant`. Rules:

- **Solution comes before schema.** `arr` leads, so every notebook belonging to a
  solution sorts together in the folder listing regardless of which schema it writes
  to. It is `nb_silver_arr_revenue_…`, never `nb_silver_revenue_…_arr`.
- **Never repeat a token.** If the solution is `arr`, the entity does not carry `arr`
  again. Write `nb_silver_arr_bridge_nonearemaining`, not
  `nb_silver_arr_bridge_arr_nonearemaining`, even when the legacy p32 source object
  is named `ARR_BRIDGE_ARR_NonEARemaining`. Don't inherit redundancy from the source.
- **Drop the `fact` token.** It adds nothing the schema and entity don't already say.
  `nb_silver_arr_revenue_wwicquotatarget`, not `nb_silver_revenue_fact_arr_wwicquotatarget`.
- The **folder** (`<name>.Notebook`), the **`displayName`** in its `.platform`, and any
  self-reference in the notebook body must all agree. A rename that updates only the
  folder leaves Fabric showing the old name.

**Renaming a notebook**: always `git mv` the `.Notebook` folder (so git records a
rename `R` rather than a delete + add), update `displayName`, and **keep `logicalId`
unchanged**. The `logicalId` is what makes Fabric treat it as a rename instead of a
delete-and-recreate, which preserves the item's run history. Then grep the whole repo
for the old name, because pipelines and `%run` references won't follow a folder rename.

**`.platform` manifests are LF**, like everything else in the tree. Watch for a CRLF
manifest sneaking in: it shows up as a whole-file rewrite in `git diff --numstat`
(e.g. `12  12` for a 12-line file) instead of the one or two lines actually changed.
Normalize with `[IO.File]::WriteAllText($p, $t -replace "\r\n","\n")` and re-check the
numstat before committing.

## Commits

Include the trailer on commits:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
