# copilot

The WorkLog tooling, Copilot CLI skills, and work/GitHub dashboards that used to
live here have **moved** to the cloud-hosted **`worklog_web`** project:

- Repo: https://github.com/purduepete/worklog_web
- Live dashboard: https://func-worklog-umcla2.azurewebsites.net/

## Still here

- **`instructions.html`** — the **Copilot Reference Hub** (general reference, not
  superseded by worklog_web). Open it in a browser.
- **`skills/`** — personal Copilot CLI skills, junctioned into `~/.copilot/skills`
  by `skills/Install-Skills.ps1`.
- **`global-instructions/`** — junctioned into `~/.copilot/instructions`, loaded in
  every repo.
- **`settings/`** — canonical `settings.json` and `permissions-config.json` for the
  Copilot CLI, kept in step across machines by
  `tools/Sync-CopilotSettings.ps1` (`-Mode Status|Save|Apply`).

## New machine

```powershell
git clone <this repo> C:\Files\Dev\main\copilot
pwsh -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
```

That creates every junction and seeds the CLI settings. Then `/restart` the CLI.

## After changing CLI settings

```powershell
# this computer is right -> record it, then commit and push
pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Save

# this computer is behind -> git pull first, then take the repo's copy
pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Apply
```

`Save` and `Apply` are used instead of Pull/Push because those read backwards here.
Passing `-Mode Pull` or `-Mode Push` errors out rather than guessing.

`config.json` is not synced. The CLI manages it and it is machine-local.