---
name: windows-logon-task
description: >-
  Start a PowerShell script or app at Windows logon with no terminal window
  on screen. Covers the launcher pattern that actually hides a long-running
  console script, the scheduled-task shape to copy, the approaches that look
  right and fail, and how to verify the thing is really running.
  WHEN: "run this at login", "start at logon", "launch on startup", "run in
  the background at startup", "a terminal window stays open at login", "hide
  the console window", "scheduled task at logon", "why is a powershell window
  showing at startup", "make this start automatically", "autostart my script".
argument-hint: Which script or app should start at logon, and any arguments it needs
---

# Start something at Windows logon with no terminal window

## The one rule

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

## The task shape

Keep it plain. Copy `C:\Files\Dev\main\utility\Scripts\Install.ps1`.

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
