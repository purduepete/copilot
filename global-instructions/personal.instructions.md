# Personal global Copilot instructions (@purduepete)

Shared across **all** repositories and machines. The canonical copy lives in the
`copilot` repo at `global-instructions\personal.instructions.md` and is linked into
`%USERPROFILE%\.copilot\instructions\` by `skills\Install-Skills.ps1` (directory
junction — no admin required). Edit here, commit/push, then `git pull` on other
machines to sync. Repo-specific rules still belong in each repo's
`.github/copilot-instructions.md`, which take precedence for that repo.

## Preferences

- When cloning source/solution repos for analysis, clone them under
  `C:\Files\Dev\msft` (not a temp directory). On the work computer, new repos are
  most often written to `C:\Files\Dev\msft`.
- Treat the WorkLog category alias `dev` as `development`.
- **Always display times in my local time zone**, never UTC. When a data source
  stores timestamps in UTC (e.g. the Copilot session store's `created_at`), convert
  to local time before showing them, and label them as local.
- **Anything that alters a database** (schema migrations, data-fix scripts, or any
  write/DDL against a live DB) **requires a second opinion from Gemini** before it is
  run — get Gemini to review the change first, then proceed (see `## Models`).

## Models

When I want a **second opinion, accuracy review, or cross-check**, run it through a
**Gemini** or **ChatGPT** model — invoked as a review sub-agent with a model override,
not a separate external CLI. Use these model IDs:

- **Gemini** — `gemini-3.1-pro-preview` (deep review) or `gemini-3.5-flash` (fast).
- **ChatGPT** — `gpt-5.5` (default), `gpt-5.4`, or `gpt-5.3-codex` (code-focused).

The `## Preferences` rule that DB-altering changes "require a second opinion from
Gemini" is satisfied by invoking a Gemini model above.

### Route cheap work to a cheap model

Don't burn a premium model on a task that doesn't need one. You **cannot** change your
own model mid-session — only I can, via `/model` — but you *can* delegate the expensive
part: hand the bulk reading to a sub-agent with a `model` override and spend premium
tokens only on the final synthesis.

| Kind of work | Model |
|---|---|
| Read-only Q&A, doc/repo lookups, summarizing existing files, "what does X say / where does Y live" | Delegate to `explore`, or a `task` sub-agent overridden to `gemini-3.5-flash` / `gpt-5.4-mini` / `claude-haiku-4.5` |
| Code changes, debugging, architecture & design judgment, PR review, anything touching a live DB | Keep the premium model |

Rule of thumb — if the task is read-only, the answer already exists in docs or config,
and no cross-file reasoning about *behavior* is required, delegate it. Producing a
substantial artifact from what was read (e.g. a themed HTML report) still justifies the
premium model for that step. When it's genuinely borderline, delegate and check the
result rather than defaulting to expensive.

## Communication style

- **Be concise; lead with the answer, minimal preamble.**
- **Plan first, then implement.** I don't do well when work jumps straight to
  implementation — lay out a short plan and let me confirm before you build.
- **I'm a visual person — dense text is not great.** HTML is by far the best way to
  share information; prefer it for anything substantial.
- **For any HTML you produce, include both a dark and a light theme** (with a way to
  toggle / respect the system preference).

## Pull requests

- **Before creating a PR, show an HTML of all changed files** (dark/light themed, per
  the communication-style rules above). Present it and let @jimb review the change set
  *before* the PR is opened — not after.
- **Reviewers: Jesus Anaya Valdes and Rodrigo Cadena only, and both REQUIRED.** Do not add
  anyone else as an approver, and never leave a reviewer optional. `az repos pr reviewer add`
  creates *optional* reviewers, so set `isRequired` afterwards via the REST API:
  `PUT .../pullRequests/<id>/reviewers/<reviewerId>?api-version=7.1` with
  `{"isRequired": true, "id": "<reviewerId>"}`. Verify with
  `az repos pr show --query "reviewers[].{name:displayName, required:isRequired}"`.
- **After creating a PR, always check its comment threads** — don't assume a fresh PR has
  none. The `GitOps` **PR Assistant** posts an automated AI code review within a minute or
  two, and it **also rewrites the PR description** with its own generated summary, silently
  discarding whatever description was set at creation. So: re-read the description after it
  runs and restore it if it was clobbered, and triage its review threads (they carry a
  severity, and the high-severity ones are often legitimate). Fetch threads via
  `GET .../pullRequests/<id>/threads?api-version=7.1` and filter out `commentType == "system"`.

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
  again — `nb_silver_arr_bridge_nonearemaining`, not
  `nb_silver_arr_bridge_arr_nonearemaining`, even when the legacy p32 source object
  is named `ARR_BRIDGE_ARR_NonEARemaining`. Don't inherit redundancy from the source.
- **Drop the `fact` token.** It adds nothing the schema and entity don't already say.
  `nb_silver_arr_revenue_wwicquotatarget`, not `nb_silver_revenue_fact_arr_wwicquotatarget`.
- The **folder** (`<name>.Notebook`), the **`displayName`** in its `.platform`, and any
  self-reference in the notebook body must all agree. A rename that updates only the
  folder leaves Fabric showing the old name.

**Renaming a notebook** — always `git mv` the `.Notebook` folder (so git records a
rename `R` rather than a delete + add), update `displayName`, and **keep `logicalId`
unchanged**. The `logicalId` is what makes Fabric treat it as a rename instead of a
delete-and-recreate, which preserves the item's run history. Then grep the whole repo
for the old name — pipelines and `%run` references won't follow a folder rename.

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
