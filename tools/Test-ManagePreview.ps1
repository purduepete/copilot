#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'Manage-Preview.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) "preview-test-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($root) | Out-Null
$server = Join-Path $root 'fixture with spaces.cjs'
$node = (Get-Command node -CommandType Application).Source
$supervisor = $null
$unrelated = $null
$env:PREVIEW_TEST_MARKER = 'argument preserved'

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    Write-Host "PASS: $Message"
}
function Free-Port {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}
function Start-Fixture([string[]]$Values) {
    $start = [Diagnostics.ProcessStartInfo]::new($node)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    foreach ($value in $Values) { $start.ArgumentList.Add($value) }
    return [Diagnostics.Process]::Start($start)
}
function Start-Supervisor([int]$Port, [string]$Name = 'fixture', [switch]$Fail) {
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $parameters = @{
        Action = 'Start'; App = $Name; Session = 'test-session'; StateRoot = $root
        WorkingDirectory = $root; Executable = $node; Url = "http://127.0.0.1:$Port/"
        TimeoutSeconds = 3; Arguments = @($server, "$Port", $(if ($Fail) { 'wrong argument' } else { 'argument preserved' }))
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($parameters | ConvertTo-Json)))
    $command = "`$parameters = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json -AsHashtable; & '$helper' @parameters"
    foreach ($value in @('-NoProfile', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))) {
        $start.ArgumentList.Add($value)
    }
    return [Diagnostics.Process]::Start($start)
}

try {
    @'
const http = require('node:http');
const {spawn} = require('node:child_process');
const port = Number(process.argv[2]);
if (process.argv[3] !== process.env.PREVIEW_TEST_MARKER) process.exit(9);
if (!process.argv.includes('child')) {
  spawn(process.execPath, [__filename, '0', process.argv[3], 'child'], {stdio:'ignore'});
}
http.createServer((req,res) => res.end('ok')).listen(port, '127.0.0.1');
'@ | Set-Content -LiteralPath $server
    $port = Free-Port
    $supervisor = Start-Supervisor $port
    $deadline = [datetime]::Now.AddSeconds(20)
    $recordPath = Join-Path $root 'fixture.json'
    do {
        if ($supervisor.HasExited) {
            throw "Supervisor failed: $($supervisor.StandardError.ReadToEnd())"
        }
        Start-Sleep -Milliseconds 300
        $status = @(& $helper -Action Status -StateRoot $root -App fixture)
        $record = if (Test-Path -LiteralPath $recordPath) { Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json }
    } until (($status.Count -and $status[0].Ready -and $record.Processes.Count -ge 2) -or [datetime]::Now -ge $deadline)
    Assert ($status.Count -and $status[0].Ready) 'Server with spaced path and argument reaches HTTP 200'
    $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    Assert ($record.Processes.Count -ge 2) 'Supervisor tracks launcher and child identities'
    $reuse = & $helper -Action Start -App fixture -Session test-session -StateRoot $root
    Assert ($reuse -like 'Reusing*') 'Same session reuses preview without another launch'
    $refused = $false
    try { & $helper -Action Stop -App fixture -Session another-session -StateRoot $root }
    catch { $refused = $_ -like '*belongs to session*' }
    Assert $refused 'Another session cannot stop the preview'
    $refused = $false
    try { & $helper -Action Start -App occupied -Session test-session -StateRoot $root -WorkingDirectory $root -Executable $node -Url "http://127.0.0.1:$port/" }
    catch { $refused = $_ -like '*already occupied*' }
    Assert $refused 'Untracked occupied port is refused without stopping its listener'
    $unrelated = Start-Fixture @($server, '0', 'argument preserved', 'child')
    & $helper -Action Stop -App fixture -Session test-session -StateRoot $root
    Assert ($supervisor.WaitForExit(10000) -and $supervisor.ExitCode -eq 0) 'Supervisor exits cleanly'
    foreach ($identity in $record.Processes) {
        Assert (-not (Get-Process -Id $identity.Id -ErrorAction SilentlyContinue)) "Tracked process $($identity.Id) exited"
    }
    Assert (-not (Test-Path -LiteralPath $recordPath)) 'Successful stop removes ownership record'
    Assert (-not (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)) 'Preview port is released'
    Assert (-not $unrelated.HasExited) 'Unrelated Node process survives cleanup'
    $badPort = Free-Port
    $failed = Start-Supervisor $badPort 'failed' -Fail
    try {
        Assert ($failed.WaitForExit(20000) -and $failed.ExitCode -ne 0) 'Failed launcher reports an error'
        Assert (-not (Test-Path -LiteralPath (Join-Path $root 'failed.json'))) 'Failed start cleans up its ownership record'
    }
    finally {
        if (-not $failed.HasExited) {
            & $helper -Action Stop -App failed -Session test-session -StateRoot $root
            $failed.WaitForExit(10000) | Out-Null
        }
        $failed.Dispose()
    }
    $crashPort = Free-Port
    $crashed = Start-Supervisor $crashPort 'crash'
    try {
        $deadline = [datetime]::Now.AddSeconds(20)
        do {
            Start-Sleep -Milliseconds 300
            $crashStatus = @(& $helper -Action Status -App crash -StateRoot $root)
        } until (($crashStatus.Count -and $crashStatus[0].Ready) -or [datetime]::Now -ge $deadline)
        Assert ($crashStatus.Count -and $crashStatus[0].Ready) 'Crash fixture reaches readiness'
        $crashed.Kill()
        $crashed.WaitForExit()
        Start-Sleep -Seconds 1
        Assert (-not (Get-NetTCPConnection -State Listen -LocalPort $crashPort -ErrorAction SilentlyContinue)) 'Supervisor crash also releases the preview port'
        $stale = @(& $helper -Action Status -App crash -StateRoot $root)
        Assert ($stale[0].State -like 'Supervisor exited*') 'Status reports a stale supervisor explicitly'
        $refused = $false
        try { & $helper -Action Start -App crash -Session test-session -StateRoot $root }
        catch { $refused = $_ -like '*stale supervisor record*' }
        Assert $refused 'Stale records block duplicate launches pending inspection'
    }
    finally {
        if (-not $crashed.HasExited) {
            & $helper -Action Stop -App crash -Session test-session -StateRoot $root
            $crashed.WaitForExit(10000) | Out-Null
        }
        $crashed.Dispose()
    }
}
finally {
    if ($supervisor -and -not $supervisor.HasExited) {
        & $helper -Action Stop -App fixture -Session test-session -StateRoot $root
        $supervisor.WaitForExit(10000) | Out-Null
    }
    if ($unrelated) {
        if (-not $unrelated.HasExited) { $unrelated.Kill(); $unrelated.WaitForExit() }
        $unrelated.Dispose()
    }
    if ($supervisor) { $supervisor.Dispose() }
    Remove-Item Env:\PREVIEW_TEST_MARKER
    # This exact generated test directory contains only fixture files and logs.
    Remove-Item -LiteralPath $root -Recurse -Force
}
