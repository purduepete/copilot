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
- The live apps run **elevated (High integrity)** — NOT from a manifest
  (WinUtility's manifest is `asInvoker`) but because `exe\WinUtility.exe` has a
  per-user **RUNASADMIN** AppCompat layer
  (`HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers`).
  Any ShellExecute launch (`Start-Process`, double-click, the scheduled task)
  makes Windows **auto-elevate it via UAC**, and the trio WinUtility spawns
  inherit High. So they come up elevated regardless of the launching shell's
  integrity. (The `WinUtility` scheduled task is also RunLevel=Highest, but the
  RUNASADMIN layer is why even a manual `Start-Process` from a Medium shell yields
  High.)
- Each app is **single-instance** (a mutex, e.g. `Local\JimlerWorker_SingleInstance`)
  **and** registers **exclusive global hotkeys** via `RegisterHotKey`.

So launching a fresh `bin\Debug\...\JimlerShowHide.exe` non-elevated does nothing
useful: it hits the mutex and exits, and can't steal the hotkeys the elevated copy
already owns. A non-elevated `Stop-Process` can't kill the elevated processes
either (fails silently). Symptom: you edit + build + "restart" but behavior is
unchanged because the OLD elevated `exe\` build is still what's running. Tell-tale:
`(Get-Process ...).Path` comes back EMPTY for the running PIDs (they're higher
integrity than your shell).

## To actually test a change

You do NOT need an elevated shell to *launch* — `WinUtility.exe` auto-elevates
itself (RUNASADMIN, above). The only thing that needs elevation is **killing the
already-running elevated apps** (a Medium shell can't `Stop-Process` a
higher-integrity process).

```powershell
cd C:\Files\Dev\main\utility
.\Scripts\Publish.ps1 -NoRelease         # stops the 4 procs, publishes Release to exe\, bumps version
Start-ScheduledTask -TaskName WinUtility  # OR: Start-Process exe\WinUtility.exe (auto-elevates via UAC)
```

- `Publish.ps1` (see `Scripts\Publish.ps1`) stops
  `JimlerWindowManager, WinUtility, JimlerShowHide, JimlerWorker`, then
  `dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true`
  each project into `exe\`, and copies `substitutions.json` / `autocorrect.json`
  next to `JimlerWorker.exe`.
- **Publish must stop the apps first.** A running single-file exe locks
  `exe\*.exe`, so `dotnet publish` can't overwrite it. If elevated instances are
  running, run Publish from an **elevated** shell (a Medium `Stop-Process` can't kill
  them → files stay locked → publish fails). If the apps aren't running, a
  non-elevated Publish is fine.
- **Relaunch needs no elevation** — launching `WinUtility.exe` (or the task)
  auto-elevates via the RUNASADMIN layer (UAC may prompt).
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
- Needs a GitHub token (gh CLI or git credential).
- **Elevation:** `Update.ps1` relaunches `WinUtility.exe` via `Start-Process`
  (ShellExecute), which triggers the **RUNASADMIN auto-elevation** — so the
  relaunched WinUtility + trio come up **elevated even from a non-elevated shell**
  (UAC may prompt). Verified: run from a Medium shell, the new `WinUtility.exe` is
  High integrity. The only catch is its `Stop-Process` step — from a non-elevated
  shell it can't kill an already-running elevated instance, so run `Update.ps1` when
  the apps are stopped (otherwise the old elevated copy keeps running and the
  single-instance mutex blocks the fresh launch).

## Versioning

- Single shared `<Version>` in `WinUtility/WinUtility.csproj` covers all 4 apps.
- `Publish.ps1` auto-bumps: minor +0.01 until the minor part hits 15, then rolls to
  the next whole number (e.g. 2.15 → 3.0).

## Notes

- If you only need a compile check (not a runtime test), a plain
  `dotnet build <project>.csproj -c Debug` is fine — just don't expect launching the
  loose exe to exercise the change.
- `exe\WinUtility.exe` carries a **RUNASADMIN** AppCompat layer, so it (and the trio
  it spawns) always run **elevated** regardless of the launching shell. Elevation is
  only needed to *kill* those elevated processes (e.g. Publish's `Stop-Process`) —
  never to launch them.
