<#
.SYNOPSIS
  Conversational, time-tracked work-logging framework (daily standup + weekly summary).

.DESCRIPTION
  A persistent activity log designed to be driven through conversation: you say when
  you start a piece of work and what it is; you say when you switch; you say when you
  finish and what you accomplished. The framework records timestamped sessions and
  rolls them up into a daily standup and a weekly summary (HTML to view + Markdown
  to paste into Teams/email/ADO).

  Session model (PARALLEL sessions supported):
    - Multiple sessions can be open at once. Starting or switching NEVER closes another.
    - 'current' is just the session that notes/stop default to; switching moves it.
    - A session stays open (end = null) until you explicitly Stop-Work it.

  Each session captures:
    id, kind ('ado' | 'adhoc'), adoId, category, tags, title,
    start, end, durationMin, status, accomplishment, blocker, notes[] (timestamped)

  State : <script>\data\<profile>\work-log.json  (profile = work | personal | ...)
  Output: standup.* / weekly-summary.* / work-dashboard.html (in the same per-profile folder)

  Public functions:
    Start-Work, Switch-Work, Stop-Work, Add-WorkNote,
    Get-OpenSessions, Get-WorkLog, Show-WorkStatus,
    New-Standup, New-WeeklySummary
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web

# ---- Configuration ---------------------------------------------------------
# Portable + profile-aware. Paths resolve relative to this script, so the tool
# runs from wherever the repo is cloned. Each profile (e.g. 'work', 'personal')
# keeps its own log + reports under <script>\data\<profile>\.
$script:Fmt        = 'yyyy-MM-dd HH:mm:ss'
$script:SuppressDashboard = $false
$script:ScriptDir  = $PSScriptRoot
$script:DataRoot   = if ($env:WORKLOG_HOME) { $env:WORKLOG_HOME } else { $PSScriptRoot }
$script:ConfigPath = Join-Path $script:ScriptDir 'worklog.config.json'

function Get-WorkConfig {
    if (Test-Path $script:ConfigPath) {
        try { return Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return $null
}

function Resolve-WorkProfile {
    param([string]$Profile)
    if ($Profile)              { return $Profile }
    if ($env:WORKLOG_PROFILE)  { return $env:WORKLOG_PROFILE }
    $pf = Join-Path $script:ScriptDir '.profile'
    if (Test-Path $pf) { $v = (Get-Content $pf -Raw).Trim(); if ($v) { return $v } }
    $cfg = Get-WorkConfig
    if ($cfg -and $cfg.defaultProfile) { return [string]$cfg.defaultProfile }
    return 'work'
}

function Set-WorkProfile {
    [CmdletBinding()]
    param([string]$Profile)
    $script:Profile = Resolve-WorkProfile -Profile $Profile
    $dataDir = Join-Path (Join-Path $script:DataRoot 'data') $script:Profile
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    $script:StatePath = Join-Path $dataDir 'work-log.json'
    $script:OutDir    = $dataDir
    $script:Org       = ''
    $cfg = Get-WorkConfig
    if ($cfg -and $cfg.profiles -and ($cfg.profiles.PSObject.Properties.Name -contains $script:Profile)) {
        $p = $cfg.profiles.$($script:Profile)
        if ($p.PSObject.Properties.Name -contains 'org') { $script:Org = [string]$p.org }
    }
    [pscustomobject]@{ Profile = $script:Profile; State = $script:StatePath; OutDir = $script:OutDir; Org = $script:Org }
}

function Get-WorkProfile {
    [pscustomobject]@{ Profile = $script:Profile; State = $script:StatePath; OutDir = $script:OutDir; Org = $script:Org }
}

function Set-WorkDefaultProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Profile)
    Set-Content -Path (Join-Path $script:ScriptDir '.profile') -Value $Profile.Trim() -NoNewline -Encoding UTF8
    Set-WorkProfile -Profile $Profile
}

Set-WorkProfile | Out-Null

# ---- Internal helpers ------------------------------------------------------
function HtmlEnc([string]$s) { [System.Web.HttpUtility]::HtmlEncode($s) }
function ConvertTo-TitleCaseCategory([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    ($s.Trim() -split '\s+' | ForEach-Object {
        if ($_.Length -gt 0) { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) } else { $_ }
    }) -join ' '
}
function ConvertTo-FirstCapital([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    $i = 0
    while ($i -lt $s.Length -and [char]::IsWhiteSpace($s[$i])) { $i++ }
    if ($i -ge $s.Length) { return $s }
    $s.Substring(0, $i) + $s.Substring($i, 1).ToUpperInvariant() + $s.Substring($i + 1)
}
function NowStr { (Get-Date).ToString($script:Fmt) }
function ParseTs([string]$s) { [datetime]::ParseExact($s, $script:Fmt, [Globalization.CultureInfo]::InvariantCulture) }
function FmtMin([int]$m) {
    if ($m -le 0) { return '0m' }
    if ($m -lt 60) { return "${m}m" }
    return ('{0}h {1}m' -f [math]::Floor($m / 60), ($m % 60))
}

function ConvertTo-HashtableDeep {
    param($obj)
    if ($null -eq $obj) { return $null }
    if ($obj -is [string]) { return $obj }
    if ($obj.GetType().IsValueType) { return $obj }
    if ($obj -is [System.Collections.IDictionary]) {
        $h = @{}; foreach ($k in $obj.Keys) { $h["$k"] = ConvertTo-HashtableDeep $obj[$k] }; return $h
    }
    if ($obj -is [System.Collections.IEnumerable]) {
        $a = New-Object System.Collections.ArrayList
        foreach ($e in $obj) { [void]$a.Add((ConvertTo-HashtableDeep $e)) }
        return , $a.ToArray()
    }
    if ($obj.PSObject) {
        $h = @{}; foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }; return $h
    }
    return $obj
}

function Get-LogState {
    if (Test-Path -LiteralPath $script:StatePath) {
        $raw = Get-Content -Raw -LiteralPath $script:StatePath
        if ($raw -and $raw.Trim()) {
            $h = ConvertTo-HashtableDeep ($raw | ConvertFrom-Json)
            if (-not $h.ContainsKey('sessions') -or $null -eq $h['sessions']) { $h['sessions'] = @() }
            $h['sessions'] = @($h['sessions'])
            if (-not $h.ContainsKey('nextId'))  { $h['nextId']  = ($h['sessions'].Count + 1) }
            if (-not $h.ContainsKey('current')) { $h['current'] = $null }
            return $h
        }
    }
    return @{ current = $null; nextId = 1; sessions = @() }
}

