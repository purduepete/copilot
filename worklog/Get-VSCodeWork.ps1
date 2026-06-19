<#
.SYNOPSIS
  Parse VS Code Copilot chat transcripts into work "blocks" so you can quickly log work.

.DESCRIPTION
  Maps a workspace folder -> VS Code workspaceStorage hash, finds the relevant chat
  transcript(s), converts UTC event timestamps to local time, and groups user messages
  into blocks separated by idle gaps. For each block it prints the exact start/end time,
  duration, message count, first/last message snippets, and a ready-to-run Work.ps1
  command. It also lists git commits in the block window to help title the item.

.EXAMPLES
  # Today's work blocks for the current repo:
  pwsh -File Get-VSCodeWork.ps1

  # A specific folder / date / idle-gap threshold:
  pwsh -File Get-VSCodeWork.ps1 -Folder C:\Files\Dev\main\webportfolio -Date 2026-06-18 -GapMinutes 60

  # Fuzzy "what was I just doing" window (last 60 min), and create an item from it:
  pwsh -File Get-VSCodeWork.ps1 -LastMinutes 60
  pwsh -File Get-VSCodeWork.ps1 -LastMinutes 60 -Create

  # Machine-readable output:
  pwsh -File Get-VSCodeWork.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$Folder = (Get-Location).Path,
    [datetime]$Date = (Get-Date).Date,
    [int]$LastMinutes = 0,
    [int]$GapMinutes = 90,
    [int]$Snippet = 80,
    [switch]$IncludeTerminal,
    [switch]$Json,
    [switch]$Create,
    [int]$Block = 0,
    [string]$Title = '',
    [string]$Category = 'Dev'
)

$ErrorActionPreference = 'Stop'

