---
name: solution-review
description: >-
  Run a READ-ONLY, parallel-model review of any solution/codebase and open a
  themed light/dark HTML report. TWO agents (Gemini 3.1 Pro + Claude Opus)
  analyze the target at once; I merge their results. Scope=audit finds
  robustness / performance / reliability / duplication issues (Critical→Low with
  file:line, impact, fix); scope=quality produces a graded maintainability
  scorecard (test coverage, type safety, complexity, readability, architecture,
  docs, dead code, conventions); scope=both runs both. Defaults to the current
  directory; never changes code. WHEN: "review this solution", "audit this
  codebase", "solution audit", "robustness audit", "reliability review",
  "production readiness review", "rubber duck this codebase", "find performance
  problems", "check for duplication", "measure code quality", "code quality
  report", "quality scorecard", "grade this codebase", "assess maintainability",
  "how good is this code", "parallel model review", "is this production ready".
argument-hint: "[path; defaults to CWD] [-Scope audit|quality|both] [-NoOpen]"
---

# Solution Review

One entry point for **read-only, parallel-model** review of a codebase. Two other
models analyze the target **in parallel**, then I synthesize their output into a
self-contained, themed HTML report. Modeled on the webportfolio reviews (06/27
rubber-duck reliability review and the 07/02 perf/duplication audit).

There are two lenses, selected by **`-Scope`**:

- **`audit`** — *what's fragile or slow*: **Robustness · Performance ·
  Reliability · Duplication**. Output: prioritized findings (Critical→Low) with
  `file:line`, impact and fix. Renderer: `Render-AuditReport.ps1`.
- **`quality`** — *how good / maintainable*: a **graded scorecard** across test
  coverage, type safety, complexity, readability, architecture, documentation,
  dead code and convention adherence. Renderer: `Render-QualityReport.ps1`.
- **`both`** (default when the ask is generic "review this") — run both, produce
  two reports.

This skill **never modifies code** — analysis + report only. If @jimb wants fixes
afterward, follow the target repo's own issue-first workflow (out of scope here).

## Inputs

- **Target**: the path argument, defaulting to the current working directory.
  Resolve to an absolute Windows path before dispatching.
- **Models**: `gemini-3.1-pro-preview` and an **Anthropic Claude** model
  (e.g. `claude-opus-4.8` — @jimb prefers Claude over MAI for this review). If the
  user names different models, use those.
- **Scope**: `audit`, `quality`, or `both`. Infer from the request if not stated
  ("robustness / reliability / perf / duplication / production-ready" → audit;
  "quality / grade / maintainable / how good" → quality; generic "review" → both).

## Workflow

### 1. Establish the target
Resolve to an absolute path; get a quick shape (top-level folders, languages,
scale, presence of tests / lint config / CI). Note obvious red flags (huge single
files, near-duplicate file/route/service names) to seed the agent prompts.

**Assess the prevention layer.** Check whether the target has a real regression
gate: a CI workflow that runs on PRs (not just deploy), a lint/format config, a
type-check step, and a non-trivial test suite. If any are **missing or toothless**
(e.g. deploy-only CI, a single token test, no lint), that is the *root cause* of
recurring findings — surface it as a **top-priority meta-finding** (see step 3),
not just a note.

### 2. Dispatch TWO parallel agents (same turn = true parallelism)
Use the **`task`** tool, `agent_type: general-purpose`, `mode: background`, each
with a **`model`** override. Give each a COMPLETE, self-contained prompt (they do
not see this conversation). Both prompts MUST require: **READ-ONLY, do NOT modify
files**; absolute Windows paths with target root `<resolved path>`; **strict JSON**
output; concrete `file:line` locations; rank by real-world impact.

For **audit** scope, split the lenses (overlap is what makes cross-model agreement
meaningful):
- **Gemini** → emphasis on **Reliability + Robustness** (error handling, retries,
  concurrency/race conditions, resource leaks, transactions, input validation,
  failure modes, edge cases).
- **Claude** → emphasis on **Performance + Duplication** (N+1 / redundant work, hot
  paths, oversized files/bundles, algorithmic cost; copy-paste, duplicated
  files/routes/services, dead code).

  Finding JSON: `{ "category":"Reliability|Performance|Robustness|Duplication|Prevention",
  "severity":"Critical|High|Medium|Low", "title","location","impact",
  "recommendation", "plan":[{ "stage","step" }] }`. Ask each agent to include a
  short **staged `plan`** per finding (the concrete steps to fix that item,
  broken into `Stage 1`, `Stage 2`, … — smallest safe change first).
  (`Prevention` is reserved for the meta-finding you add in step 3.)

