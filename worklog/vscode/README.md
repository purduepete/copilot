# WorkLog in VS Code

Two ways to track time while you work in VS Code.

## A. Talk to Copilot in the integrated terminal (recommended)

Run the GitHub Copilot CLI in VS Code's terminal and just describe what you're
doing in plain English — "starting on the MS Sales pull, ADO 435324",
"switching to a review meeting", "done with the pull — patched the view". Copilot
maps it to the right `Work.ps1` command, infers ids/timestamps, and regenerates
the dashboard. See the "Talking to Copilot (phrases)" section of the reference hub
(`instructions.html`).

## B. VS Code Tasks + keybindings (no Copilot needed)

1. Copy `tasks.json` from this folder into your workspace's `.vscode\tasks.json`
   (or merge the `tasks` and `inputs` arrays into an existing file). It references
   `Work.ps1` via the `WORKLOG` env var defined at the top — edit that path if your
   clone lives elsewhere.
2. (Optional) Paste the entries from `keybindings.jsonc` into your user
   `keybindings.json` (Command Palette -> *Preferences: Open Keyboard Shortcuts (JSON)*).

Then:

- **Ctrl+Shift+P -> Tasks: Run Task** -> pick a `WorkLog:` task, **or**
- Press the chord, e.g. `Ctrl+Alt+W` then `S` to **Start**, `X` to **Stop**,
  `N` for a **Note**, `M` for the **Daily summary**, `T` for **Status**, `D` for **Dashboard**.

Tasks prompt for title / category / id / text as needed.

## Forgot to start a task? Back-date it.

Nothing is lost if you forget to start — every time field can be set after the fact:

- Tell Copilot: *"I forgot to log 2-3pm, I was doing X in Dev"* and it inserts a
  session with those exact start/end times.
- Or from the CLI:
  ```powershell
  # back-date a start/stop you forgot to log in real time
  pwsh -File Work.ps1 start "Data platform meeting" -Category Meeting -At "2026-06-16 16:00"
  pwsh -File Work.ps1 stop  "Aligned on lakehouse structure" -Id 7 -At "2026-06-16 16:23"

  # fix the times on an already-logged session
  pwsh -File Work.ps1 edit -Id 6 -Start "2026-06-16 15:07" -End "2026-06-16 16:00"
  ```

> Note: true "track-as-you-type" automation (idle detection, per-file time) needs a
> dedicated extension such as WakaTime; this framework is intentionally explicit so
> sessions map cleanly to ADO items, meetings, and categories.