function Save-LogState($state) {
    $state['updated'] = NowStr
    $state['sessions'] = @($state['sessions'])
    $json = $state | ConvertTo-Json -Depth 12
    if (-not (Test-Path -LiteralPath $script:OutDir)) { New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    # Atomic write: stage to a temp file, then swap into place keeping a .bak rollback copy.
    $tmp = "$script:StatePath.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, $utf8)
    if (Test-Path -LiteralPath $script:StatePath) {
        $bak = "$script:StatePath.bak"
        try   { [System.IO.File]::Replace($tmp, $script:StatePath, $bak) }
        catch { [System.IO.File]::Copy($script:StatePath, $bak, $true); [System.IO.File]::Move($tmp, $script:StatePath, $true) }
    } else {
        [System.IO.File]::Move($tmp, $script:StatePath)
    }
    if (-not $script:SuppressDashboard) {
        try { New-WorkDashboard -NoOpen | Out-Null }
        catch { Write-Warning "Dashboard rebuild failed: $($_.Exception.Message)" }
    }
}

function Find-Session($state, [int]$Id) {
    $state['sessions'] | Where-Object { [int]$_['id'] -eq $Id } | Select-Object -First 1
}

# ---- Public: Start ---------------------------------------------------------
function Start-Work {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$AdoId = '',
        [string]$Category = '',
        [string]$Project = '',
        [string[]]$Tags = @(),
        [datetime]$At = (Get-Date),
        [switch]$AfterLast
    )
    $st = Get-LogState
    # -AfterLast: back-date the start to the most recent session's end (no overlaps),
    # so "log work since my last item" needs no separate lookups.
    if ($AfterLast -and -not $PSBoundParameters.ContainsKey('At')) {
        $ends = @($st['sessions'] | Where-Object { $_['end'] } | ForEach-Object { ParseTs $_['end'] })
        if ($ends.Count) {
            $last = ($ends | Sort-Object)[-1]
            if ($last -lt (Get-Date)) { $At = $last }
        }
    }
    $id = [int]$st['nextId']
    $kind = if ($AdoId) { 'ado' } else { 'adhoc' }
    $Category = ConvertTo-TitleCaseCategory $Category
    $Title = ConvertTo-FirstCapital $Title
    $s = @{
        id = $id; kind = $kind; adoId = $AdoId; category = $Category; project = $Project; tags = @($Tags)
        title = $Title; start = $At.ToString($script:Fmt); end = $null; durationMin = 0
        status = 'in-progress'; accomplishment = ''; blocker = ''; notes = @()
    }
    $st['sessions'] = @($st['sessions']) + $s
    $st['nextId']   = $id + 1
    $st['current']  = $id    # switch focus to the new session; previous sessions stay OPEN
    Save-LogState $st
    $tag = if ($AdoId) { "[$AdoId] " } else { '' }
    Write-Host ("> Started #{0}: {1}{2}  ({3})" -f $id, $tag, $Title, $At.ToString('HH:mm'))
    return $s
}

# ---- Public: Switch (no close) --------------------------------------------
function Switch-Work {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Id)
    $st = Get-LogState
    $s = Find-Session $st $Id
    if (-not $s) { throw "No session #$Id." }
    if ($s['end']) { throw "Session #$Id is already stopped." }
    $st['current'] = $Id
    Save-LogState $st
    Write-Host ("~ Switched to #{0}: {1} (previous sessions left open)" -f $Id, $s['title'])
}

# ---- Public: Stop ----------------------------------------------------------
function Stop-Work {
    [CmdletBinding()]
    param(
        [int]$Id = 0,
        [string]$Accomplishment = '',
        [string]$Blocker = '',
        [ValidateSet('done', 'paused', 'in-progress')][string]$Status = 'done',
        [datetime]$At = (Get-Date)
    )
    $st = Get-LogState
    if (-not $Id) { $Id = if ($st['current']) { [int]$st['current'] } else { 0 } }
    if (-not $Id) { Write-Warning 'No current session. Specify -Id.'; return }
    $s = Find-Session $st $Id
    if (-not $s) { throw "No session #$Id." }
    if ($s['end']) { Write-Warning "Session #$Id already stopped."; return }
    $s['end'] = $At.ToString($script:Fmt)
    $s['durationMin'] = [math]::Round((($At) - (ParseTs $s['start'])).TotalMinutes)
    if ($Accomplishment) { $s['accomplishment'] = ConvertTo-FirstCapital $Accomplishment }
    if ($Blocker)        { $s['blocker'] = ConvertTo-FirstCapital $Blocker }
    $s['status'] = $Status
    if ([int]$st['current'] -eq $Id) { $st['current'] = $null }
    Save-LogState $st
    Write-Host ("# Stopped #{0}: {1}  ({2})" -f $Id, $s['title'], (FmtMin $s['durationMin']))
    return $s
}

# ---- Helper: build a GitHub-issue note line --------------------------------
# Fetches the issue once and returns the standard markdown note:
#   [#N Title](url) - milestone: X | state: Y | commit: abc1234
function New-GhIssueNote {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Issue, [string]$RepoPath = '', [string]$Commit = '')
    $loc = if ($RepoPath) { $RepoPath } else { (Get-Location).Path }
    Push-Location $loc
    try {
        $j = $null
        try { $j = (gh issue view $Issue --json number,title,url,milestone,state 2>$null | ConvertFrom-Json) } catch { $j = $null }
        if (-not $j) { Write-Warning "Could not fetch gh issue #$Issue from $loc."; return $null }
        $ms = if ($j.milestone) { $j.milestone.title } else { 'none' }
        if (-not $Commit) { try { $Commit = (git rev-parse --short HEAD 2>$null) } catch { $Commit = '' } }
        $note = ('[#{0} {1}]({2}) - milestone: {3} | state: {4}' -f $j.number, $j.title, $j.url, $ms, $j.state)
        if ($Commit) { $note += " | commit: $Commit" }
        return $note
    }
    finally { Pop-Location }
}

# ---- Public: Close (one-shot: gh note + stop + single dashboard rebuild) ----
# Collapses the whole "close a work item" workflow into ONE process so the
# agent makes a single call instead of separate note/stop/dashboard round-trips.
function Complete-Work {
    [CmdletBinding()]
    param(
        [int]$Id = 0,
        [string]$Accomplishment = '',
        [string]$Blocker = '',
        [ValidateSet('done', 'paused', 'in-progress')][string]$Status = 'done',
        [datetime]$At = (Get-Date),
        [int]$Issue = 0,
        [string]$RepoPath = '',
        [string]$Commit = '',
        [switch]$CloseIssue
    )
    $s = $null
    $script:SuppressDashboard = $true
    try {
        $st = Get-LogState
        if (-not $Id) { $Id = if ($st['current']) { [int]$st['current'] } else { 0 } }
        if (-not $Id) { Write-Warning 'No current session. Specify -Id.'; return }

        if ($Issue -gt 0) {
            $note = New-GhIssueNote -Issue $Issue -RepoPath $RepoPath -Commit $Commit
            if ($note) { Add-WorkNote -Text $note -Id $Id }
        }

        $sp = @{ Id = $Id; Accomplishment = $Accomplishment; Blocker = $Blocker; Status = $Status; At = $At }
        $s = Stop-Work @sp

        if ($Issue -gt 0 -and $CloseIssue) {
            $loc = if ($RepoPath) { $RepoPath } else { (Get-Location).Path }
            Push-Location $loc
            try {
                $cmt = if ($Accomplishment) { "Completed: $Accomplishment" } else { 'Completed.' }
                gh issue close $Issue --comment $cmt 2>$null | Out-Null
                Write-Host "# Closed gh issue #$Issue"
            }
            catch { Write-Warning "gh issue close failed: $($_.Exception.Message)" }
            finally { Pop-Location }
        }
    }
    finally { $script:SuppressDashboard = $false }

    # One dashboard rebuild for the whole close (instead of one per mutation).
    try { New-WorkDashboard -NoOpen | Out-Null }
    catch { Write-Warning "Dashboard rebuild failed: $($_.Exception.Message)" }
    return $s
}

# ---- Public: Day commentary -----------------------------------------------
function Set-DayCommentary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text, [datetime]$Date = (Get-Date))
    $st = Get-LogState
    $key = $Date.ToString('yyyy-MM-dd')
    $map = if ($st.ContainsKey('commentary') -and $st['commentary']) { $st['commentary'] } else { @{} }
    if ($Text.Trim()) { $map[$key] = (ConvertTo-FirstCapital $Text.Trim()) } else { $map.Remove($key) | Out-Null }
    $st['commentary'] = $map
    Save-LogState $st
    Write-Host ("* Commentary set for {0}" -f $key)
}

