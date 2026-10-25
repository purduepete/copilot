# copilot

The WorkLog tooling, Copilot CLI skills, and work/GitHub dashboards that used to
live here have **moved** to the cloud-hosted **`worklog_web`** project:

- Repo: https://github.com/purduepete/work-log
- Live dashboard: https://func-worklog-umcla2.azurewebsites.net/

## Still here

- **`global-instructions/`** — the checked-in source for shared instructions.
- `tools\Manage-Preview.ps1`: owned local preview supervision, status and cleanup.

## Local previews

Use one tracked preview per app. `Start` stays running as its supervisor, so launch
the following with the Copilot powershell tool's `mode: "async", detach: true`.
Use your actual session id. This example runs a Vite preview of an existing build:

```powershell
& C:\Files\Dev\main\copilot\tools\Manage-Preview.ps1 -Action Start `
  -App ferry-tracker -Session '<current-session-id>' `
  -WorkingDirectory C:\Files\Dev\main\ferry-tracker `
  -Executable node -Arguments @('node_modules\vite\bin\vite.js', 'preview', '--host', '127.0.0.1', '--port', '4173', '--strictPort') `
  -Url http://127.0.0.1:4173/
```

Start refuses occupied ports and another session's app record. A repeated Start
from the same session reuses a responding preview. Readiness requires HTTP 200
and a listener owned by the launched process tree. Use an executable such as
`node.exe` or the full PowerShell path, rather than a `.cmd` shim. Bind the app
to loopback and configure a strict port so it cannot silently choose another one.
Arguments are passed individually; paths containing spaces stay single arguments.
Never put credentials in arguments. The helper stores process identities, session,
URL and stdout/stderr logs under `%LOCALAPPDATA%\Copilot\previews`.

Status and Stop are synchronous:

```powershell
& C:\Files\Dev\main\copilot\tools\Manage-Preview.ps1 -Action Status
& C:\Files\Dev\main\copilot\tools\Manage-Preview.ps1 -Action Stop `
  -App ferry-tracker -Session '<owning-session-id>'
```

Stop signals the supervisor, which checks PID, creation time and executable path
when inspecting its tracked descendants. A Windows job contains the launched tree
and stops it when the supervisor closes or exits unexpectedly. It verifies port release before removing
the ownership record. Another session's id must only be used with the user's
approval. This helper does not manage production services or adopt old listeners.
It does not automatically close browser pages or expire pending review previews.
Reuse browser pages and close temporary pages separately where supported.

Stop test-only servers after validation. Keep a review preview until the review
ends, then Stop it unless the user asks to retain it. If a supervisor is forcibly
killed or the machine crashes, Status reports the stale record even after the job
has stopped its processes. Inspect the
record's process identities and listeners before manually cleaning up that app;
do not remove the record and launch a second copy blindly.

Run the isolated lifecycle regression checks with PowerShell 7.2 or later and Node:

```powershell
& .\tools\Test-ManagePreview.ps1
```

The checks use temporary loopback servers and remove their files and processes.

## New machine

```powershell
git clone git@github.com:purduepete/copilot.git C:\Files\Dev\main\copilot
```

### Instructions

Junction `~\.copilot\instructions` at `global-instructions`. Both Copilot CLI and
VS Code discover that path by default, so there is nothing to configure once the
junction exists.

```powershell
New-Item -ItemType Junction -Path "$HOME\.copilot\instructions" `
         -Target 'C:\Files\Dev\main\copilot\global-instructions'
```

Junctions need no admin rights and no Developer Mode, unlike symlinks.

Each instruction file carries `applyTo: '**'` in its YAML frontmatter. VS Code only
auto-loads instruction files that declare an `applyTo` glob, so do not remove it.

### Not synced

`config.json` is machine-local. The CLI manages it.

Copilot chat memory lives in
`%APPDATA%\Code\User\globalStorage\github.copilot-chat\memory-tool\memories\`.
Settings Sync does not carry `globalStorage`, so those notes start empty on a new
machine. The junctioned instructions still load, so this is optional redundancy.

`tools\Sync-WritingStyle.ps1` only runs on machines with `G:\My Drive` mounted.
Everywhere else the checked-in copy is the source and `git pull` refreshes it.