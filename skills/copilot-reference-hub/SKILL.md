---
name: copilot-reference-hub
description: >-
  Open and maintain the user's personal "Copilot Reference Hub"
  (C:\Files\Dev\main\copilot\instructions.html) — a living, browsable HTML doc
  organized Subject → Topic → Section (Azure DevOps, Time Tracking, Copilot
  Skills, Copilot CLI). Open it, answer "how do I…" questions from its content,
  or add new subjects/topics/sections and commit them. WHEN: "open my reference
  hub", "copilot reference hub", "show my documentation", "open instructions.html",
  "how do I <something I've documented>", "add this to my reference hub", "document
  this in the hub", "add a note to the hub", "update my reference hub".
argument-hint: Optionally name a subject/topic to jump to, or content to add
---

# Copilot Reference Hub

A personal, living HTML reference at
`C:\Files\Dev\main\copilot\instructions.html` (repo:
https://github.com/purduepete/copilot). Organized as **Subject → Topic →
Section**, dark-themed, with a sidebar nav and client-side anchors.

## Primary action — open it

```powershell
Invoke-Item C:\Files\Dev\main\copilot\instructions.html
```

If the user names a subject/topic (e.g. "open the Proactive WorkLog section"),
open the file and tell them the anchor to click (the `id` of that section).

## Answering "how do I…" questions

The hub is the source of truth for the user's own documented workflows. To answer,
**read the relevant section** rather than guessing:

```powershell
Select-String -Path C:\Files\Dev\main\copilot\instructions.html -Pattern '<keyword>' -Context 0,8
```

Current subjects: **Azure DevOps** (open work-item report), **Time Tracking**
(WorkLog, mining VS Code chats), **Copilot Skills** (personal skills), **Copilot
CLI** (the toolbox, proactive WorkLog, WorkLog AI workflows).

## Adding content (it's a living doc)

The file has copy-paste templates marked by HTML comments. Two parts must stay in
sync — the **sidebar nav** and the **main content** — linked by matching anchor
`id`s.

1. **Sidebar nav** — add a `<details class="subject">` block (or a
   `<details class="topic">` under an existing subject) just above the
   `ADD A FUTURE SUBJECT` comment in the `<nav>`. Each section link is
   `<a href="#unique-id">N. Title</a>`.
2. **Main content** — add the matching content just above the
   `ADD FUTURE SUBJECTS BELOW` comment. Use the existing building blocks:
   - `<div class="subject-banner"><span class="badge">…icon…</span><h2>Name</h2></div>`
   - `<div class="topic-head" id="…"><svg…><h3>Topic: Name</h3></div>`
   - `<h4 id="unique-id">N. Section</h4>` then `<p>`, `<ul>`, `<table>`,
     `<pre><code>`, or `<div class="callout">`.
3. **Update the Overview** "Current subjects" line if adding a new subject.
4. **Icons** are inline lucide-style SVGs (`viewBox="0 0 24 24"`); reuse a path
   from a similar existing entry.

### Validate before committing

```powershell
$h = Get-Content C:\Files\Dev\main\copilot\instructions.html -Raw
"details: $(([regex]::Matches($h,'<details')).Count)/$(([regex]::Matches($h,'</details>')).Count)"
"table:   $(([regex]::Matches($h,'<table')).Count)/$(([regex]::Matches($h,'</table>')).Count)"
# every new href="#id" must have a matching id="id"
```

Tag opens/closes must balance and every nav `href="#id"` must resolve to an `id`.

### Commit & sync

```powershell
cd C:\Files\Dev\main\copilot
git add instructions.html
git commit -m "Update Copilot Reference Hub: <what>"
git push origin HEAD
```

Pushing syncs the hub to the user's other machines on `git pull`.

## Conventions

- Match the existing visual style (cards, callouts, tables) — don't invent new CSS.
- Keep entries concise and scannable; prefer tables for "capability → use" and
  callouts for gotchas.
- Use HTML entities (`&ge;`, `&rarr;`, `&mdash;`) instead of raw unicode to keep the
  file ASCII-safe.

## Locations at a glance

| Path | Purpose |
| --- | --- |
| `C:\Files\Dev\main\copilot\instructions.html` | The Reference Hub document |
| `C:\Files\Dev\main\copilot\README.md` | Points here; notes worklog tooling moved to worklog_web |
| `C:\Users\jimb\.copilot\skills\copilot-reference-hub\` | This skill (junction to the copilot repo) |
