---
name: windows-logon-task
description: >-
  Start a PowerShell script, service or app automatically on Windows. Defaults
  to a system-startup task that runs with nobody signed in, and covers the
  logon-task exception for work that needs the user session: the launcher
  pattern that hides a long-running console script, the task shapes to copy,
  the approaches that look right and fail, and how to verify it is running.
  WHEN: "run this at login", "start at logon", "launch on startup", "run in
  the background at startup", "a terminal window stays open at login", "hide
  the console window", "scheduled task at logon", "why is a powershell window
  showing at startup", "make this start automatically", "autostart my script",
  "run at boot", "start without signing in", "run whether logged on or not".
argument-hint: Which script or app should start automatically, and any arguments it needs
---

# Start something automatically on Windows

## Startup first

Default to a **system-startup task**. It runs after a reboot with nobody signed
in, and it runs in session 0, so no window can ever appear on a desktop.

Use a logon task only when the workload needs the signed-in user session:

- a per-user mount, such as the Google Drive for Desktop `G:` drive (the
  FitTrack upload watcher is the standing example)
- a tray icon or any UI the user sees
- a per-user app that only exists in that profile

State that reason in the task's `-Description`. "It was easier" is not a reason.

### Startup task shape

Copy `solution-deploy\scripts\Install-LanProxy.ps1`. Registration needs an
elevated session.

```powershell
$pwsh = 'C:\ProgramData\SolutionDeploy\runtime\powershell\7\pwsh.exe'
$action = New-ScheduledTaskAction -Execute $pwsh -WorkingDirectory $root `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$root\Start-Thing.ps1`""
$triggers = @(New-ScheduledTaskTrigger -AtStartup)
# Only for a repeat-safe watchdog (see below):
# $triggers += New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-19' -LogonType ServiceAccount -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([timespan]::Zero) -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskPath '\JimlerTech\' -TaskName $taskName -Action $action -Trigger $triggers `
    -Principal $principal -Settings $settings -Description '...' -Force | Out-Null
```

- `S-1-5-19` is `LOCAL SERVICE`. Use it when the work needs no network
  credentials or secrets of its own.
- When it needs its own file ACLs or database login, use a dedicated non-admin
  local account with `-LogonType Password` and a stored password. SolutionDeploy
  app tasks do this through `Install-AppBootTask` in `src\Lifecycle.psm1`. Keep
  that password in a DPAPI credential file under
  `C:\ProgramData\SolutionDeploy\control\task-credentials`, because changing the
  task later (even its executable path) asks for it again.
- Never S4U or `SYSTEM` for app workloads. `SYSTEM` is for host plumbing such as
  the executor and backups.
- The startup trigger alone is the default. `-RestartCount` retries a failed
  launch.
- Add the repeat trigger only when the task needs periodic retries or
  reconciliation, and only when every run is safe to repeat. That holds when
  the action blocks for the life of the workload (the FitTrack VBS waits on
  pwsh, which waits on python), or when the script checks for a live instance
  and exits if one exists (the SolutionDeploy watchdog checks the recorded PID
  and creation time).
- `IgnoreNew` only skips a run while the previous action is still running.
  If the action starts a detached process and exits, the next repeat starts
  a second copy. A launcher like that needs a singleton check before it gets
  a repeat.
- Put tasks in `\JimlerTech\` on jimbrownhome1.

### Launch PowerShell by full path

Never call bare `pwsh` or `pwsh.exe` from a task, a VBS or a launcher. On a
machine with the Store build, the name resolves to the WindowsApps alias, which
task accounts cannot run: the FitTrack watcher died with VBScript `800A0046`
(Permission denied) from exactly this. On jimbrownhome1, use the fixed runtime
`C:\ProgramData\SolutionDeploy\runtime\powershell\7\pwsh.exe`. Never hard-code a
versioned path such as `C:\Program Files\PowerShell\7.6.7\pwsh.exe`; it breaks on
the next PowerShell update.

### Verify a startup task

Start it by hand, then check the payload process and its listener or log. For a
real proof, reboot and check again **before** anyone signs in, using
`New-CimSession -Protocol Dcom` from another machine.

## Logon tasks: the one rule

**Never point a scheduled task at a long-running console script.** The task's
process owns a console for its whole life, and `-WindowStyle Hidden` is only
honored when the default terminal application is the old console host. Windows
Terminal ignores it and the window stays on screen.

Check which host a machine uses:

```powershell
Get-ItemProperty 'HKCU:\Console\%%Startup' | Select-Object DelegationConsole, DelegationTerminal
```

All-zero GUIDs mean the old console host, where hiding works. Anything else is
Windows Terminal, where it does not. Never rely on this being one value, because
it differs per machine and the failure only shows up at logon.

A GUI-subsystem `.exe` sidesteps all of it, since it never allocates a console.
That is why `WinUtility.exe` starts cleanly from a plain Interactive task.

## The pattern that works

Give the task a **launcher** that spawns the real process and exits. Redirect
both of the child's streams to files. That takes the `CreateProcess` path, and
the long-lived process gets a headless console host that is never drawn.

```powershell
$proc = Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $LogPath -RedirectStandardError $ErrorLogPath
Set-Content -Path $PidFile -Value $proc.Id
```

Both redirections are required. Redirecting one stream, or using PowerShell's
`*>>` inside a `-Command` string, leaves the console attached and the window
comes back.

Write the PID to a file so a matching stop function can kill it, and so the
installer can prove the process came up.

## The logon task shape

Only for the exceptions listed under "Startup first". Keep it plain. Copy `C:\Files\Dev\main\utility\Scripts\Install.ps1`.

```powershell
$argLine = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`" -Port $Port"
$action = New-ScheduledTaskAction -Execute $exe -Argument $argLine -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Description "..." | Out-Null
```

