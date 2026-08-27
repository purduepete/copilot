# copilot

The WorkLog tooling, Copilot CLI skills, and work/GitHub dashboards that used to
live here have **moved** to the cloud-hosted **`worklog_web`** project:

- Repo: https://github.com/purduepete/worklog_web
- Live dashboard: https://func-worklog-umcla2.azurewebsites.net/

## Still here

- **`instructions.html`** — the **Copilot Reference Hub** (general reference, not
  superseded by worklog_web). Open it in a browser.
- **`skills/`** — personal Copilot CLI skill source.
- **`global-instructions/`** — the checked-in source for shared instructions.

## New machine

```powershell
git clone <this repo> C:\Files\Dev\main\copilot
```

Then, in Copilot CLI, run `/skills add C:\Files\Dev\main\copilot\skills` followed
by `/restart`. Manage that registered skill root with `/skills list` and
`/skills remove`.

`config.json` is not synced. The CLI manages it and it is machine-local.