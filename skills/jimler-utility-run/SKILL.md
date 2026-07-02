---
name: jimler-utility-run
description: >-
  How to actually run/test @jimb's Jimler utility apps (C:\Files\Dev\main\utility):
  you CANNOT just launch an individual exe — the WHOLE WinUtility.exe orchestrator
  must run, because WinUtility launches + manages the trio (JimlerWorker,
  JimlerShowHide, JimlerWindowManager) from the elevated exe\ folder, each is
  single-instance and owns global hotkeys. Rebuild with Publish.ps1 then relaunch
  via the WinUtility scheduled task. WHEN: "run the exe so I can test", "launch the
  utility", "test this change", "run WinUtility", "run the jimler apps", "restart
  jimler", "why isn't my change taking effect", "test JimlerShowHide",
  "test JimlerWorker", "test JimlerWindowManager", "deploy the utility",
  "update win utility", "update the utility", "pull the latest release".
argument-hint: What you changed (which of WinUtility / JimlerWorker / JimlerShowHide / JimlerWindowManager)
---

# Running / testing the Jimler utility apps

Repo: `C:\Files\Dev\main\utility`. Four WinForms apps share one solution:
`WinUtility` (the orchestrator) plus the trio `JimlerWorker`, `JimlerShowHide`,
`JimlerWindowManager`.

## Why you can't just launch one exe

- `WinUtility.exe` is the launcher/manager. On startup (`WinUtility/Jimler.cs`
  `StartJimlerProcesses`) it starts `JimlerWorker`, `JimlerShowHide`,
  `JimlerWindowManager` from the **`exe\` folder** (`Config.GetJimlerFolder()`).
- The live apps run **elevated** (the `WinUtility` scheduled task is
  RunLevel=Highest, LogonType=Interactive) and point at
  `C:\Files\Dev\main\utility\exe\WinUtility.exe`.
- Each app is **single-instance** (a mutex, e.g. `Local\JimlerWorker_SingleInstance`)
  **and** registers **exclusive global hotkeys** via `RegisterHotKey`.

So launching a fresh `bin\Debug\...\JimlerShowHide.exe` non-elevated does nothing
useful: it hits the mutex and exits, and can't steal the hotkeys the elevated copy
already owns. A non-elevated `Stop-Process` can't kill the elevated processes
either (fails silently). Symptom: you edit + build + "restart" but behavior is
unchanged because the OLD elevated `exe\` build is still what's running. Tell-tale:
`(Get-Process ...).Path` comes back EMPTY for the running PIDs (they're higher
integrity than your shell).

## To actually test a change — from an ELEVATED PowerShell

```powershell
cd C:\Files\Dev\main\utility
.\Scripts\Publish.ps1 -NoRelease        # kills all 4 procs, publishes Release to exe\, bumps version
Start-ScheduledTask -TaskName WinUtility  # relaunches WinUtility -> relaunches the trio (new code)
```

- `Publish.ps1` (see `Scripts\Publish.ps1`) stops
  `JimlerWindowManager, WinUtility, JimlerShowHide, JimlerWorker`, then
  `dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true`
  each project into `exe\`, and copies `substitutions.json` / `autocorrect.json`
  next to `JimlerWorker.exe`.
- `Publish.ps1` does NOT restart the apps. The `WinUtility` task relaunches at logon,
  so kick it manually with `Start-ScheduledTask -TaskName WinUtility` (or run
  `exe\WinUtility.exe` elevated yourself).
- `-NoRelease` skips cutting a GitHub release. Use `-ReleaseNote "..."` (implies
  `-Release`) to also publish a `gh` release.

## "update win utility" — install the latest published release

`Scripts\Update.ps1` is the INSTALL-from-release path (distinct from Publish, which
builds locally). It stops the 4 procs, downloads the latest `gh` release's `.exe`
assets from `jimlertech/utility` into `exe\`, then relaunches `WinUtility.exe`
directly (via `Start-Process`, NOT the scheduled task).

```powershell
cd C:\Files\Dev\main\utility
.\Scripts\Update.ps1
```

- Trigger phrase: **"update win utility"** ⇒ run `Update.ps1`.
- Use this to pull down a release that was already cut (e.g. after a `ship it`), or
  to sync a machine to the newest published build. It does NOT build from source.
- Needs a GitHub token (gh CLI or git credential); it relaunches WinUtility itself,
  so no `Start-ScheduledTask` step is required.

## Versioning

- Single shared `<Version>` in `WinUtility/WinUtility.csproj` covers all 4 apps.
- `Publish.ps1` auto-bumps: minor +0.01 until the minor part hits 15, then rolls to
  the next whole number (e.g. 2.15 → 3.0).

## Notes

- If you only need a compile check (not a runtime test), a plain
  `dotnet build <project>.csproj -c Debug` is fine — just don't expect launching the
  loose exe to exercise the change.
- Always run the publish + task relaunch from an **elevated** shell, or it silently
  won't replace/relaunch the elevated processes.
