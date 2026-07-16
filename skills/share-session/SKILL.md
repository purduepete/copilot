---
name: share-session
description: >-
  Share @jimb's Copilot CLI sessions between his computers (e.g. laptop
  XFINJIMBLAPTOP <-> Cloud PC CPC-jimb-M4XXGV) through a OneDrive drop folder, so
  work done on one machine can be read, summarized, or resumed on another. Export
  (push) copies local session-state to OneDrive; Import (pull) lists shared sessions
  and copies one back locally so `copilot --resume=<id>` continues it. Fills the gap
  where the cross-session/cloud store hasn't synced a local session yet. WHEN:
  "share my session", "share sessions between computers", "share this session with my
  other machine", "send today's work to my other computer", "export copilot sessions",
  "sync my sessions via OneDrive", "what did I do on my laptop/other machine", "pick
  up work from my laptop", "resume a session from another computer", "import a shared
  session", "continue a session from my other machine".
argument-hint: optionally "export", "list", or a session id to import
---

# share-session

Bridge @jimb's Copilot CLI sessions across his machines via a shared **OneDrive**
folder. Local session transcripts live at
`%USERPROFILE%\.copilot\session-state\<id>\` (holding `events.jsonl`, `plan.md`,
`checkpoints\*.md`, `session.db`, `workspace.yaml`). The cloud/cross-session store
only sees sessions **already synced**, so today's work on one machine is often
invisible from another. This skill is the **file-based bridge** for that gap.

Two scripts (reference by absolute path):

| Direction | Script |
|---|---|
| **Push** — copy local sessions to the share | `Export-CopilotSessions.ps1` |
| **Pull** — list / import a shared session | `Import-CopilotSessions.ps1` |

Default drop folder: **`<OneDrive - Microsoft>\copilot-session-share`**, laid out as
`copilot-session-share\<yyyy-MM-dd>\<COMPUTERNAME>\<session-id>\` with a per-day
`manifest.json`.

## Flow

1. **On the source machine** (the one you worked on) — export, then let OneDrive sync
   (wait for the green check).
2. **On the target machine** — list what's available, then either ask Copilot to read
   a session's `checkpoints\*.md` / `events.jsonl` to **summarize** it, or **import**
   it to **resume** the actual conversation.

## Export (push)

```powershell
# Last 5 days of local sessions -> OneDrive share (auto-prunes exports >14 days)
pwsh -File C:\Files\Dev\main\copilot\skills\share-session\Export-CopilotSessions.ps1

# Today only, slim dialog-only copies (no tool output)
pwsh -File C:\Files\Dev\main\copilot\skills\share-session\Export-CopilotSessions.ps1 -Days 0 -TranscriptOnly

# Machine-readable summary of what was exported
pwsh -File C:\Files\Dev\main\copilot\skills\share-session\Export-CopilotSessions.ps1 -Json
```

**Parameters:** `-Days` (default 5; 0 = today), `-All`, `-TranscriptOnly` (also writes
`<id>.dialog.jsonl` = user+assistant only), `-ShareRoot <path>` (override drop folder),
`-RetentionDays` (default 14), `-NoPrune`, `-Json`. Selection uses the **newest file
inside** each session folder as its "last active" time (the folder's own timestamp is
unreliable).

## List & import (pull / resume)

```powershell
# List everything available in the share (grouped by date/computer)
pwsh -File C:\Files\Dev\main\copilot\skills\share-session\Import-CopilotSessions.ps1

# Import one session locally (accepts a 7+ char id prefix)
pwsh -File C:\Files\Dev\main\copilot\skills\share-session\Import-CopilotSessions.ps1 -SessionId da6bae75
```

Import copies the shared `session-state\<id>\` folder into this machine's local
`%USERPROFILE%\.copilot\session-state`, strips the `inuse*` lock, and prints the exact
resume command. Then continue the conversation yourself:

```powershell
copilot --resume=<session-id>
```

**Parameters:** `-SessionId <id-or-prefix>` (omit to just LIST), `-Date <yyyy-MM-dd>`
and `-Computer <name>` (disambiguate), `-All`, `-Force` (overwrite an existing local
copy — default is skip), `-ShareRoot`, `-Json`.

## Read vs resume

- **Read/summarize** (default, no import): point Copilot at a shared session's
  `checkpoints\*.md` (compact recap) or `events.jsonl` (full transcript) directly in
  the OneDrive folder — no import needed. Best for "what did I do on my other machine".
- **Resume** (import): use when you want to *continue* that exact session on this
  machine. A plain folder copy is sufficient — `copilot --resume=<id>` reads the
  session-state folder; **no `session-store.db` row is required** (verified).

## Caveats

- **Confidentiality:** transcripts can contain confidential repo content (e.g.
  FDE_Revenue_Bedrock). This stays inside @jimb's own **work OneDrive** (same identity)
  — acceptable. Never route session data anywhere else. Use `-TranscriptOnly` for a
  lighter, tool-output-free share.
- **Picker vs id:** an imported session resumes by explicit id immediately; it may not
  appear in the bare `copilot --resume` picker (DB-backed) until the CLI reindexes.
- **cwd:** resume opens in the session's original `cwd`; import warns if that path
  doesn't exist on this machine. Both of @jimb's machines use `C:\Files\Dev`, so this
  is usually fine.
- **Large transcripts:** `events.jsonl` can be several MB per session.
- Requires OneDrive to have finished syncing on both ends before the other machine can
  see the export.