# ---- Public: Note ----------------------------------------------------------
function Add-WorkNote {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text, [int]$Id = 0)
    $st = Get-LogState
    if (-not $Id) { $Id = if ($st['current']) { [int]$st['current'] } else { 0 } }
    if (-not $Id) { Write-Warning 'No current session. Specify -Id.'; return }
    $s = Find-Session $st $Id
    if (-not $s) { throw "No session #$Id." }
    $notes = [System.Collections.ArrayList]@($s['notes'])
    [void]$notes.Add(@{ ts = NowStr; text = (ConvertTo-FirstCapital $Text) })
    $s['notes'] = $notes.ToArray()
    Save-LogState $st
    Write-Host ("* Note added to #{0} ({1} total)" -f $Id, $notes.Count)
}

# ---- Public: Edit ----------------------------------------------------------
function Edit-Work {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Id,
        [string]$Title,
        [string]$Category,
        [string]$Project,
        [string]$AdoId,
        [string[]]$Tags,
        [string]$Accomplishment,
        [string]$Blocker,
        [ValidateSet('done', 'paused', 'in-progress')][string]$Status,
        [datetime]$Start,
        [datetime]$End,
        [switch]$Reopen
    )
    $st = Get-LogState
    $s = Find-Session $st $Id
    if (-not $s) { throw "No session #$Id." }
    $changed = @()
    if ($PSBoundParameters.ContainsKey('Title'))         { $s['title'] = ConvertTo-FirstCapital $Title; $changed += 'title' }
    if ($PSBoundParameters.ContainsKey('Category'))      { $s['category'] = ConvertTo-TitleCaseCategory $Category; $changed += 'category' }
    if ($PSBoundParameters.ContainsKey('Project'))       { $s['project'] = $Project; $changed += 'project' }
    if ($PSBoundParameters.ContainsKey('AdoId'))         { $s['adoId'] = $AdoId; $s['kind'] = if ($AdoId) { 'ado' } else { 'adhoc' }; $changed += 'adoId' }
    if ($PSBoundParameters.ContainsKey('Tags'))          { $s['tags'] = @($Tags); $changed += 'tags' }
    if ($PSBoundParameters.ContainsKey('Accomplishment')){ $s['accomplishment'] = ConvertTo-FirstCapital $Accomplishment; $changed += 'accomplishment' }
    if ($PSBoundParameters.ContainsKey('Blocker'))       { $s['blocker'] = ConvertTo-FirstCapital $Blocker; $changed += 'blocker' }
    if ($PSBoundParameters.ContainsKey('Status'))        { $s['status'] = $Status; $changed += 'status' }
    if ($PSBoundParameters.ContainsKey('Start'))         { $s['start'] = $Start.ToString($script:Fmt); $changed += 'start' }
    if ($PSBoundParameters.ContainsKey('End'))           { $s['end'] = $End.ToString($script:Fmt); $changed += 'end' }
    if ($Reopen) {
        $s['end'] = $null; $s['durationMin'] = 0
        if (-not $PSBoundParameters.ContainsKey('Status')) { $s['status'] = 'in-progress' }
        $changed += 'reopened'
    }
    if (-not $changed) { Write-Warning "Nothing to change for #$Id. Pass a field, e.g. -Title, -Category, -Status."; return }
    if ($s['end']) { $s['durationMin'] = [math]::Round(((ParseTs $s['end']) - (ParseTs $s['start'])).TotalMinutes) }
    Save-LogState $st
    Write-Host ("~ Edited #{0}: {1}  (updated: {2})" -f $Id, $s['title'], ($changed -join ', '))
    return (ConvertTo-SessionView $s)
}

# ---- Public: Queries -------------------------------------------------------
function ConvertTo-SessionView($s) {
    [pscustomobject]@{
        Id = [int]$s['id']; Title = $s['title']; Kind = $s['kind']; AdoId = $s['adoId']
        Category = $s['category']; Project = $s['project']; Tags = (@($s['tags']) -join ', ')
        Start = (ParseTs $s['start']); End = $(if ($s['end']) { ParseTs $s['end'] } else { $null })
        Min = [int]$s['durationMin']; Status = $s['status']
        Accomplishment = $s['accomplishment']; Blocker = $s['blocker']; Notes = @($s['notes'])
    }
}

function Get-OpenSessions {
    $st = Get-LogState
    $st['sessions'] | Where-Object { -not $_['end'] } | ForEach-Object { ConvertTo-SessionView $_ } | Sort-Object Start
}

function Get-WorkLog {
    [CmdletBinding()]
    param([datetime]$Since, [datetime]$Until)
    $st = Get-LogState
    $st['sessions'] | ForEach-Object { ConvertTo-SessionView $_ } | Where-Object {
        (-not $Since -or $_.Start -ge $Since) -and (-not $Until -or $_.Start -le $Until)
    } | Sort-Object Start
}

function Find-WorkLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Query,
        [datetime]$Since,
        [datetime]$Until
    )
    $sp = @{}
    if ($PSBoundParameters.ContainsKey('Since')) { $sp.Since = $Since }
    if ($PSBoundParameters.ContainsKey('Until')) { $sp.Until = $Until }
    $sessions = Get-WorkLog @sp
    $needle = $Query.Trim()
    if (-not $needle) { return @() }
    $sessions | Where-Object {
        $s = $_
        $hay = @(
            $s.Title, $s.Accomplishment, $s.Blocker, $s.Project,
            $s.Category, $s.Tags, [string]$s.AdoId
        )
        $hay += @($s.Notes | ForEach-Object { $_.text })
        ($hay -join "`n") -match [regex]::Escape($needle)
    }
}

function Show-WorkSearch {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Query, [int]$Days = 0)
    $p = @{ Query = $Query }
    if ($Days -gt 0) { $p.Since = (Get-Date).Date.AddDays(-$Days) }
    $hits = @(Find-WorkLog @p | Sort-Object Start)
    Write-Host ''
    Write-Host ("{0} match(es) for '{1}'{2}" -f $hits.Count, $Query, $(if ($Days -gt 0) { " in last $Days day(s)" } else { '' })) -ForegroundColor Cyan
    foreach ($s in $hits) {
        $tag = if ($s.AdoId) { "[$($s.AdoId)] " } else { '' }
        Write-Host ("  #{0}  {1}  {2}{3}  ({4})" -f $s.Id, $s.Start.ToString('yyyy-MM-dd HH:mm'), $tag, $s.Title, (FmtMin $s.Min))
        $why = @()
        if ($s.Accomplishment) { $why += "  acc: $($s.Accomplishment)" }
        if ($s.Project)        { $why += "  project: $($s.Project)" }
        $noteHit = @($s.Notes | Where-Object { $_.text -match [regex]::Escape($Query.Trim()) })
        foreach ($n in $noteHit) { $why += "  note: $($n.text)" }
        foreach ($w in $why) { Write-Host $w -ForegroundColor DarkGray }
    }
    if (-not $hits.Count) { Write-Host '  (no matches)' }
}

function Show-WorkStatus {
    $st = Get-LogState
    $open = @($st['sessions'] | Where-Object { -not $_['end'] } | ForEach-Object { ConvertTo-SessionView $_ } | Sort-Object Start)
    $cur = $st['current']
    $todayMeasure = @(Get-WorkLog -Since (Get-Date).Date) | Measure-Object -Property Min -Sum
    $todayMin = 0
    if ($todayMeasure -and ($todayMeasure | Get-Member -Name Sum)) { $todayMin = $todayMeasure.Sum }
    Write-Host ''
    Write-Host ("Open sessions: {0}   Logged today: {1}" -f $open.Count, (FmtMin ([int]$todayMin))) -ForegroundColor Cyan
    foreach ($s in $open) {
        $mark = if ($cur -and [int]$cur -eq $s.Id) { '>' } else { ' ' }
        $elapsed = FmtMin ([math]::Round(((Get-Date) - $s.Start).TotalMinutes))
        $tag = if ($s.AdoId) { "[$($s.AdoId)] " } else { '' }
        Write-Host ("  {0} #{1}  {2}{3}  (running {4})" -f $mark, $s.Id, $tag, $s.Title, $elapsed)
    }
    if (-not $open.Count) { Write-Host '  (nothing open)' }
}

