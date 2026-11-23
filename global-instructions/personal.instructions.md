---
applyTo: '**'
description: "@jimb's global workflow, tooling, and review preferences. Apply in every repository."
---

# Personal global Copilot instructions (@purduepete)

Shared across repositories and machines. Repo-specific rules belong in each repo's
`.github/copilot-instructions.md` and take precedence for that repo.

## General workflow

- **Keep it simple.** Use the shortest working procedure and existing tools. Avoid
  speculative helpers, approval layers, repeated reviews, and side work.
- **Stop after the requested result is verified.** Run focused checks and inspect the
  requested behavior. Expand the checks only when a focused check fails or I ask.
- **Ask about consequential trade-offs early.** Establish scope, data gaps, and downtime
  before designing work that depends on them. Reuse answers already given.
- **Plan first, then implement.** Give me a short plan for implementation work. For small,
  clear, low-risk changes, state the plan and proceed in the same turn. Wait for confirmation
  when a consequential trade-off needs my decision or I ask to review the plan.
- **Ground decisions in the actual evidence.** Before asking me to choose, inspect the
  relevant code, query, config, or DDL and cite the exact lines.
- **Report actual progress.** Distinguish requested, launched, writing data, committed,
  and verified. Give confirmed results, elapsed time, and specific blockers.
- Reuse verified setup and lessons when they prevent repeat failures. Don't delay current
  work for unrelated feedback.
- Always show times in my local time zone. Convert UTC timestamps and label them local.
- When I say "commit," commit and push unless I explicitly ask to keep the commit local
  or not to push.
- Include this trailer on commits unless I ask otherwise:

  ```text
  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
  ```

## Shared safety and task-specific procedures

- Any write or DDL against a live database requires an independent model review before
  it runs. Routine WorkLog writes (`start`, `stop`, `add`, `edit`, day markers, summaries,
  and notes) are exempt. Explicit WorkLog deletion or removal requires review.
- Use the matching skill for specialized procedures:
  - `msft-ado-repo` for Azure DevOps work and PRs.
  - `vscode-extension` for Marketplace work.
  - `worklog` for WorkLog tasks.

## Models

For second opinions, accuracy reviews, and cross-checks, choose a currently available
model that fits the task, context size, and time budget. I prefer Claude, Gemini, or
ChatGPT, with no fixed model-version requirement.

- For independent reviews, prefer a different provider from the primary model when
  practical. A same-provider review is acceptable when it is the best fit or the only
  suitable option.
- For multiple independent reviews, prefer different providers when available. Record
  the model selected and its verdict.
- Keep narrow validations time-bounded. Ask for a concise verdict when the budget ends.
- Use a faster, lower-cost model for read-only lookups and summaries. Use a model with
  enough reasoning and context for code changes, debugging, architecture, PR reviews,
  and database work.
- For a required database review, choose a suitable independent model. The required
  review does not depend on a specific model version or provider.

## Completion notifications

For turns with a start marker, send a Pushover notification through
`C:\Files\Dev\main\copilot\tools\Send-Pushover.ps1` when the turn reaches 5 minutes.

- Stamp the clock with `-Stamp` in the first terminal command of the turn. Turns without
  a marker do not get an automatic notification.
- For marked turns, call the script as the last action before handing the turn back. Give
  it a lock-screen-readable title and put any decision I need to make in the message.
- Call the script unconditionally; its threshold defaults to 5 minutes. Use `-Force`
  for plan handoffs and `-Priority 1` for failures or blocking questions.
- Keys are per machine. Check that both environment variables are set before assuming
  the notification will send. Never put credentials in the repo, command line, chat,
  or question tool.
- Tell me to set missing keys from a terminal outside VS Code. A watched terminal's
  `Last Command` line can expose a `SetEnvironmentVariable` call in the transcript.

## Communication and previews

- Writing preferences are in `writing-style.instructions.md`. They apply to responses
  to me and content drafted for me.
- Be concise and lead with the useful answer.
- For HTML deliverables, include dark and light themes with a toggle or system
  preference support. Open the HTML after writing and after each regeneration.
- Open a local preview after every site change. State whether it uses live data or
  fixtures. Use `C:\Files\Dev\main\copilot\tools\Manage-Preview.ps1` for Start, Status,
  and Stop. Use the app's hyphenated name and current session id.
- Check preview ownership and listeners before starting. Reuse the current session's
  preview and browser page. Never stop another session's preview or an untracked
  listener without approval.
- Keep review previews only while review is pending. Stop them after approval,
  rejection, or review completion. Stop test-only servers in the same turn.
- Close temporary browser pages when supported. At handoff, report any retained
  preview URL and why. After stopping, verify the process exited and the port is free.

## Pull requests and repository-specific work

Use `msft-ado-repo` for Azure DevOps PR requirements, including the review report,
required reviewers, PR description verification, and comment-thread triage.
Follow repo-specific instructions for other PR providers, notebook conventions,
and repository workflows.
