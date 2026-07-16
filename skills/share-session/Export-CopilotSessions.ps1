<#
.SYNOPSIS
  Export (push) Copilot CLI session transcripts to a shared OneDrive folder so they
  can be read, summarized, or resumed from another computer.

.DESCRIPTION
  Copies each local Copilot CLI session-state folder (which holds events.jsonl -- the
  full dialog + tool actions -- plus plan.md, checkpoints\, session.db, workspace.yaml)
  into the shared drop:

     <ShareRoot>\<yyyy-MM-dd>\<COMPUTERNAME>\<session-id>\

  Run this on the machine you worked on, let OneDrive finish syncing (green check),
  then on the other machine use Import-CopilotSessions.ps1 (or just ask Copilot to read
  the drop folder) to summarize or resume.

  A manifest.json is written per <date>\<computer> with each session's id, last-active
  time, cwd, and summary. Exports older than -RetentionDays are pruned automatically.

.PARAMETER Days
  How many days back to include, based on each session's newest inner file. Default 5.
  0 = today only. Ignored when -All is set.

.PARAMETER All
  Export every local session regardless of date.

.PARAMETER TranscriptOnly
  Also emit a slimmed <session-id>.dialog.jsonl (user + assistant messages only, no
  tool output) next to each copy, for a lighter/redacted share.

.PARAMETER ShareRoot
  Override the destination root. Default resolves to
  "<OneDrive - Microsoft>\copilot-session-share".

.PARAMETER RetentionDays
  Prune <yyyy-MM-dd> export folders in ShareRoot older than this many days. Default 14.

.PARAMETER NoPrune
  Skip retention pruning for this run.

.PARAMETER Json
  Emit a machine-readable JSON summary of what was exported (for agent consumption)
  instead of the human-friendly text.

.EXAMPLE
  .\Export-CopilotSessions.ps1
  # last 5 days of sessions -> default OneDrive share, prune >14 days

.EXAMPLE
  .\Export-CopilotSessions.ps1 -Days 0 -TranscriptOnly
  # today only, dialog-only slim copies
#>
[CmdletBinding()]
param(
    [int]    $Days = 5,
    [switch] $All,
    [switch] $TranscriptOnly,
    [string] $ShareRoot,
    [int]    $RetentionDays = 14,
    [switch] $NoPrune,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'

function Resolve-ShareRoot {
    param([string] $Override)
    if ($Override) { return $Override }
    # Prefer the work OneDrive ("OneDrive - Microsoft"), then any OneDrive*, then profile.
    $candidates = @()
    if ($env:OneDriveCommercial) { $candidates += $env:OneDriveCommercial }
    $candidates += Get-ChildItem $env:USERPROFILE -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OneDrive - *' } | Select-Object -Expand FullName
    if ($env:OneDrive) { $candidates += $env:OneDrive }
    $base = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $base) { $base = $env:USERPROFILE }
    return (Join-Path $base 'copilot-session-share')
}

# --- Source: local Copilot CLI session state --------------------------------
$srcRoot = Join-Path $env:USERPROFILE '.copilot\session-state'
if (-not (Test-Path $srcRoot)) {
    throw "No Copilot session-state found at: $srcRoot"
}

$shareRootResolved = Resolve-ShareRoot -Override $ShareRoot
$stamp = Get-Date -Format 'yyyy-MM-dd'
$dst   = Join-Path $shareRootResolved (Join-Path $stamp $env:COMPUTERNAME)
New-Item -ItemType Directory -Force $dst | Out-Null

# --- Session selection ------------------------------------------------------
# "Last active" = newest file INSIDE the session folder; the folder's own
# LastWriteTime does not update when contained files change.
function Get-SessionLastActive {
    param([System.IO.DirectoryInfo] $Dir)
    $newest = Get-ChildItem $Dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) { $newest.LastWriteTime } else { $Dir.LastWriteTime }
}