# ---- Report building helpers ----------------------------------------------
function Get-ItemLabel($s) { if ($s.AdoId) { "[$($s.AdoId)] $($s.Title)" } else { $s.Title } }
function Get-ItemUrl($s)   { if ($s.AdoId -and $script:Org) { "$script:Org/_workitems/edit/$($s.AdoId)" } else { $null } }

function Get-LineText($s) {
    $t = if ($s.Accomplishment) { $s.Accomplishment } else { $s.Title }
    if ($s.Accomplishment -and $s.AdoId) { "$(Get-ItemLabel $s) - $($s.Accomplishment)" }
    elseif ($s.Accomplishment) { "$($s.Title) - $($s.Accomplishment)" }
    else { Get-ItemLabel $s }
}

$script:BaseCss = @"
@import url('https://fonts.googleapis.com/css2?family=Roboto+Flex:opsz,wght@8..144,100..1000&family=Roboto+Mono:wght@400;500&display=swap');
:root{--bg:#0a0e1a;--card:#0f1524;--card2:#151c2d;--border:#1e2739;--text:#e9eef6;--muted:#7d8a9e;--accent:#4d8dff;--green:#33d685;--red:#ff5d5d;--amber:#ffb648;--mono:'Roboto Mono',Consolas,monospace;}
*{box-sizing:border-box;}
html{scroll-behavior:smooth;}
body{font-family:'Roboto Flex',system-ui,sans-serif;font-optical-sizing:auto;margin:0;background:var(--bg);color:var(--text);line-height:1.55;}
.page{max-width:none;margin:0;padding:26px 20% 80px;}
a{color:var(--accent);text-decoration:none;}a:hover{text-decoration:underline;}
.rpt-hero{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;padding:6px 2px 16px;border-bottom:1px solid var(--border);}
.rpt-hero h1{font-size:26px;font-weight:800;letter-spacing:-.3px;margin:0;}
.meta{color:var(--muted);font-size:13px;margin-top:6px;}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.7px;color:var(--muted);margin:26px 0 10px;font-weight:600;}
.card{background:var(--card);border:1px solid var(--border);border-radius:0;padding:18px;}
.muted{color:var(--muted);}.nowrap{white-space:nowrap;}.center{text-align:center;}
.run{color:var(--green);font-weight:600;}
.blk{color:var(--red);font-size:12px;margin-top:4px;}
.cat{display:inline-block;background:#4d8dff22;color:#9cc2ff;border-radius:0;padding:2px 10px;font-size:11px;font-weight:600;white-space:nowrap;}
.proj{display:inline-block;background:#a06bff22;color:#c7adff;border-radius:0;padding:2px 10px;font-size:11px;font-weight:600;}
.sbadge{display:inline-block;border-radius:0;padding:1px 8px;font-size:10px;font-weight:700;letter-spacing:.4px;text-transform:uppercase;margin-left:8px;vertical-align:middle;white-space:nowrap;border:1px solid transparent;}
.sbadge.open{background:#33d68522;color:var(--green);border-color:#33d68555;}
.sbadge.paused{background:#ffb64822;color:var(--amber);border-color:#ffb64855;}
.sbadge.inprogress{background:#4d8dff22;color:#9cc2ff;border-color:#4d8dff55;}
tr.unstopped td{background:#ffb6480d;}
tr.unstopped td:first-child{box-shadow:inset 3px 0 0 var(--amber);}
.adoid{color:var(--muted);font-family:var(--mono);font-size:11.5px;font-weight:500;}
.idnum{font-family:var(--mono);font-size:12px;font-weight:600;color:var(--accent);}
.chip{display:inline-block;background:#4d8dff1a;color:#9cc2ff;border:1px solid #4d8dff33;border-radius:0;padding:3px 11px;font-size:12px;margin:0 6px 6px 0;}
.ncount{display:inline-block;min-width:20px;text-align:center;background:#4d8dff33;color:#9cc2ff;border-radius:0;font-size:11px;padding:1px 7px;font-weight:600;cursor:default;}
table.log{width:100%;border-collapse:separate;border-spacing:0;background:var(--card);border:1px solid var(--border);border-radius:0;overflow:hidden;}
table.log th{background:var(--card2);color:var(--muted);text-transform:uppercase;font-size:10.5px;letter-spacing:.5px;font-weight:600;text-align:left;padding:10px 14px;}
table.log td{padding:11px 14px;border-top:1px solid var(--border);font-size:13.5px;vertical-align:top;}
table.log tbody tr:hover td{background:#161f30;}
table.log.day{table-layout:fixed;}
table.log.day th,table.log.day td{overflow-wrap:anywhere;word-break:break-word;}
table.log.day td.nowrap{white-space:normal;}
.callout{display:flex;gap:9px;background:#4d8dff12;border-left:3px solid var(--accent);border-radius:0;padding:11px 15px;font-size:13.5px;margin:8px 0;}
.callout.warn{background:#ff5d5d1a;border-left-color:var(--red);}
.top{display:grid;grid-template-columns:300px 1fr;gap:16px;margin:18px 0 8px;}
.sum-row{display:flex;gap:28px;flex-wrap:wrap;margin-bottom:14px;}
.stat .big{font-size:26px;font-weight:700;font-variant-numeric:tabular-nums;}
.stat .lbl{font-size:10.5px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted);}
.chips{margin-bottom:8px;}.scope{font-size:12.5px;color:var(--muted);}
.commentary{margin:10px 0 2px;padding:7px 10px;border-left:3px solid var(--accent,#3b82f6);background:rgba(59,130,246,.07);border-radius:4px;font-size:12.5px;font-style:italic;line-height:1.45;color:var(--muted);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;}
.commentary b{font-style:normal;color:var(--fg,#e6e6e6);font-weight:600;}
.daygrp{margin:0 0 18px;}
.dayhdr{display:flex;justify-content:space-between;align-items:baseline;margin:0 0 8px;padding:0 2px;}
.dayhdr span:first-child{font-size:15px;font-weight:700;color:var(--accent);}
.daytot{font-size:12px;color:var(--muted);}
.empty{color:var(--muted);padding:34px;text-align:center;background:var(--card);border:1px solid var(--border);border-radius:0;}
.cal-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;}
.cal-title{font-size:14px;font-weight:700;}
.cbtn{background:var(--card2);border:1px solid var(--border);color:var(--text);border-radius:0;width:30px;height:30px;cursor:pointer;font-size:16px;line-height:1;}
.cbtn:hover{background:#161f30;}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:5px;}
.cal-grid .dow{font-size:9.5px;color:var(--muted);text-align:center;text-transform:uppercase;padding-bottom:3px;}
.cal-day{aspect-ratio:1;display:flex;flex-direction:column;align-items:center;justify-content:center;border-radius:0;font-size:13px;color:#46505c;}
.cal-day.in{color:var(--text);}
.cal-day.has{background:#4d8dff22;cursor:pointer;font-weight:600;}
.cal-day.has:hover{background:#4d8dff55;}
.cal-day.today{outline:1.5px solid var(--accent);outline-offset:-1.5px;}
.cal-day.sel{background:var(--accent);color:#06101f;}
.cal-day .dot{width:5px;height:5px;border-radius:50%;background:var(--accent);margin-top:3px;}
.cal-day.sel .dot{background:#06101f;}
.cal-foot{margin-top:12px;text-align:center;}
.pill{background:var(--card2);border:1px solid var(--border);color:var(--text);border-radius:0;padding:5px 14px;font-size:12px;cursor:pointer;}
.pill:hover{background:#161f30;}
.nbtn{cursor:pointer;border:none;font-family:var(--mono);}
.ncount.zero{background:transparent;color:var(--muted);}
.modal{display:none;position:fixed;inset:0;background:rgba(4,7,14,.72);z-index:50;align-items:flex-start;justify-content:center;padding:8vh 16px;}
.modal.show{display:flex;}
.modal-box{background:var(--card);border:1px solid var(--border);width:min(680px,100%);max-height:80vh;display:flex;flex-direction:column;}
.modal-head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px 18px;border-bottom:1px solid var(--border);font-size:15px;font-weight:700;}
.modal-body{padding:16px 18px;overflow:auto;}
@media(max-width:760px){.top{grid-template-columns:1fr;}.page{padding:18px 6%;}}
"@

function Get-ItemCell($s) {
    $t = HtmlEnc $s.Title
    $u = Get-ItemUrl $s
    $title = if ($u) { "<a href='$u' target='_blank'>$t</a>" } else { $t }
    if ($s.AdoId) { "<span class='adoid'>#$(HtmlEnc $s.AdoId)</span> $title" } else { $title }
}

function New-ReportHtml([string]$Title, [string]$Meta, [string]$Body) {
    @"
<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'><title>$Title</title>
<style>$script:BaseCss</style></head><body>
<div class='page'>
<header class='rpt-hero'><div><h1>$Title</h1><div class='meta'>$Meta</div></div></header>
$Body
</div></body></html>
"@
}

function Write-Report([string]$BaseName, [string]$Html, [string]$Md, [switch]$NoOpen) {
    $htmlPath = Join-Path $script:OutDir "$BaseName.html"
    $mdPath   = Join-Path $script:OutDir "$BaseName.md"
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($htmlPath, $Html, $enc)
    [System.IO.File]::WriteAllText($mdPath, $Md, $enc)
    Write-Host "Wrote $htmlPath"
    Write-Host "Wrote $mdPath"
    if (-not $NoOpen) { Start-Process $htmlPath }
    [pscustomobject]@{ Html = $htmlPath; Md = $mdPath }
}

# ---- Public: Daily standup -------------------------------------------------
function New-Standup {
    [CmdletBinding()]
    param([datetime]$Date = (Get-Date), [switch]$NoOpen)

    $today = $Date.Date
    $yest = $today.AddDays(-1)
    while ($yest.DayOfWeek -in 'Saturday', 'Sunday') { $yest = $yest.AddDays(-1) }

    $all = @(Get-WorkLog)
    $yItems = @($all | Where-Object { $_.Start.Date -eq $yest })
    $tItems = @($all | Where-Object { $_.Start.Date -eq $today })
    $blockers = @($all | Where-Object { $_.Blocker -and ($_.Start.Date -eq $yest -or $_.Start.Date -eq $today) })

    # ---- Markdown ----
    $md = New-Object System.Collections.ArrayList
    [void]$md.Add("# Daily Standup - $($today.ToString('yyyy-MM-dd ddd'))")
    [void]$md.Add('')
    [void]$md.Add("## Yesterday ($($yest.ToString('yyyy-MM-dd ddd')))")
    if ($yItems.Count) { foreach ($s in $yItems) { [void]$md.Add("- $(Get-LineText $s) ($(FmtMin $s.Min))") } }
    else { [void]$md.Add('- _No logged work._') }
    [void]$md.Add('')
    [void]$md.Add("## Today ($($today.ToString('yyyy-MM-dd ddd')))")
    if ($tItems.Count) {
        foreach ($s in $tItems) {
            $state = if (-not $s.End) { ' (in progress)' } elseif ($s.Status -eq 'done') { '' } else { " ($($s.Status))" }
            [void]$md.Add("- $(Get-ItemLabel $s)$state")
        }
    } else { [void]$md.Add('- _Nothing logged yet._') }
    [void]$md.Add('')
    [void]$md.Add('## Blockers')
    if ($blockers.Count) { foreach ($s in $blockers) { [void]$md.Add("- $(Get-ItemLabel $s): $($s.Blocker)") } }
    else { [void]$md.Add('- None') }
    $mdText = ($md -join "`n")

    # ---- HTML (modern tables) ----
    $yRows = if ($yItems.Count) {
        ($yItems | ForEach-Object {
            $acc = if ($_.Accomplishment) { HtmlEnc $_.Accomplishment } else { "<span class='muted'>&mdash;</span>" }
            "<tr><td>$(Get-ItemCell $_)</td><td>$acc</td><td class='nowrap'>$(FmtMin $_.Min)</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='3' class='muted'>No logged work.</td></tr>" }
    $tRows = if ($tItems.Count) {
        ($tItems | ForEach-Object {
            $state = if (-not $_.End) { "<span class='run'>in progress</span>" } else { HtmlEnc $_.Status }
            "<tr><td>$(Get-ItemCell $_)</td><td>$state</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='2' class='muted'>Nothing logged yet.</td></tr>" }
    $bBlock = if ($blockers.Count) {
        ($blockers | ForEach-Object { "<div class='callout warn'>&#9888;<span><b>$(HtmlEnc (Get-ItemLabel $_)):</b> $(HtmlEnc $_.Blocker)</span></div>" }) -join "`n"
    } else { "<div class='callout'>None</div>" }

    $body = @"
<h2>Yesterday &mdash; $($yest.ToString('dddd, MMM d'))</h2>
<table class='log'><thead><tr><th>Item</th><th>Accomplishment</th><th class='nowrap'>Time</th></tr></thead><tbody>
$yRows
</tbody></table>
<h2>Today &mdash; $($today.ToString('dddd, MMM d'))</h2>
<table class='log'><thead><tr><th>Item</th><th>Status</th></tr></thead><tbody>
$tRows
</tbody></table>
<h2>Blockers</h2>
$bBlock
"@
    $html = New-ReportHtml "Daily Standup" "Generated $((Get-Date).ToString('yyyy-MM-dd HH:mm')) &bull; StarlightAgileBI" $body

    Write-Report -BaseName 'standup' -Html $html -Md $mdText -NoOpen:$NoOpen | Out-Null
    Write-Host ''
    Write-Host $mdText
}

# ---- Public: Weekly summary ------------------------------------------------
function New-WeeklySummary {
    [CmdletBinding()]
    param([datetime]$Date = (Get-Date), [switch]$NoOpen)

    $ref = $Date.Date
    $delta = ([int]$ref.DayOfWeek + 6) % 7   # Monday = 0
    $mon = $ref.AddDays(-$delta)
    $sun = $mon.AddDays(6)

    $week = @(Get-WorkLog -Since $mon -Until $sun.AddDays(1).AddSeconds(-1))
    $totalMin = (@($week) | Measure-Object -Property Min -Sum).Sum; if (-not $totalMin) { $totalMin = 0 }

    # by category
    $catGroups = $week | Group-Object { if ($_.Category) { $_.Category } elseif ($_.AdoId) { 'ADO' } else { 'Other' } }

    # ---- Markdown ----
    $md = New-Object System.Collections.ArrayList
    [void]$md.Add("# Weekly Summary - Week of $($mon.ToString('yyyy-MM-dd')) to $($sun.ToString('yyyy-MM-dd'))")
    [void]$md.Add('')
    [void]$md.Add('## Accomplishments')
    $any = $false
    for ($d = $mon; $d -le $sun; $d = $d.AddDays(1)) {
        $day = @($week | Where-Object { $_.Start.Date -eq $d })
        if (-not $day.Count) { continue }
        $any = $true
        [void]$md.Add("### $($d.ToString('ddd MM-dd'))")
        foreach ($s in $day) { [void]$md.Add("- $(Get-LineText $s) ($(FmtMin $s.Min))") }
    }
    if (-not $any) { [void]$md.Add('- _No logged work this week._') }
    [void]$md.Add('')
    [void]$md.Add('## Time')
    [void]$md.Add("- Total: $(FmtMin ([int]$totalMin))")
    foreach ($g in ($catGroups | Sort-Object { -(($_.Group | Measure-Object Min -Sum).Sum) })) {
        $cm = ($g.Group | Measure-Object Min -Sum).Sum
        [void]$md.Add("- $($g.Name): $(FmtMin ([int]$cm))")
    }
    [void]$md.Add('')
    [void]$md.Add('## Blockers')
    $wblk = @($week | Where-Object Blocker)
    if ($wblk.Count) { foreach ($s in $wblk) { [void]$md.Add("- $(Get-ItemLabel $s): $($s.Blocker)") } } else { [void]$md.Add('- None') }
    $mdText = ($md -join "`n")

    # ---- HTML (modern tables) ----
    $dayHtml = ''
    for ($d = $mon; $d -le $sun; $d = $d.AddDays(1)) {
        $day = @($week | Where-Object { $_.Start.Date -eq $d })
        if (-not $day.Count) { continue }
        $dayMin = ($day | Measure-Object Min -Sum).Sum
        $rows = ($day | ForEach-Object {
            $time = "$($_.Start.ToString('HH:mm'))" + $(if ($_.End) { " &ndash; $($_.End.ToString('HH:mm'))" } else { " <span class='run'>&bull; open</span>" })
            $acc = if ($_.Accomplishment) { HtmlEnc $_.Accomplishment } else { "<span class='muted'>&mdash;</span>" }
            if ($_.Blocker) { $acc += "<div class='blk'>&#9888; $(HtmlEnc $_.Blocker)</div>" }
            $cat = if ($_.Category) { $_.Category } elseif ($_.AdoId) { 'ADO' } else { 'Other' }
            "<tr><td class='nowrap'>$time</td><td class='nowrap'>$(FmtMin $_.Min)</td><td><span class='cat'>$(HtmlEnc $cat)</span></td><td>$(Get-ItemCell $_)</td><td>$acc</td></tr>"
        }) -join "`n"
        $dayHtml += @"
<div class='daygrp'><div class='dayhdr'><span>$($d.ToString('dddd, MMM d'))</span><span class='daytot'>$(FmtMin ([int]$dayMin)) &bull; $($day.Count) session(s)</span></div>
<table class='log'><thead><tr><th>Time</th><th>Dur</th><th>Category</th><th>Item</th><th>Accomplishment</th></tr></thead><tbody>
$rows
</tbody></table></div>
"@
    }
    if (-not $dayHtml) { $dayHtml = "<div class='empty'>No logged work this week.</div>" }

    $catChips = ($catGroups | Sort-Object { -(($_.Group | Measure-Object Min -Sum).Sum) } | ForEach-Object {
        $cm = ($_.Group | Measure-Object Min -Sum).Sum
        "<span class='chip'>$(HtmlEnc $_.Name): $(FmtMin ([int]$cm))</span>"
    }) -join ' '
    $wblkBlock = if ($wblk.Count) {
        ($wblk | ForEach-Object { "<div class='callout warn'>&#9888;<span><b>$(HtmlEnc (Get-ItemLabel $_)):</b> $(HtmlEnc $_.Blocker)</span></div>" }) -join "`n"
    } else { "<div class='callout'>None</div>" }

    $body = @"
<div class='card'><div class='sum-row'>
<div class='stat'><div class='big'>$(FmtMin ([int]$totalMin))</div><div class='lbl'>Total time</div></div>
<div class='stat'><div class='big'>$($week.Count)</div><div class='lbl'>Sessions</div></div>
<div class='stat'><div class='big'>$(@($catGroups).Count)</div><div class='lbl'>Categories</div></div>
</div><div class='chips'>$catChips</div></div>
<h2>Accomplishments</h2>
$dayHtml
<h2>Blockers</h2>
$wblkBlock
"@
    $html = New-ReportHtml "Weekly Summary" "Week of $($mon.ToString('MMM d')) &ndash; $($sun.ToString('MMM d, yyyy')) &bull; Generated $((Get-Date).ToString('yyyy-MM-dd HH:mm'))" $body

    Write-Report -BaseName 'weekly-summary' -Html $html -Md $mdText -NoOpen:$NoOpen | Out-Null
    Write-Host ''
    Write-Host $mdText
}

# ---- Public: Interactive calendar dashboard --------------------------------
function New-WorkDashboard {
    [CmdletBinding()]
    param([switch]$NoOpen)

    $data = @(Get-WorkLog | ForEach-Object {
        [pscustomobject]@{
            id    = $_.Id
            date  = $_.Start.ToString('yyyy-MM-dd')
            start = $_.Start.ToString('HH:mm')
            end   = if ($_.End) { $_.End.ToString('HH:mm') } else { '' }
            min   = $_.Min
            category = if ($_.Category) { $_.Category } elseif ($_.AdoId) { 'ADO' } else { 'Other' }
            project = $_.Project
            adoId = $_.AdoId
            url   = if ($_.AdoId -and $script:Org) { "$script:Org/_workitems/edit/$($_.AdoId)" } else { '' }
            title = $_.Title
            accomplishment = $_.Accomplishment
            blocker = $_.Blocker
            status = $_.Status
            notes = @($_.Notes | ForEach-Object { @{ ts = $_.ts; text = $_.text } })
        }
    })
    $json = $data | ConvertTo-Json -Depth 6 -AsArray
    $json = $json.Replace('</', '<\/')
    $state = Get-LogState
    $commentaryMap = if ($state['commentary']) { $state['commentary'] } else { @{} }
    $commentaryJson = ([pscustomobject]$commentaryMap | ConvertTo-Json -Depth 3)
    if (-not $commentaryJson -or $commentaryJson -notmatch '[:{]') { $commentaryJson = '{}' }
    $commentaryJson = $commentaryJson.Replace('</', '<\/')
    $count = $data.Count
    $totalMin = (@($data) | Measure-Object min -Sum).Sum; if (-not $totalMin) { $totalMin = 0 }
    $meta = "Generated $((Get-Date).ToString('yyyy-MM-dd HH:mm')) &bull; $count session(s) &bull; $(FmtMin ([int]$totalMin)) total &bull; click a highlighted day to filter"

    $js = @'
var MONTHS=['January','February','March','April','May','June','July','August','September','October','November','December'];
var WEEKDAYS=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
var DOW=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
var calY, calM, sel=[];
function isSel(ds){ return sel.indexOf(ds)!==-1; }
function fmtMin(m){ if(m<=0) return '0m'; if(m<60) return m+'m'; return Math.floor(m/60)+'h '+(m%60)+'m'; }
function esc(s){ s=(s==null?'':String(s)); return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function fmtTs(s){
  if(!s) return '';
  var m=String(s).match(/^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
  if(!m) return esc(s);
  return m[2]+'/'+m[3]+'/'+m[1]+' '+m[4]+':'+m[5];
}
function urlLabel(u){
  var raw=String(u).replace(/&amp;/g,'&');
  var pm=raw.match(/[?&]path=([^&]+)/i);
  var p = pm ? decodeURIComponent(pm[1]) : raw.replace(/[?#].*$/,'');
  var seg=p.split('/').filter(function(x){return x.length;});
  if(seg.length) return seg[seg.length-1];
  return raw.replace(/^https?:\/\//,'').split('/')[0];
}
function mdInline(e){
  e=e.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, function(m,name,u){ return "<a href='"+u+"' target='_blank' rel='noopener'>"+name+"</a>"; });
  e=e.replace(/(^|[^'(>])(https?:\/\/[^\s<]+)/g, function(m,pre,u){ return pre+"<a href='"+u+"' target='_blank' rel='noopener'>"+urlLabel(u)+"</a>"; });
  e=e.replace(/`([^`]+)`/g, function(m,c){ return "<code>"+c+"</code>"; });
  e=e.replace(/\*\*([^*]+)\*\*/g, function(m,b){ return "<b>"+b+"</b>"; });
  if(ADO_BASE){ e=e.replace(/\b(ADO(?:\s+item)?\s+#?)(\d{3,})\b/gi, function(m,p,n){ return p+"<a href='"+ADO_BASE+"/_workitems/edit/"+n+"' target='_blank' rel='noopener'>"+n+"</a>"; }); }
  return e;
}
function linkify(s){ return mdInline(esc(s)); }
function mdNote(s){
  var lines=String(s==null?'':s).split(/\r?\n/);
  var html=''; var inList=false;
  function closeList(){ if(inList){ html+='</ul>'; inList=false; } }
  lines.forEach(function(ln){
    var t=ln.replace(/\s+$/,'');
    var li=t.match(/^\s*[-*]\s+(.*)$/);
    if(li){ if(!inList){ html+="<ul class='nlist'>"; inList=true; } html+='<li>'+mdInline(esc(li[1]))+'</li>'; return; }
    closeList();
    if(t.trim()===''){ return; }
    var h=t.match(/^\s*(#{1,6})\s+(.*)$/);
    if(h){ html+="<div class='nh'>"+mdInline(esc(h[2]))+"</div>"; return; }
    html+="<div class='np'>"+mdInline(esc(t))+"</div>";
  });
  closeList();
  return html;
}
function pad(n){ return (n<10?'0':'')+n; }
function ymd(y,m,d){ return y+'-'+pad(m+1)+'-'+pad(d); }
var DAYMAP={};
SESSIONS.forEach(function(s,i){ s._uid=i; });
SESSIONS.forEach(function(s){ if(!DAYMAP[s.date]) DAYMAP[s.date]={count:0,min:0}; DAYMAP[s.date].count++; DAYMAP[s.date].min+=s.min; });
function renderCal(){
  var first=new Date(calY,calM,1);
  var startDow=(first.getDay()+6)%7;
  var daysIn=new Date(calY,calM+1,0).getDate();
  var now=new Date(); var tstr=ymd(now.getFullYear(),now.getMonth(),now.getDate());
  var h="<div class='cal-head'><button class='cbtn' onclick='navMonth(-1)'>&#8249;</button><div class='cal-title'>"+MONTHS[calM]+' '+calY+"</div><button class='cbtn' onclick='navMonth(1)'>&#8250;</button></div><div class='cal-grid'>";
  for(var i=0;i<7;i++){ h+="<div class='dow'>"+DOW[i]+"</div>"; }
  for(var b=0;b<startDow;b++){ h+="<div class='cal-day'></div>"; }
  for(var d=1;d<=daysIn;d++){
    var ds=ymd(calY,calM,d);
    var cls='cal-day in'; var dot='';
    if(DAYMAP[ds]){ cls+=' has'; dot="<span class='dot'></span>"; }
    if(ds===tstr){ cls+=' today'; }
    if(isSel(ds)){ cls+=' sel'; }
    var clk = DAYMAP[ds] ? (" onclick=\"selDay('"+ds+"',event)\" title=\""+fmtMin(DAYMAP[ds].min)+", "+DAYMAP[ds].count+" session(s)\"") : '';
    h+="<div class='"+cls+"'"+clk+"><span>"+d+"</span>"+dot+"</div>";
  }
  h+="</div><div class='cal-foot'><button class='pill' onclick='clearSel()'>All dates</button></div>";
  document.getElementById('cal').innerHTML=h;
}
function navMonth(delta){ calM+=delta; if(calM<0){ calM=11; calY--; } if(calM>11){ calM=0; calY++; } renderCal(); }
function selDay(ds,ev){
  var multi = ev && (ev.ctrlKey || ev.metaKey);
  if(multi){
    var i=sel.indexOf(ds);
    if(i===-1){ sel.push(ds); } else { sel.splice(i,1); }
  } else {
    sel=(sel.length===1 && sel[0]===ds) ? [] : [ds];
  }
  renderCal(); renderView();
  if(!multi){ document.getElementById('log').scrollIntoView({behavior:'smooth',block:'start'}); }
}
function clearSel(){ sel=[]; renderCal(); renderView(); }
var SEARCH='';
function matchQ(s,q){
  if(!q) return true;
  var hay=[s.title,s.accomplishment,s.blocker,s.project,s.category,s.adoId].join('\n');
  if(s.notes){ s.notes.forEach(function(n){ hay+='\n'+(n.text||''); }); }
  return hay.toLowerCase().indexOf(q)!==-1;
}
function onSearch(v){ SEARCH=(v||'').trim().toLowerCase(); renderView(); }
function clearSearch(){ var b=document.getElementById('q'); if(b){ b.value=''; } onSearch(''); }
function curSet(){ var base = sel.length ? SESSIONS.filter(function(s){ return isSel(s.date); }) : SESSIONS.slice(); return SEARCH ? base.filter(function(s){ return matchQ(s,SEARCH); }) : base; }
function autoSummary(set){
  if(!set.length) return '';
  var cat={}; set.forEach(function(s){ var c=s.category||'Other'; cat[c]=(cat[c]||0)+s.min; });
  var keys=Object.keys(cat).sort(function(a,b){ return cat[b]-cat[a]; });
  var top=keys.slice(0,3);
  var lead = top.length>1 ? (top.slice(0,-1).join(', ')+' and '+top[top.length-1]) : top[0];
  return 'Focused mainly on '+lead+' across '+set.length+' session'+(set.length===1?'':'s')+'.';
}
function dayCommentary(set){
  if(!set.length) return '';
  var dates={}; set.forEach(function(s){ dates[s.date]=1; });
  var dk=Object.keys(dates);
  if(dk.length===1 && COMMENTARY[dk[0]]) return COMMENTARY[dk[0]];
  return autoSummary(set);
}
function renderSummary(){
  var set=curSet(); var total=0; var cat={};
  set.forEach(function(s){ total+=s.min; var c=s.category||'Other'; cat[c]=(cat[c]||0)+s.min; });
  var chips='';
  Object.keys(cat).sort(function(a,b){ return cat[b]-cat[a]; }).forEach(function(c){ chips+="<span class='chip'>"+esc(c)+': '+fmtMin(cat[c])+"</span>"; });
  if(!chips){ chips="<span class='muted'>No work logged.</span>"; }
  var label = sel.length ? (sel.length===1 ? sel[0] : (sel.length+' dates: '+sel.slice().sort().join(', '))) : 'All time';
  if(SEARCH){ label += ' \u2022 \u201C'+SEARCH+'\u201D'; }
  var comm = dayCommentary(set);
  document.getElementById('sum').innerHTML =
    "<div class='sum-row'><div class='stat'><div class='big'>"+fmtMin(total)+"</div><div class='lbl'>Total time</div></div>"+
    "<div class='stat'><div class='big'>"+set.length+"</div><div class='lbl'>Sessions</div></div>"+
    "<div class='stat'><div class='big'>"+Object.keys(cat).length+"</div><div class='lbl'>Categories</div></div></div>"+
    "<div class='chips'>"+chips+"</div><div class='scope'>Showing: <b>"+esc(label)+"</b></div>"+
    (comm ? "<div class='commentary' title='"+esc(comm)+"'><b>Highlights:</b> "+esc(comm)+"</div>" : "");
}
function renderTable(){
  var set=curSet().slice().sort(function(a,b){ if(a.date!==b.date){ return a.date<b.date?1:-1; } return a.start<b.start?-1:1; });
  if(!set.length){ document.getElementById('log').innerHTML="<div class='empty'>No sessions"+(SEARCH?" matching \u201C"+esc(SEARCH)+"\u201D":"")+" for this selection.</div>"; return; }
  var groups={}; var order=[];
  set.forEach(function(s){ if(!groups[s.date]){ groups[s.date]=[]; order.push(s.date); } groups[s.date].push(s); });
  var h='';
  order.forEach(function(dt){
    var rows=groups[dt]; var dmin=0; rows.forEach(function(r){ dmin+=r.min; });
    var o=new Date(dt+'T00:00:00');
    var dl=WEEKDAYS[(o.getDay()+6)%7]+', '+MONTHS[o.getMonth()]+' '+o.getDate()+', '+o.getFullYear();
    h+="<div class='daygrp'><div class='dayhdr'><span>"+esc(dl)+"</span><span class='daytot'>"+fmtMin(dmin)+" &bull; "+rows.length+" session(s)</span></div>";
    h+="<table class='log day'><colgroup><col style='width:4%'><col style='width:10%'><col style='width:6%'><col style='width:9%'><col style='width:11%'><col style='width:24%'><col style='width:32%'><col style='width:4%'></colgroup><thead><tr><th class='center'>#</th><th>Time</th><th>Dur</th><th>Category</th><th>Project</th><th>Item</th><th>Accomplishment</th><th class='center'>Notes</th></tr></thead><tbody>";
    rows.forEach(function(s,ri){
      var stopped = (s.status==='done');
      var time=esc(s.start)+(s.end ? ' &ndash; '+esc(s.end) : " <span class='run'>&bull; open</span>");
      var item = s.url ? "<a href='"+esc(s.url)+"' target='_blank'>"+esc(s.title)+"</a>" : esc(s.title);
      if(s.adoId){ item="<span class='adoid'>#"+esc(s.adoId)+"</span> "+item; }
      if(!stopped){
        var st=(s.status||(s.end?'':'open'));
        var lab = !s.end ? 'open' : st;
        var cls = (lab==='open')?'open':(lab==='paused'?'paused':'inprogress');
        item+="<span class='sbadge "+cls+"' title='Not stopped'>"+esc(lab)+"</span>";
      }
      var acc = s.accomplishment ? esc(s.accomplishment) : "<span class='muted'>&mdash;</span>";
      if(s.blocker){ acc+="<div class='blk'>&#9888; "+esc(s.blocker)+"</div>"; }
      var notes=(s.notes && s.notes.length)?"<button class='ncount nbtn' onclick='openNotes("+s._uid+")' title='View notes'>"+s.notes.length+"</button>":"<span class='muted'>0</span>";
      var proj = s.project ? "<span class='proj'>"+esc(s.project)+"</span>" : "<span class='muted'>&mdash;</span>";
      h+="<tr class='"+(stopped?'':'unstopped')+"'><td class='center'><span class='idnum' title='id "+s.id+"'>"+(ri+1)+"</span></td><td class='nowrap'>"+time+"</td><td class='nowrap'>"+fmtMin(s.min)+"</td><td><span class='cat'>"+esc(s.category||'Other')+"</span></td><td>"+proj+"</td><td>"+item+"</td><td>"+acc+"</td><td class='center'>"+notes+"</td></tr>";
    });
    h+="</tbody></table></div>";
  });
  document.getElementById('log').innerHTML=h;
}
function renderView(){ renderSummary(); renderTable(); }
function byId(uid){ for(var i=0;i<SESSIONS.length;i++){ if(SESSIONS[i]._uid===uid) return SESSIONS[i]; } return null; }
function openNotes(id){
  var s=byId(id); if(!s || !s.notes || !s.notes.length) return;
  document.getElementById('mTitle').innerHTML=esc(s.title||'');
  var b="<table class='log'><thead><tr><th class='nowrap'>When</th><th>Note</th></tr></thead><tbody>";
  s.notes.forEach(function(n){ b+="<tr><td class='nowrap muted'>"+fmtTs(n.ts)+"</td><td>"+mdNote(n.text)+"</td></tr>"; });
  b+="</tbody></table>";
  document.getElementById('mBody').innerHTML=b;
  document.getElementById('modal').classList.add('show');
}
function closeNotes(){ document.getElementById('modal').classList.remove('show'); }
document.addEventListener('keydown', function(e){ if(e.key==='Escape') closeNotes(); });
(function(){
  var n=new Date(); var today=ymd(n.getFullYear(), n.getMonth(), n.getDate());
  calY=n.getFullYear(); calM=n.getMonth();
  sel=[today]; renderCal(); renderView();
})();
'@

    $html = @"
<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'><title>Work Log</title>
<style>$script:BaseCss
.searchbar{display:flex;gap:.5rem;align-items:center;margin:0 0 .75rem 0;}
.searchbar input{flex:1;padding:.55rem .8rem;border-radius:0;border:1px solid var(--bd,#d0d7de);background:var(--card,#fff);color:inherit;font-size:.95rem;outline:none;}
.searchbar input:focus{border-color:var(--accent);box-shadow:0 0 0 2px rgba(77,141,255,.25);}
.searchbar button{padding:.55rem 1rem;font-size:.9rem;line-height:1;color:var(--muted);transition:background .15s,border-color .15s,color .15s;}
.searchbar button:hover{background:var(--card2);border-color:var(--accent);color:var(--text);}
.nh{font-weight:700;margin:.5rem 0 .25rem;}
.np{margin:.25rem 0;}
.nlist{margin:.25rem 0 .25rem 1.1rem;padding:0;}
.nlist li{margin:.15rem 0;}
.modal-body code{background:var(--card2,rgba(127,127,127,.18));padding:.05rem .35rem;border-radius:3px;font-size:.86em;}
</style></head><body>
<div class='page'>
<header class='rpt-hero'><div><h1>Work Log</h1><div class='meta'>$meta</div></div></header>
<div class='top'>
  <div class='card'><div id='cal'></div></div>
  <div class='card'><div id='sum'></div></div>
</div>
<div class='searchbar'>
  <input id='q' type='search' placeholder='Search title, notes, project, accomplishment&hellip;' oninput='onSearch(this.value)' autocomplete='off'>
  <button class='pill' onclick='clearSearch()'>Clear</button>
</div>
<div id='log'></div>
</div>
<div id='modal' class='modal' onclick='if(event.target===this)closeNotes()'>
  <div class='modal-box'>
    <div class='modal-head'><span id='mTitle'></span><button class='cbtn' onclick='closeNotes()'>&times;</button></div>
    <div id='mBody' class='modal-body'></div>
  </div>
</div>
<script>
var SESSIONS = $json;
var COMMENTARY = $commentaryJson;
var ADO_BASE = "$($script:Org)";
$js
</script>
</body></html>
"@

    $outPath = Join-Path $script:OutDir 'work-dashboard.html'
    [System.IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Wrote $outPath"
    if (-not $NoOpen) { Start-Process $outPath }
    [pscustomobject]@{ Html = $outPath }
}

Export-ModuleMember -Function Start-Work, Switch-Work, Stop-Work, Complete-Work, New-GhIssueNote, Add-WorkNote, Edit-Work, Set-DayCommentary, `
    Get-OpenSessions, Get-WorkLog, Find-WorkLog, Show-WorkSearch, Show-WorkStatus, New-Standup, New-WeeklySummary, New-WorkDashboard, `
    Set-WorkProfile, Set-WorkDefaultProfile, Get-WorkProfile
