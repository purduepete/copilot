<#
.SYNOPSIS
  Start or stop the Work Log live-edit dashboard server.

.DESCRIPTION
  start    launches the dashboard web server in the background and opens it in your
           browser. Edit any row (start/end time, category, project, item,
           accomplishment); Save writes the change instantly and rebuilds the page.
  stop     shuts the background server down.
  status   reports whether it is running.
  restart  stop + start.

  The running server's process id + port are tracked in `.dashboard-server.json`
  next to this script.

.PARAMETER Action
  start (default) | stop | status | restart

.PARAMETER Port
  Port to serve on. Default 8787.

.PARAMETER Profile
  Which log profile to edit (e.g. work, personal). Defaults to this machine's default.

.PARAMETER NoOpen
  Start without opening a browser window.

.EXAMPLE
  pwsh -File Edit-Dashboard.ps1 start

.EXAMPLE
  pwsh -File Edit-Dashboard.ps1 stop

.EXAMPLE
  pwsh -File Edit-Dashboard.ps1 start -Profile personal -Port 9000
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'restart')]
    [string]$Action = 'start',
    [int]$Port = 8787,
    [string]$Profile = '',
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$PidFile = Join-Path $PSScriptRoot '.dashboard-server.json'

function Get-ServerInfo {
    if (-not (Test-Path -LiteralPath $PidFile)) { return $null }
    try { $info = Get-Content -LiteralPath $PidFile -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $info.pid) { return $null }
    $proc = Get-Process -Id $info.pid -ErrorAction SilentlyContinue
    if (-not $proc) { return $null }
    return $info
}

function Stop-Server {
    $info = Get-ServerInfo
    if (-not $info) {
        if (Test-Path -LiteralPath $PidFile) { Remove-Item -LiteralPath $PidFile -Force }
        Write-Host 'Dashboard server is not running.'
        return
    }
    Stop-Process -Id $info.pid -Force
    Remove-Item -LiteralPath $PidFile -Force
    Write-Host "Stopped dashboard server (pid $($info.pid), port $($info.port))."
}

function Start-Server {
    $existing = Get-ServerInfo
    if ($existing) {
        $url = "http://localhost:$($existing.port)/"
        Write-Host "Dashboard server already running (pid $($existing.pid)) at $url"
        if (-not $NoOpen) { Start-Process $url }
        return
    }

    $modulePath = Join-Path $PSScriptRoot 'WorkLog.psm1'
    $cmd = @(
        "Import-Module '$modulePath' -Force"
        $(if ($Profile) { "Set-WorkProfile -Profile '$Profile' | Out-Null" } else { '' })
        "Start-WorkServer -Port $Port -NoOpen"
    ) -join '; '

    $proc = Start-Process -FilePath 'pwsh' `
        -ArgumentList '-NoProfile', '-Command', $cmd `
        -WindowStyle Hidden -PassThru

    @{ pid = $proc.Id; port = $Port; profile = $Profile } |
        ConvertTo-Json | Set-Content -LiteralPath $PidFile -Encoding UTF8

    # Wait for the server to come up.
    $url = "http://localhost:$Port/"
    $up = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 300
        if ($proc.HasExited) { break }
        try { Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2 | Out-Null; $up = $true; break } catch {}
    }

    if (-not $up) {
        if (Test-Path -LiteralPath $PidFile) { Remove-Item -LiteralPath $PidFile -Force }
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
        throw "Dashboard server failed to start on $url (port may already be in use)."
    }

    Write-Host "Dashboard server started (pid $($proc.Id)) at $url"
    Write-Host "Stop it with:  pwsh -File `"$PSCommandPath`" stop"
    if (-not $NoOpen) { Start-Process $url }
}

function Show-Status {
    $info = Get-ServerInfo
    if ($info) { Write-Host "Running: pid $($info.pid), http://localhost:$($info.port)/ (profile: $(if ($info.profile) { $info.profile } else { 'default' }))" }
    else       { Write-Host 'Dashboard server is not running.' }
}

switch ($Action) {
    'start'   { Start-Server }
    'stop'    { Stop-Server }
    'status'  { Show-Status }
    'restart' { Stop-Server; Start-Server }
}
