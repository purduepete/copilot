<#
.SYNOPSIS
  Read your Microsoft 365 calendar from local classic Outlook via COM (no UI, no sign-in).

.DESCRIPTION
  Microsoft Graph access is blocked in this tenant (user consent is disabled, so the
  Graph CLI app needs admin approval; first-party apps return AADSTS65002 "not
  preauthorized"). Instead this reads classic Outlook (Office16) through COM using your
  existing signed-in profile.

  It instantiates Outlook purely as a COM automation server and logs on to MAPI, so
  NO Outlook window is shown (if classic Outlook isn't already running, a hidden
  background instance is started). If you already have classic Outlook open, it simply
  attaches to it.

  Caveats:
    * Your default client is "new Outlook" (olk.exe), which has NO automation API.
      This uses CLASSIC OUTLOOK.EXE, which still has your mailbox/profile.
    * A modal "Reminder(s)" dialog in an already-open Outlook can block COM activation
      (CO_E_SERVER_EXEC_FAILURE); the script dismisses it and retries.

  Writes raw events to worklog\.secrets\calendar.json (git-ignored) and prints a table.

.EXAMPLE
  pwsh -File .\Get-Calendar.ps1                 # today
  pwsh -File .\Get-Calendar.ps1 -Date 2026-06-16
  pwsh -File .\Get-Calendar.ps1 -Start 2026-06-15 -End 2026-06-18
#>
[CmdletBinding()]
param(
    [datetime]$Date,
    [datetime]$Start,
    [datetime]$End,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$Secrets = Join-Path $PSScriptRoot '.secrets'
if (-not (Test-Path $Secrets)) { New-Item -ItemType Directory -Path $Secrets -Force | Out-Null }

# Resolve range (local time). Default = today.
if ($Date)           { $Start = $Date.Date; $End = $Start.AddDays(1) }
elseif (-not $Start) { $Start = (Get-Date).Date; $End = $Start.AddDays(1) }
elseif (-not $End)   { $End   = $Start.Date.AddDays(1) }

if (-not ([System.Management.Automation.PSTypeName]'Win').Type) {
    Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class Win {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] public static extern int EnumWindows(EnumProc cb,IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h,StringBuilder s,int m);
  public delegate bool EnumProc(IntPtr h,IntPtr l);
}
"@
}

function Dismiss-ReminderDialog {
    $closed = $false
    $cb = [Win+EnumProc]{ param($h,$l)
        $sb = New-Object System.Text.StringBuilder 256
        [Win]::GetWindowText($h,$sb,256) | Out-Null
        if ($sb.ToString() -match 'Reminder') { [Win]::PostMessage($h,0x0010,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null; $script:closed = $true }
        return $true
    }
    [Win]::EnumWindows($cb,[IntPtr]::Zero) | Out-Null
    if ($closed) { Start-Sleep -Seconds 3 }
}

function Read-CalendarRange($from,$to) {
    # Pure COM automation server -> no Outlook window is displayed.
    $ol = New-Object -ComObject Outlook.Application
    $ns = $ol.GetNamespace('MAPI')
    try { $ns.Logon($null,$null,$false,$false) } catch { }   # silent logon to default profile
    $cal = $ns.GetDefaultFolder(9)   # olFolderCalendar
    $items = $cal.Items
    $items.IncludeRecurrences = $true
    $items.Sort('[Start]')
    $filter = "[Start] >= '{0}' AND [Start] < '{1}'" -f $from.ToString('MM/dd/yyyy hh:mm tt'), $to.ToString('MM/dd/yyyy hh:mm tt')
    $restricted = $items.Restrict($filter)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($a in $restricted) {
        $list.Add([pscustomobject]@{
            Start     = $a.Start
            End       = $a.End
            Subject   = $a.Subject
            Location  = $a.Location
            AllDay    = $a.AllDayEvent
            Busy      = "$($a.BusyStatus)"
            Organizer = $a.Organizer
        })
    }
    # De-dup identical Start+Subject (recurrence/peek artifacts)
    $list | Sort-Object Start | Group-Object { "$($_.Start.Ticks)|$($_.Subject)" } | ForEach-Object { $_.Group[0] }
}

$events = $null
for ($i = 1; $i -le 8; $i++) {
    try { $events = @(Read-CalendarRange $Start $End); break }
    catch {
        if ($_.Exception.Message -match 'not connected|CO_E_SERVER_EXEC_FAILURE|0x80080005|call was rejected|RPC') {
            Dismiss-ReminderDialog; Start-Sleep -Seconds 8
        } else { throw }
    }
}
if ($null -eq $events) {
    throw "Could not read calendar via classic Outlook COM. Ensure classic Outlook (Office16) is installed and its profile can connect."
}

($events | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $Secrets 'calendar.json') -Encoding UTF8

if (-not $Quiet) {
    Write-Host ("Calendar {0:yyyy-MM-dd} -> {1:yyyy-MM-dd}  ({2} event(s))" -f $Start, $End, $events.Count)
    $events | ForEach-Object {
        [pscustomobject]@{
            Date    = $_.Start.ToString('MM-dd')
            Start   = if ($_.AllDay) { 'all-day' } else { $_.Start.ToString('HH:mm') }
            End     = if ($_.AllDay) { '' } else { $_.End.ToString('HH:mm') }
            Subject = $_.Subject
            Where   = $_.Location
        }
    } | Format-Table -AutoSize
}

$events