function Get-WorkspaceField {
    param([string] $SessionDir, [string] $Field)
    $wf = Join-Path $SessionDir 'workspace.yaml'
    if (-not (Test-Path $wf)) { return $null }
    $line = Get-Content $wf -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Field))\s*:\s*(.+?)\s*$" } |
        Select-Object -First 1
    if ($line -and $line -match "^\s*$([regex]::Escape($Field))\s*:\s*(.+?)\s*$") {
        return $matches[1].Trim()
    }
    return $null
}

$cutoff = (Get-Date).Date.AddDays(-1 * [math]::Abs($Days))
$sessions = Get-ChildItem $srcRoot -Directory |
    Where-Object { $_.Name -match '^[0-9a-f]{8}-' } |
    ForEach-Object {
        $_ | Add-Member -NotePropertyName LastActive `
            -NotePropertyValue (Get-SessionLastActive $_) -PassThru -Force
    } | Where-Object { $All -or ($_.LastActive.Date -ge $cutoff) }

# --- Retention prune (only within our own share root) -----------------------
$pruned = @()
if (-not $NoPrune -and (Test-Path $shareRootResolved)) {
    $pruneCutoff = (Get-Date).Date.AddDays(-1 * [math]::Abs($RetentionDays))
    Get-ChildItem $shareRootResolved -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } |
        ForEach-Object {
            $d = [datetime]::MinValue
            if ([datetime]::TryParseExact($_.Name, 'yyyy-MM-dd', $null, 'None', [ref]$d) `
                    -and $d -lt $pruneCutoff) {
                $pruned += $_.Name
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
}

if (-not $sessions) {
    if ($Json) {
        [pscustomobject]@{
            shareRoot = $shareRootResolved; destination = $dst
            exported = @(); pruned = $pruned; count = 0
        } | ConvertTo-Json -Depth 4
    } else {
        Write-Warning "No sessions matched (Days=$Days, All=$All). Nothing to export."
        if ($pruned) { Write-Host "Pruned old export dates: $($pruned -join ', ')" }
    }
    return
}

# --- Copy + optional slim transcript ---------------------------------------
$exported = @()
foreach ($s in $sessions) {
    $target = Join-Path $dst $s.Name
    Copy-Item $s.FullName -Destination $target -Recurse -Force
    # Don't ship the local lock file.
    Get-ChildItem $target -Filter 'inuse*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if ($TranscriptOnly) {
        $events = Join-Path $target 'events.jsonl'
        if (Test-Path $events) {
            $slim = Join-Path $target ("{0}.dialog.jsonl" -f $s.Name)
            Get-Content $events | ForEach-Object {
                try { $o = $_ | ConvertFrom-Json } catch { return }
                if ($o.type -in @('user.message', 'assistant.message')) { $_ }
            } | Set-Content -Encoding UTF8 $slim
        }
    }

    $exported += [pscustomobject]@{
        session    = $s.Name
        lastActive = $s.LastActive.ToString('s')
        computer   = $env:COMPUTERNAME
        cwd        = (Get-WorkspaceField $target 'cwd')
        summary    = (Get-WorkspaceField $target 'name')
    }
    if (-not $Json) {
        Write-Host ("  + {0}  ({1})  [{2}]" -f `
            $s.Name, $s.LastActive.ToString('yyyy-MM-dd HH:mm'), $exported[-1].summary)
    }
}

# --- Manifest ---------------------------------------------------------------
$exported | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $dst 'manifest.json')

# --- Report -----------------------------------------------------------------
if ($Json) {
    [pscustomobject]@{
        shareRoot = $shareRootResolved; destination = $dst
        exported = $exported; pruned = $pruned; count = $exported.Count
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host ""
    Write-Host "Exported $($exported.Count) session(s) to:" -ForegroundColor Green
    Write-Host "  $dst"
    if ($pruned) { Write-Host "Pruned old export dates: $($pruned -join ', ')" -ForegroundColor DarkGray }
    Write-Host "Let OneDrive finish syncing (green check), then on the other machine run" -ForegroundColor Yellow
    Write-Host "Import-CopilotSessions.ps1 (or ask Copilot to read the share)." -ForegroundColor Yellow
}