function Resolve-WorkspaceHash {
    param([string]$Folder)
    $storage = Join-Path $env:APPDATA 'Code\User\workspaceStorage'
    if (-not (Test-Path $storage)) { throw "workspaceStorage not found: $storage" }
    # Normalise to a filesystem path for robust comparison (handles %3A, drive casing, slashes).
    $target = (Resolve-Path $Folder).Path.TrimEnd('\').Replace('/', '\').ToLowerInvariant()
    foreach ($d in Get-ChildItem $storage -Directory) {
        $wj = Join-Path $d.FullName 'workspace.json'
        if (-not (Test-Path $wj)) { continue }
        $f = (Get-Content $wj -Raw | ConvertFrom-Json).folder
        if (-not $f) { continue }
        $path = [uri]::UnescapeDataString($f) -replace '^file:///', '' -replace '/', '\'
        $path = $path.TrimEnd('\').ToLowerInvariant()
        if ($path -ieq $target) { return $d }
    }
    return $null
}

$ws = Resolve-WorkspaceHash -Folder $Folder
if (-not $ws) { throw "No VS Code workspace storage found for folder: $Folder" }

$tdir = Join-Path $ws.FullName 'GitHub.copilot-chat\transcripts'
if (-not (Test-Path $tdir)) { throw "No transcripts dir for this workspace: $tdir" }

# Time window: a fuzzy "last N minutes" takes precedence over the whole -Date day.
if ($LastMinutes -gt 0) {
    $dayStart = (Get-Date).AddMinutes(-$LastMinutes)
    $dayEnd   = (Get-Date).AddMinutes(1)   # small buffer so the just-typed message is included
    $rangeLabel = "last $LastMinutes min (since $($dayStart.ToString('HH:mm')))"
}
else {
    $dayStart = $Date.Date
    $dayEnd   = $dayStart.AddDays(1)
    $rangeLabel = $Date.ToString('yyyy-MM-dd')
}

# Collect user.message events across transcripts, converting UTC -> local.
$events = foreach ($file in Get-ChildItem $tdir -Filter '*.jsonl') {
    foreach ($line in Get-Content $file.FullName) {
        if ($line -notmatch '"user.message"') { continue }
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if ($o.type -ne 'user.message') { continue }
        $local = ([datetime]$o.timestamp).ToLocalTime()
        if ($local -lt $dayStart -or $local -ge $dayEnd) { continue }
        $content = [string]$o.data.content
        if (-not $IncludeTerminal -and $content -match '^\[Terminal ') { continue }
        [PSCustomObject]@{ Time = $local; Content = ($content -replace '\s+', ' ').Trim() }
    }
}
$events = $events | Sort-Object Time
if (-not $events) {
    Write-Host "No user messages found for $rangeLabel in workspace $($ws.Name.Substring(0,8))." -ForegroundColor Yellow
    return
}

# Group into blocks separated by > GapMinutes idle.
$blocks = @()
$cur = $null
foreach ($e in $events) {
    if ($null -eq $cur) {
        $cur = [ordered]@{ Start = $e.Time; End = $e.Time; Msgs = @($e) }
    }
    elseif (($e.Time - $cur.End).TotalMinutes -gt $GapMinutes) {
        $blocks += [pscustomobject]$cur
        $cur = [ordered]@{ Start = $e.Time; End = $e.Time; Msgs = @($e) }
    }
    else {
        $cur.End = $e.Time; $cur.Msgs += $e
    }
}
if ($cur) { $blocks += [pscustomobject]$cur }

if ($Json) {
    $blocks | ForEach-Object {
        [pscustomobject]@{
            start    = $_.Start.ToString('o')
            end      = $_.End.ToString('o')
            minutes  = [math]::Round(($_.End - $_.Start).TotalMinutes)
            count    = $_.Msgs.Count
            first    = $_.Msgs[0].Content
            last     = $_.Msgs[-1].Content
        }
    } | ConvertTo-Json -Depth 4
    return
}

Write-Host ""
Write-Host "Workspace : $Folder" -ForegroundColor Cyan
Write-Host "Hash      : $($ws.Name)"
Write-Host "Range     : $rangeLabel   GapMinutes: $GapMinutes"
Write-Host ("=" * 78)

$i = 0
foreach ($b in $blocks) {
    $i++
    $dur = [math]::Round(($b.End - $b.Start).TotalMinutes)
    $first = $b.Msgs[0].Content; if ($first.Length -gt $Snippet) { $first = $first.Substring(0, $Snippet) }
    $last = $b.Msgs[-1].Content;  if ($last.Length  -gt $Snippet) { $last  = $last.Substring(0, $Snippet) }
    Write-Host ""
    Write-Host ("Block {0}: {1} -> {2}  ({3}m, {4} msgs)" -f $i, $b.Start.ToString('HH:mm:ss'), $b.End.ToString('HH:mm:ss'), $dur, $b.Msgs.Count) -ForegroundColor Green
    Write-Host "  first: $first"
    Write-Host "  last : $last"

    # Git commits in the block window (if folder is a repo).
    Push-Location $Folder
    try {
        $since = $b.Start.AddMinutes(-5).ToString('yyyy-MM-dd HH:mm:ss')
        $until = $b.End.AddMinutes(5).ToString('yyyy-MM-dd HH:mm:ss')
        $commits = git --no-pager log --since="$since" --until="$until" --pretty=format:"    %h %ad %s" --date=format:"%H:%M" 2>$null
    } catch { $commits = $null }
    finally { Pop-Location }
    if ($commits) {
        Write-Host "  commits:"
        $commits | ForEach-Object { Write-Host $_ }
    }

    $titleGuess = ($b.Msgs[0].Content -replace '"', "'")
    if ($titleGuess.Length -gt 90) { $titleGuess = $titleGuess.Substring(0, 90) }
    $proj = Split-Path $Folder -Leaf
    Write-Host "  -> pwsh -File Work.ps1 start `"$titleGuess`" -Category $Category -Project $proj -At '$($b.Start.ToString('yyyy-MM-dd HH:mm:ss'))'" -ForegroundColor DarkGray
}
Write-Host ""

if ($Create) {
    $target = if ($Block -gt 0) { $Block } else { $blocks.Count }  # default: last (most recent) block
    if ($target -lt 1 -or $target -gt $blocks.Count) { throw "Block $target out of range (1..$($blocks.Count))." }
    $b = $blocks[$target - 1]
    $proj = Split-Path $Folder -Leaf
    $itemTitle = if ($Title) { $Title } else {
        $t = ($b.Msgs[0].Content -replace '"', "'"); if ($t.Length -gt 90) { $t = $t.Substring(0, 90) }; $t
    }
    $at = $b.Start.ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "Creating work item for block $target (start $at)..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'Work.ps1') start $itemTitle -Category $Category -Project $proj -At $at
}

