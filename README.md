# copilot

The WorkLog tooling, Copilot CLI skills, and work/GitHub dashboards that used to
live here have **moved** to the cloud-hosted **`worklog_web`** project:

- Repo: https://github.com/purduepete/work-log
- Live dashboard: https://func-worklog-umcla2.azurewebsites.net/

## Still here

- **`global-instructions/`** — the checked-in source for shared instructions.

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