For **quality** scope, have **both** models score the **same** dimensions 0–100
(test coverage, type safety, complexity, readability, architecture, documentation,
dead code, convention adherence), each with a one-line justification and 1–3
`topIssues`, plus an overall 0–100 and 3–6 improvement levers.

  **Test coverage is INFORMATIONAL only** (@jimb's rule): score it and surface
  weak/absent tests as a callout, but **exclude it from the overall score** —
  mark that dimension `"excludeFromScore": true` so the renderer shows it without
  a grade and it does not drag the number down.

  Quality JSON: `{ "overallScore":n, "dimensions":[{ "name","score","notes",
  "topIssues":[...], "excludeFromScore":false }], "improvements":[{ "title",
  "dimension","effort","impact","detail" }] }` (effort/impact = Low|Medium|High).

For **both**, ask each agent to return an object `{ "audit":[...], "quality":{...} }`
so one dispatch covers both lenses.

### 3. Synthesize
- **Audit**: combine the arrays, **de-duplicate** same-root-cause findings (keep
  clearer wording + higher severity), set **`foundBy`** to the model(s) that
  surfaced each (both = higher confidence), assign short `id`s (`R1`,`P2`,`D3`),
  ensure every finding has a **staged `plan`** (Stage 1 → n), build an overall
  **`roadmap`** that sequences the findings into phases (each stage = a `goal`
  plus the finding `items` it covers — typically Stage 1 = quick wins / highest
  risk, later stages = larger refactors), and write a 1–2 sentence `summary`.
- **Prevention meta-finding (audit)**: if step 1 found the regression gate missing
  or toothless, prepend a finding with `"category":"Prevention"`, `id` `PL1`, a
  **High/Critical** severity, and a `plan` to stand up the missing gate (CI on PRs
  → lint/format → type-check → seed tests). This is the highest-leverage item when
  the same problems keep recurring — its whole job is to *stop findings from coming
  back*. The renderer shows Prevention findings with a distinct accent, a top
  **meta-callout**, and its own filter button.
- **Recurrence is automatic** — the renderer keeps a per-target history snapshot
  (`<OutDir>\history\<slug>.json`, keyed by normalized `category|title`) and flags
  any finding that appeared in a previous run with a **"Recurring ×n"** badge, a
  Recurring KPI/filter, and a callout. Keep finding **titles stable run-to-run** so
  recurrence matches; a growing recurring count is the signal that fixes aren't
  being locked in (i.e. the Prevention meta-finding is overdue).
- **Quality**: per dimension combine the two scores (**average**; on wide
  disagreement lean **lower** and note it — quality gaps are under-reported, rarely
  over-reported), merge `topIssues`/`improvements`, compute an `overallScore`
  from the **scored** dimensions only — **exclude Test coverage** (mark it
  `excludeFromScore:true`; weight Complexity/Architecture) — and a `summary`.

### 4. Render (write payload to a temp JSON, then run the matching script)

```powershell
# audit
pwsh -File C:\Files\Dev\main\copilot\skills\solution-review\Render-AuditReport.ps1   -InputJson <audit.json>
# quality
pwsh -File C:\Files\Dev\main\copilot\skills\solution-review\Render-QualityReport.ps1 -InputJson <quality.json>
```

Each writes a self-contained HTML report (indigo→violet accent, **light + dark
toggle** respecting the system preference, squared corners, Lucide stroke icons,
no emoji) to `%TEMP%\solution-audit\` / `%TEMP%\code-quality\` respectively and
**opens it**. Pass `-NoOpen` to skip the browser (still writes + prints a summary).
The authoritative payload schema for each lives in that script's header comment.

For **`both`**, render each report (two files open). Grade mapping applied by the
quality script: **≥90 A · ≥80 B · ≥70 C · ≥60 D · else F**.

### 5. Summarize in chat
- Audit: lead with Critical/High findings and where the two models **agreed**.
- Quality: lead with the **overall grade** and the weakest 1–2 dimensions + top
  lever.
Keep it short; the report has the detail.

## Notes

- **Read-only, always** — neither the agents nor the scripts edit code.
- Dispatch both agents in the **same turn**; synthesize once both return.
- Large targets: tell each agent to prioritize the highest-traffic / highest-risk
  areas over walking every file.
- Keep the quality dimension set stable run-to-run so a repo's grade is comparable
  over time.
- **Recurrence tracking** (audit): the renderer persists a per-target history to
  `%TEMP%\solution-audit\history\<slug>.json` and badges repeat findings. Don't
  delete it between runs — it's what proves whether fixes are sticking. Keep
  finding titles stable so matches hold.
- **When problems keep recurring**, resist working the findings list again — lead
  with the **Prevention** meta-finding (stand up a real CI/test/lint gate) so the
  fixes get locked in instead of regressing.
