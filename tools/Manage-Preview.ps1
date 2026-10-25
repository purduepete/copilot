#Requires -Version 7.2
<#
Start is a foreground supervisor: invoke it with the powershell tool's async,
detach: true options. Status and Stop are short, synchronous operations.
Only processes launched by this supervisor are eligible for cleanup.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Start', 'Status', 'Stop')]
    [string]$Action,
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$App,
    [string]$Session,
    [string]$WorkingDirectory,
    [string]$Executable,
    [string[]]$Arguments = @(),
    [uri]$Url,
    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 30,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'Copilot\previews')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This helper requires Windows process identity and listener checks.' }
if ($Action -ne 'Status' -and (-not $App -or -not $Session)) {
    throw 'Start and Stop require -App and -Session.'
}
$StateRoot = [IO.Path]::GetFullPath($StateRoot)
[IO.Directory]::CreateDirectory($StateRoot) | Out-Null

function Get-Identity([int]$Id) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$Id"
    if ($process) {
        return [pscustomobject]@{
            Id = [int]$process.ProcessId
            Created = $process.CreationDate.ToUniversalTime().ToString('yyyyMMddHHmmssffffff')
            Path = $process.ExecutablePath
            Parent = [int]$process.ParentProcessId
        }
    }
}

function Test-Identity($Identity) {
    $current = Get-Identity $Identity.Id
    return ($null -ne $current -and $current.Created -eq $Identity.Created -and
        $current.Path -and $current.Path -eq $Identity.Path)
}

function Read-Record([string]$Path) {
    $record = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($record.Version -ne 1 -or $record.App -ne [IO.Path]::GetFileNameWithoutExtension($Path)) {
        throw "Invalid preview record: $Path"
    }
    return $record
}

function Test-Ready([uri]$Address) {
    try {
        $response = Invoke-WebRequest -Uri $Address -TimeoutSec 2 -MaximumRedirection 0 -SkipHttpErrorCheck
        return $response.StatusCode -eq 200
    }
    catch [System.Net.Http.HttpRequestException] { return $false }
    catch [System.Threading.Tasks.TaskCanceledException] { return $false }
}

function Test-RecordReady($Record) {
    if ($Record.State -ne 'Ready') { return $false }
    $address = [uri]$Record.Url
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $address.Port -ErrorAction SilentlyContinue)
    foreach ($listener in $listeners) {
        if ($listener.LocalAddress -notin @('127.0.0.1', '0.0.0.0', '::')) { continue }
        foreach ($identity in $Record.Processes) {
            if ($identity.Id -eq $listener.OwningProcess -and (Test-Identity $identity)) {
                return Test-Ready $address
            }
        }
    }
    return $false
}

if ($Action -eq 'Status') {
    foreach ($file in Get-ChildItem -LiteralPath $StateRoot -Filter '*.json') {
        if ($App -and $file.BaseName -ne $App) { continue }
        $record = Read-Record $file.FullName
        $alive = Test-Identity $record.Supervisor
        [pscustomobject]@{
            App = $record.App
            Session = $record.Session
            Url = $record.Url
            Pid = $record.Supervisor.Id
            StartedLocal = ([datetime]$record.Started).ToLocalTime()
            State = if ($alive) { $record.State } else { 'Supervisor exited; inspect tracked processes' }
            Ready = if ($alive) { Test-RecordReady $record } else { $false }
            Record = $file.FullName
        }
    }
    return
}