`-ExecutionTimeLimit 0` matters: the default kills the task after 3 days.

`-RunLevel Limited`, not `Highest`. Registering a `Highest` task from a normal
prompt fails with "Access is denied", and a launcher almost never needs admin.

## Always start it and verify

Register, then start it and confirm the real process exists. An installer that
reports success without watching the thing run wastes a whole round trip.

```powershell
Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName

$serverPid = $null
foreach ($attempt in 1..20) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $pidFile) {
        $candidate = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($candidate -and (Get-Process -Id $candidate -ErrorAction SilentlyContinue)) {
            $serverPid = $candidate; break
        }
    }
}
```

Because the launcher exits immediately, the task's own state says nothing about
whether the payload is alive. Check the PID, not the task.

Confirm there is no drawn window:

```powershell
Get-CimInstance Win32_Process -Filter "Name='conhost.exe'" |
    Where-Object ParentProcessId -eq $serverPid |
    Select-Object ProcessId, CommandLine
```

`conhost.exe 0x4` is the headless flag. That is the pass condition.

## Approaches that fail

| Approach | What happens |
|---|---|
| Task runs the console script directly with `-WindowStyle Hidden` | Window stays up under Windows Terminal |
| `$settings.Hidden = $true` | Only hides the task in the Task Scheduler UI |
| `pwsh -Command "& script *>> log"` | Console still attached, window still drawn |
| S4U principal ("run whether logged on or not") | Registration needs elevation; also silently returns a non-terminating "Access is denied" |
| `-RunLevel Highest` | Registration fails from a non-elevated prompt |
| Startup folder shortcut | Same console problem, plus no restart or logging |

## Diagnosing a task that "will not start"

1. `Get-ScheduledTaskInfo -TaskName '<name>' | Format-List LastRunTime, LastTaskResult`.
   `267011` is `0x00041303`, `SCHED_S_TASK_HAS_NOT_RUN`. It is not an error; the
   task has simply never been triggered. Start it by hand before diagnosing further.
2. Filter the event log with `FilterHashtable`, not `-MaxEvents` plus `Where-Object`.
   The latter takes the newest N events and then filters, so it finds nothing and
   proves nothing.
   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; StartTime=(Get-Date).AddMinutes(-10)}
   ```
3. If that log is empty, check it is on:
   `Get-WinEvent -ListLog Microsoft-Windows-TaskScheduler/Operational | Select-Object IsEnabled`
   and enable with `wevtutil sl Microsoft-Windows-TaskScheduler/Operational /e:true`.
4. Read the launcher's redirected error log. A payload that dies on startup shows
   up there and nowhere else.

## Reference implementation

`C:\Files\Dev\main\plex\desktop` (repo `purduepete/plex`):

- `Start-PlexWebUIHidden.ps1` is the launcher.
- `Install-PlexWebUIStartup.ps1` registers the task, starts it, and verifies the PID.
- `C:\Files\Dev\main\utility\Scripts\Install.ps1` is the task shape, for a GUI `.exe`.

## If a network listener is involved

Binding anything other than loopback needs a one-time elevated setup, or
`HttpListener` throws "Access is denied" and the payload dies the moment it starts:

```powershell
netsh http add urlacl url=http://+:<port>/ user=Everyone
New-NetFirewallRule -DisplayName '<name>' -Direction Inbound -Protocol TCP -LocalPort <port> -Action Allow
```
