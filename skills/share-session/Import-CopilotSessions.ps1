<#
.SYNOPSIS
  List, summarize, or import (pull/resume) Copilot CLI sessions that another computer
  shared via Export-CopilotSessions.ps1 through the OneDrive drop folder.

.DESCRIPTION
  Two modes:

  LIST (default) -- scan the shared drop and report available exports grouped by
    date + computer, with session id, last-active time, cwd, and summary. Use -Json
    for machine-readable output (e.g. for Copilot to pick from).

  IMPORT (-SessionId <id>) -- copy a shared session-state folder into this machine's
    local %USERPROFILE%\.copilot\session-state so Copilot can RESUME it. The inuse
    lock file is stripped. A folder copy is sufficient to resume by id (verified);
    the session may not appear in the bare `copilot --resume` picker until the CLI
    reindexes, but `copilot --resume=<id>` works immediately.

  Resuming only copies files; to actually continue the conversation, run the printed
  `copilot --resume=<id>` command yourself.

.PARAMETER ShareRoot
  Override the shared drop root. Default resolves to
  "<OneDrive - Microsoft>\copilot-session-share".

.PARAMETER SessionId
  Import this session id (accepts a 7+ char prefix). Omit to just LIST.

.PARAMETER Date
  Restrict to a specific export date folder (yyyy-MM-dd). Helps disambiguate.

.PARAMETER Computer
  Restrict to a specific source computer. Helps disambiguate.

.PARAMETER All
  Import EVERY session under the selected Date/Computer (requires -Date or -Computer,
  or will act across the whole share -- use with care).

.PARAMETER Force
  Overwrite a session folder that already exists locally (default: skip with a warning).

.PARAMETER Json
  Machine-readable output.

.EXAMPLE
  .\Import-CopilotSessions.ps1
  # list everything available in the share

.EXAMPLE
  .\Import-CopilotSessions.ps1 -SessionId da6bae75
  # import that session locally, then it prints: copilot --resume=<full-id>
#>
[CmdletBinding()]
param(
    [string] $ShareRoot,
    [string] $SessionId,
    [string] $Date,
    [string] $Computer,
    [switch] $All,
    [switch] $Force,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'

function Resolve-ShareRoot {
    param([string] $Override)
    if ($Override) { return $Override }
    $candidates = @()
    if ($env:OneDriveCommercial) { $candidates += $env:OneDriveCommercial }
    $candidates += Get-ChildItem $env:USERPROFILE -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OneDrive - *' } | Select-Object -Expand FullName
    if ($env:OneDrive) { $candidates += $env:OneDrive }
    $base = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $base) { $base = $env:USERPROFILE }
    return (Join-Path $base 'copilot-session-share')
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

$shareRootResolved = Resolve-ShareRoot -Override $ShareRoot
if (-not (Test-Path $shareRootResolved)) {
    throw "Share folder not found: $shareRootResolved  (has the other machine exported + synced yet?)"
}

# --- Enumerate available shared sessions ------------------------------------
# Layout: <ShareRoot>\<yyyy-MM-dd>\<COMPUTERNAME>\<session-id>\
$avail = @()
Get-ChildItem $shareRootResolved -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and (-not $Date -or $_.Name -eq $Date) } |
    ForEach-Object {
        $dateName = $_.Name
        Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $Computer -or $_.Name -eq $Computer } |
            ForEach-Object {
                $compName = $_.Name
                Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '^[0-9a-f]{8}-' } |
                    ForEach-Object {
                        $avail += [pscustomobject]@{
                            session  = $_.Name
                            date     = $dateName
                            computer = $compName
                            cwd      = (Get-WorkspaceField $_.FullName 'cwd')
                            summary  = (Get-WorkspaceField $_.FullName 'name')
                            path     = $_.FullName
                        }
                    }
            }
    }

$localRoot = Join-Path $env:USERPROFILE '.copilot\session-state'

# --- LIST mode --------------------------------------------------------------
if (-not $SessionId -and -not $All) {
    if ($Json) {
        $avail | Select-Object session, date, computer, cwd, summary |
            ConvertTo-Json -Depth 4
    } else {
        if (-not $avail) { Write-Host "No shared sessions found under $shareRootResolved"; return }
        Write-Host "Shared sessions in $shareRootResolved`n" -ForegroundColor Cyan
        $avail | Sort-Object date, computer, summary |
            Format-Table @{n='date';e={$_.date}},
                         @{n='computer';e={$_.computer}},
                         @{n='session';e={$_.session.Substring(0,8)}},
                         @{n='summary';e={$_.summary}},
                         @{n='cwd';e={$_.cwd}} -AutoSize -Wrap
        Write-Host "Import one with:  Import-CopilotSessions.ps1 -SessionId <id-or-prefix>" -ForegroundColor Yellow
    }
    return
}

# --- Select what to import --------------------------------------------------
$toImport = $avail
if ($SessionId) {
    $toImport = $avail | Where-Object { $_.session -like "$SessionId*" }
    if (-not $toImport) { throw "No shared session matches id '$SessionId' (with the given -Date/-Computer filters)." }
    if (($toImport | Select-Object -Expand session -Unique).Count -gt 1 -and -not $All) {
        $hits = ($toImport | ForEach-Object { "$($_.session) [$($_.date)/$($_.computer)]" }) -join "`n  "
        throw "Ambiguous id '$SessionId' matches multiple sessions:`n  $hits`nDisambiguate with -Date / -Computer, or pass a longer id."
    }
} elseif ($All -and -not $Date -and -not $Computer) {
    Write-Warning "Importing ALL shared sessions across every date/computer. Ctrl+C to abort."
}

# --- Import (copy + strip lock) --------------------------------------------
$results = @()
foreach ($item in $toImport) {
    $localPath = Join-Path $localRoot $item.session
    $status = 'imported'
    if (Test-Path $localPath) {
        if ($Force) {
            Remove-Item $localPath -Recurse -Force
        } else {
            $status = 'skipped-exists'
            $results += [pscustomobject]@{ session=$item.session; status=$status; cwd=$item.cwd }
            if (-not $Json) { Write-Warning "Skip $($item.session) -- already exists locally (use -Force to overwrite)." }
            continue
        }
    }
    Copy-Item $item.path -Destination $localPath -Recurse -Force
    Get-ChildItem $localPath -Filter 'inuse*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $cwdMissing = $item.cwd -and -not (Test-Path $item.cwd)
    $results += [pscustomobject]@{
        session = $item.session; status = $status; cwd = $item.cwd; cwdMissing = [bool]$cwdMissing
    }
    if (-not $Json) {
        Write-Host "Imported $($item.session)  [$($item.date)/$($item.computer)]" -ForegroundColor Green
        if ($cwdMissing) {
            Write-Warning "  Its cwd '$($item.cwd)' does not exist here -- resume will open in a missing directory."
        }
        Write-Host "  Resume:  copilot --resume=$($item.session)" -ForegroundColor Yellow
    }
}

if ($Json) { $results | ConvertTo-Json -Depth 4 }