$recordPath = Join-Path $StateRoot "$App.json"
$stopPath = Join-Path $StateRoot "$App.stop"
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes($recordPath.ToLowerInvariant())))
$mutex = [Threading.Mutex]::new($false, "Local\CopilotPreview-$hash")
$locked = $false
try {
    try { $locked = $mutex.WaitOne(10000) }
    catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw "Another operation is changing preview '$App'. Try Status before retrying." }
    if (Test-Path -LiteralPath $recordPath) {
        $existing = Read-Record $recordPath
        if ($existing.Session -ne $Session) {
            throw "Preview '$App' belongs to session '$($existing.Session)'. Reuse its URL or obtain approval before stopping it."
        }
        if (-not (Test-Identity $existing.Supervisor)) {
            throw "Preview '$App' has a stale supervisor record. Inspect its tracked process identities before removing $recordPath."
        }
        if ($Action -eq 'Start') {
            if (-not (Test-RecordReady $existing)) { throw "Existing preview is not ready or its listener ownership changed: $($existing.Url). Inspect before restarting." }
            Write-Output "Reusing $($existing.Url) (session $Session, supervisor $($existing.Supervisor.Id))."
            return
        }
        [IO.File]::WriteAllText($stopPath, $Session)
        $deadline = [datetime]::Now.AddSeconds($TimeoutSeconds)
        while (Test-Path -LiteralPath $recordPath) {
            if ([datetime]::Now -ge $deadline) { throw "Stop timed out. Inspect $recordPath and the preview logs; do not kill an unverified PID." }
            Start-Sleep -Milliseconds 200
        }
        Write-Output "Stopped '$App'; tracked processes exited and its port was released."
        return
    }
    if ($Action -eq 'Stop') { throw "No tracked preview for '$App'. Untracked processes were left untouched." }
    if (-not $WorkingDirectory -or -not $Executable -or -not $Url) {
        throw 'Start requires -WorkingDirectory, -Executable, -Arguments (if needed), and -Url.'
    }
    if ($Url.Scheme -ne 'http' -or $Url.Host -ne '127.0.0.1') {
        throw 'Use an explicit http://127.0.0.1:PORT/ readiness URL for a local preview.'
    }
    $workingPath = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    $command = (Get-Command $Executable -CommandType Application -ErrorAction Stop).Source
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Url.Port -ErrorAction SilentlyContinue)
    if ($listeners.Count) { throw "Port $($Url.Port) is already occupied. Inspect and reuse it; no process was stopped." }
    if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $command
    $start.WorkingDirectory = $workingPath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $start
    # Windows owns tree membership, including children spawned between inventory polls.
    if (-not ('CopilotPreviewJob' -as [type])) {
        Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public sealed class CopilotPreviewJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimits {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Limits {
        public BasicLimits Basic;
        public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetInformationJobObject(SafeFileHandle job, int kind, ref Limits limits, uint size);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
    readonly SafeFileHandle handle;
    public CopilotPreviewJob() {
        handle = CreateJobObject(IntPtr.Zero, null);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        var limits = new Limits();
        limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if (!SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf<Limits>())) {
            int error = Marshal.GetLastWin32Error();
            handle.Dispose();
            throw new Win32Exception(error);
        }
    }
    public void Assign(IntPtr process) {
        if (!AssignProcessToJobObject(handle, process))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    public void Dispose() { handle.Dispose(); }
}
'@
    }
    $job = [CopilotPreviewJob]::new()
    $tracked = [Collections.Generic.Dictionary[int, object]]::new()
    $streams = @()
    $copies = @()
    $record = [ordered]@{
        Version = 1; App = $App; Session = $Session; Url = $Url.AbsoluteUri
        Started = [datetime]::Now.ToString('o'); State = 'Starting'
        Supervisor = Get-Identity $PID; Processes = @()
    }
    function Save-Record {
        $record.Processes = @($tracked.Values)
        $temporary = "$recordPath.tmp"
        [IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json -Depth 6))
        Move-Item -LiteralPath $temporary -Destination $recordPath -Force
    }
    function Update-Tracked {
        $all = @(Get-CimInstance Win32_Process)
        do {
            $added = $false
            foreach ($candidate in $all) {
                $parent = [int]$candidate.ParentProcessId
                $id = [int]$candidate.ProcessId
                if ($tracked.ContainsKey($id) -or -not $tracked.ContainsKey($parent)) { continue }
                if (-not (Test-Identity $tracked[$parent])) { continue }
                $created = $candidate.CreationDate.ToUniversalTime().ToString('yyyyMMddHHmmssffffff')
                if ([string]::CompareOrdinal($created, $tracked[$parent].Created) -lt 0) { continue }
                $tracked[$id] = [pscustomobject]@{
                    Id = $id; Created = $created
                    Path = $candidate.ExecutablePath; Parent = $parent
                }
                $added = $true
            }
        } while ($added)
        Save-Record
    }
    try {
        # Write ownership before launching so a failed start never looks untracked.
        Save-Record
        if (-not $child.Start()) { throw "Could not launch preview '$App'." }
        try { $job.Assign($child.Handle) }
        catch {
            $assignmentError = $_
            if (-not $child.HasExited) { $child.Kill($true); $child.WaitForExit() }
            throw $assignmentError
        }
        $identity = Get-Identity $child.Id
        if (-not $identity -or -not $identity.Path) { throw 'Preview exited before its identity could be recorded.' }
        $tracked[$identity.Id] = $identity
        foreach ($name in 'out', 'err') {
            $stream = [IO.File]::Create((Join-Path $StateRoot "$App.$name.log"))
            $streams += $stream
            $reader = if ($name -eq 'out') { $child.StandardOutput } else { $child.StandardError }
            $copies += $reader.BaseStream.CopyToAsync($stream)
        }
        Save-Record
        $mutex.ReleaseMutex()
        $locked = $false
        $deadline = [datetime]::Now.AddSeconds($TimeoutSeconds)
        $heartbeat = [datetime]::Now
        while (-not (Test-Path -LiteralPath $stopPath)) {
            Update-Tracked
            if ($child.HasExited) { throw "Preview launcher exited with code $($child.ExitCode). See $App.err.log." }
            if ($record.State -eq 'Starting') {
                $owners = @(Get-NetTCPConnection -State Listen -LocalPort $Url.Port -ErrorAction SilentlyContinue)
                $owned = @($owners | Where-Object {
                    $tracked.ContainsKey([int]$_.OwningProcess) -and (Test-Identity $tracked[[int]$_.OwningProcess])
                })
                if ($owned.Count -and (Test-Ready $Url)) {
                    $record.State = 'Ready'
                    Save-Record
                    Write-Output "Ready: $Url (app $App, session $Session, supervisor $PID)."
                }
                elseif ([datetime]::Now -ge $deadline) { throw "Preview did not become ready within $TimeoutSeconds seconds." }
            }
            if ([datetime]::Now -ge $heartbeat) {
                Write-Output "$App $($record.State); elapsed $([int]([datetime]::Now - [datetime]$record.Started).TotalSeconds)s."
                $heartbeat = [datetime]::Now.AddSeconds(30)
            }
            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        # Keep the record on cleanup failure so nobody mistakes it for a clean stop.
        try { Update-Tracked }
        finally { $job.Dispose() }
        foreach ($identity in @($tracked.Values | Sort-Object Created -Descending)) {
            if (Test-Identity $identity) {
                $process = Get-Process -Id $identity.Id -ErrorAction Stop
                try {
                    if ($process.StartTime.ToUniversalTime().ToString('yyyyMMddHHmmssffffff') -ne $identity.Created) {
                        throw "Process $($identity.Id) changed identity during cleanup."
                    }
                    if (-not $process.WaitForExit(5000)) { throw "Process $($identity.Id) did not exit." }
                }
                finally { $process.Dispose() }
            }
        }
        foreach ($copy in $copies) { $copy.GetAwaiter().GetResult() | Out-Null }
        foreach ($stream in $streams) { $stream.Dispose() }
        $child.Dispose()
        $remaining = @(Get-NetTCPConnection -State Listen -LocalPort $Url.Port -ErrorAction SilentlyContinue)
        if ($remaining.Count) { throw "Port $($Url.Port) still has a listener. Ownership record retained for inspection." }
        Remove-Item -LiteralPath $recordPath
        if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
    }
}
finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
