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
        if ($_ -ieq 'ai') { 'AI' } else { $_.ToLowerInvariant() }
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
            if (-not $h.ContainsKey('notes') -or $null -eq $h['notes']) { $h['notes'] = @() }
            $h['notes'] = @($h['notes'])
            if (-not $h.ContainsKey('nextNoteId')) { $h['nextNoteId'] = ($h['notes'].Count + 1) }
            return $h
        }
    }
    return @{ current = $null; nextId = 1; sessions = @(); notes = @(); nextNoteId = 1 }
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

# ---- Workday-boundary enforcement -----------------------------------------
# Rules (per user policy):
#   1. Nothing can be logged until that day's START-of-day marker exists.
#   2. A task cannot START before the start-of-day marker time.
#   3. A task cannot END after the end-of-day marker time.
# Day markers themselves (Add-DayMarker) are exempt — they set the boundaries.
function Get-DayMarker($state, [ValidateSet('start', 'end')][string]$Type, [datetime]$Date) {
    $kind = "marker-$Type"
    $day  = $Date.ToString('yyyy-MM-dd')
    $m = @($state['sessions'] | Where-Object { $_['kind'] -eq $kind -and (ParseTs $_['start']).ToString('yyyy-MM-dd') -eq $day })
    if ($m.Count) { return $m[0] }
    return $null
}

# Validate the START of a task on its day: the start marker must exist, the start
# time must be >= it, and (if an end marker exists) the start must be <= it.
function Assert-WorkdayStart($state, [datetime]$At) {
    $sm = Get-DayMarker $state 'start' $At
    if (-not $sm) {
        throw "No start-of-day marker for $($At.ToString('yyyy-MM-dd')). Set it first: Work.ps1 startday"
    }
    $smT = ParseTs $sm['start']
    if ($At -lt $smT) {
        throw "Task can't start at $($At.ToString('HH:mm')) — before the start-of-day marker ($($smT.ToString('HH:mm')))."
    }
    $em = Get-DayMarker $state 'end' $At
    if ($em) {
        $emT = ParseTs $em['end']
        if ($At -gt $emT) {
            throw "Task can't start at $($At.ToString('HH:mm')) — after the end-of-day marker ($($emT.ToString('HH:mm')))."
        }
    }
}

# Validate the END of a task against that day's end-of-day marker (if any).
function Assert-WorkdayEnd($state, [datetime]$At, [datetime]$DayOf) {
    $em = Get-DayMarker $state 'end' $DayOf
    if ($em) {
        $emT = ParseTs $em['end']
        if ($At -gt $emT) {
            throw "Task can't end at $($At.ToString('HH:mm')) — after the end-of-day marker ($($emT.ToString('HH:mm')))."
        }
    }
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
    Assert-WorkdayStart $st $At
    $id = [int]$st['nextId']
    $kind = if ($AdoId) { 'ado' } else { 'adhoc' }
    $Category = ConvertTo-TitleCaseCategory $Category
    $Title = ConvertTo-FirstCapital $Title
    $s = @{
        id = $id; kind = $kind; adoId = $AdoId; category = $Category; project = (ConvertTo-TitleCaseCategory $Project); tags = @($Tags)
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

# ---- Public: Add a complete (already-finished) session ---------------------
# Create a session in one shot with explicit start/end (used by the dashboard's
# "New item" button and `Work.ps1 add`). If no end is given it stays in-progress.
function New-WorkSession {
    [CmdletBinding()]
    param(
        [datetime]$Start = (Get-Date),
        [datetime]$End,
        [string]$Title = '',
        [string]$Category = '',
        [string]$Project = '',
        [string]$AdoId = '',
        [string[]]$Tags = @(),
        [string]$Accomplishment = ''
    )
    $st = Get-LogState
    $id = [int]$st['nextId']
    $kind = if ($AdoId) { 'ado' } else { 'adhoc' }
    $hasEnd = $PSBoundParameters.ContainsKey('End') -and $End
    $dur = if ($hasEnd) { [math]::Round((($End) - $Start).TotalMinutes) } else { 0 }
    Assert-WorkdayStart $st $Start
    if ($hasEnd) { Assert-WorkdayEnd $st $End $Start }
    $s = @{
        id = $id; kind = $kind; adoId = $AdoId
        category = ConvertTo-TitleCaseCategory $Category; project = (ConvertTo-TitleCaseCategory $Project); tags = @($Tags)
        title = ConvertTo-FirstCapital $Title; start = $Start.ToString($script:Fmt)
        end = $(if ($hasEnd) { $End.ToString($script:Fmt) } else { $null })
        durationMin = $dur
        status = $(if ($hasEnd) { 'done' } else { 'in-progress' })
        accomplishment = ConvertTo-FirstCapital $Accomplishment; blocker = ''; notes = @()
    }
    $st['sessions'] = @($st['sessions']) + $s
    $st['nextId']   = $id + 1
    Save-LogState $st
    Write-Host ("+ Added #{0}: {1}" -f $id, $s['title'])
    return (ConvertTo-SessionView $s)
}

# ---- Public: Day markers (0-minute start/end-of-workday markers) -----------
function Add-DayMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('start', 'end')][string]$Type,
        [datetime]$At = (Get-Date)
    )
    $st    = Get-LogState
    $kind  = "marker-$Type"
    $day   = $At.ToString('yyyy-MM-dd')
    $title = if ($Type -eq 'start') { 'Start work day' } else { 'End work day' }
    # If a marker of this type already exists for the day, just move its time.
    $existing = @($st['sessions'] | Where-Object { $_['kind'] -eq $kind -and (ParseTs $_['start']).ToString('yyyy-MM-dd') -eq $day })
    if ($existing.Count) {
        $m = $existing[0]
        $m['start'] = $At.ToString($script:Fmt)
        $m['end']   = $At.ToString($script:Fmt)
        $m['durationMin'] = 0
        Save-LogState $st
        Write-Host ("~ Updated {0} #{1} to {2}" -f $title, [int]$m['id'], $At.ToString('HH:mm'))
        return (ConvertTo-SessionView $m)
    }
    $id = [int]$st['nextId']
    $s = @{
        id = $id; kind = $kind; adoId = ''
        category = 'Day'; project = ''; tags = @()
        title = $title; start = $At.ToString($script:Fmt); end = $At.ToString($script:Fmt)
        durationMin = 0; status = 'done'; accomplishment = ''; blocker = ''; notes = @()
    }
    $st['sessions'] = @($st['sessions']) + $s
    $st['nextId']   = $id + 1
    Save-LogState $st
    Write-Host ("> {0} #{1} at {2}" -f $title, $id, $At.ToString('HH:mm'))
    return (ConvertTo-SessionView $s)
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
    Assert-WorkdayEnd $st $At (ParseTs $s['start'])
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

# ---- Standalone date-bound notes (NOT time-bound) --------------------------
# These are independent of work sessions: a note belongs to a calendar date and
# carries text + optional category + tags. Stored in the same per-profile state
# file under 'notes', so they honor the work/personal profile split.

function Save-NoteState($state) {
    # Persist without rebuilding the (session) work dashboard, then rebuild the
    # notes dashboard so it always reflects the latest notes.
    $prev = $script:SuppressDashboard
    $script:SuppressDashboard = $true
    try { Save-LogState $state } finally { $script:SuppressDashboard = $prev }
    try { New-NotesDashboard -NoOpen | Out-Null }
    catch { Write-Warning "Notes dashboard rebuild failed: $($_.Exception.Message)" }
}

function Add-Note {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [datetime]$Date = (Get-Date),
        [string]$Category = '',
        [string[]]$Tags = @()
    )
    $st = Get-LogState
    $id = [int]$st['nextNoteId']
    $note = @{
        id       = $id
        date     = $Date.ToString('yyyy-MM-dd')
        text     = (ConvertTo-FirstCapital $Text.Trim())
        category = (ConvertTo-TitleCaseCategory $Category)
        tags     = @($Tags)
        created  = NowStr
    }
    $arr = [System.Collections.ArrayList]@($st['notes'])
    [void]$arr.Add($note)
    $st['notes'] = $arr.ToArray()
    $st['nextNoteId'] = $id + 1
    Save-NoteState $st
    $catLbl = if ($note.category) { " [$($note.category)]" } else { '' }
    Write-Host ("+ Added note #{0} ({1}){2}" -f $id, $note.date, $catLbl)
}

function Edit-Note {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Id,
        [string]$Text,
        [datetime]$Date,
        [string]$Category,
        [string[]]$Tags
    )
    $st = Get-LogState
    $n = $st['notes'] | Where-Object { [int]$_['id'] -eq $Id } | Select-Object -First 1
    if (-not $n) { throw "No note #$Id." }
    $changed = @()
    if ($PSBoundParameters.ContainsKey('Text'))     { $n['text'] = ConvertTo-FirstCapital $Text.Trim(); $changed += 'text' }
    if ($PSBoundParameters.ContainsKey('Date'))     { $n['date'] = $Date.ToString('yyyy-MM-dd'); $changed += 'date' }
    if ($PSBoundParameters.ContainsKey('Category')) { $n['category'] = ConvertTo-TitleCaseCategory $Category; $changed += 'category' }
    if ($PSBoundParameters.ContainsKey('Tags'))     { $n['tags'] = @($Tags); $changed += 'tags' }
    if (-not $changed.Count) { Write-Host "Nothing to change for note #$Id."; return }
    Save-NoteState $st
    Write-Host ("~ Edited note #{0} (updated: {1})" -f $Id, ($changed -join ', '))
}

function Remove-Note {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Id)
    $st = Get-LogState
    $before = @($st['notes']).Count
    $st['notes'] = @($st['notes'] | Where-Object { [int]$_['id'] -ne $Id })
    if (@($st['notes']).Count -eq $before) { throw "No note #$Id." }
    Save-NoteState $st
    Write-Host ("- Removed note #{0}" -f $Id)
}

function Get-Notes {
    [CmdletBinding()]
    param([datetime]$Since)
    $st = Get-LogState
    $items = @($st['notes'] | ForEach-Object {
        [pscustomobject]@{
            Id       = [int]$_['id']
            Date     = [string]$_['date']
            Category = [string]$_['category']
            Tags     = @($_['tags'])
            Text     = [string]$_['text']
            Created  = [string]$_['created']
        }
    })
    if ($PSBoundParameters.ContainsKey('Since')) {
        $items = @($items | Where-Object {
            ([datetime]::ParseExact($_.Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)) -ge $Since.Date
        })
    }
    @($items | Sort-Object @{ Expression = 'Date'; Descending = $true }, @{ Expression = 'Id'; Descending = $true })
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
    if ($PSBoundParameters.ContainsKey('Project'))       { $s['project'] = (ConvertTo-TitleCaseCategory $Project); $changed += 'project' }
    if ($PSBoundParameters.ContainsKey('AdoId'))         { $s['adoId'] = $AdoId; $s['kind'] = if ($AdoId) { 'ado' } else { 'adhoc' }; $changed += 'adoId' }
    if ($PSBoundParameters.ContainsKey('Tags'))          { $s['tags'] = @($Tags); $changed += 'tags' }
    if ($PSBoundParameters.ContainsKey('Accomplishment')){ $s['accomplishment'] = ConvertTo-FirstCapital $Accomplishment; $changed += 'accomplishment' }
    if ($PSBoundParameters.ContainsKey('Blocker'))       { $s['blocker'] = ConvertTo-FirstCapital $Blocker; $changed += 'blocker' }
    if ($PSBoundParameters.ContainsKey('Status'))        { $s['status'] = $Status; $changed += 'status' }
    if ($PSBoundParameters.ContainsKey('Start'))         { $s['start'] = $Start.ToString($script:Fmt); $changed += 'start' }
    if ($PSBoundParameters.ContainsKey('End'))           {
        $s['end'] = $End.ToString($script:Fmt); $changed += 'end'
        # Adding an end time to an open session closes it; mark done unless the
        # caller explicitly set a status (mirrors Stop-Work's default).
        if (-not $PSBoundParameters.ContainsKey('Status') -and $s['status'] -eq 'in-progress') {
            $s['status'] = 'done'; $changed += 'status'
        }
    }
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
:root{--bg:#0a0e1a;--card:#0f1524;--card2:#151c2d;--border:#1e2739;--text:#e9eef6;--muted:#7d8a9e;--accent:#4d8dff;--green:#33d685;--red:#ff5d5d;--amber:#ffb648;--proj:#a06bff;--mono:'Roboto Mono',Consolas,monospace;--font:'Roboto Flex',system-ui,sans-serif;--scheme:dark;--on-accent:var(--bg);--bg-grad:none;}
/* Derived tints — auto-recompute from --accent when a theme overrides it */
:root{
  --accent2:color-mix(in srgb,var(--accent) 58%,#fff);
  --a06:color-mix(in srgb,var(--accent) 6%,transparent);
  --a10:color-mix(in srgb,var(--accent) 10%,transparent);
  --a14:color-mix(in srgb,var(--accent) 14%,transparent);
  --a22:color-mix(in srgb,var(--accent) 22%,transparent);
  --a33:color-mix(in srgb,var(--accent) 33%,transparent);
  --accent-hover:color-mix(in srgb,var(--accent),#000 14%);
  --hover:color-mix(in srgb,var(--accent) 8%,var(--card));
  --proj-soft:color-mix(in srgb,var(--proj) 16%,transparent);
  --proj-fg:color-mix(in srgb,var(--proj) 52%,#fff);
  --green-soft:color-mix(in srgb,var(--green) 16%,transparent);
  --green-line:color-mix(in srgb,var(--green) 33%,transparent);
  --amber-faint:color-mix(in srgb,var(--amber) 6%,transparent);
  --red-soft:color-mix(in srgb,var(--red) 12%,transparent);
}
/* ---- Theme presets ------------------------------------------------------ */
html[data-theme=nord]{--bg:#2e3440;--card:#3b4252;--card2:#434c5e;--border:#4c566a;--text:#eceff4;--muted:#9aa5b8;--accent:#88c0d0;--green:#a3be8c;--red:#bf616a;--amber:#ebcb8b;--proj:#b48ead;--on-accent:#2e3440;}
html[data-theme=dracula]{--bg:#282a36;--card:#2d2f3d;--card2:#343746;--border:#44475a;--text:#f8f8f2;--muted:#8b8fa3;--accent:#bd93f9;--green:#50fa7b;--red:#ff5555;--amber:#ffb86c;--proj:#ff79c6;--on-accent:#282a36;}
html[data-theme=rose]{--bg:#191724;--card:#1f1d2e;--card2:#26233a;--border:#403d52;--text:#e0def4;--muted:#908caa;--accent:#c4a7e7;--green:#9ccfd8;--red:#eb6f92;--amber:#f6c177;--proj:#ebbcba;--on-accent:#191724;}
html[data-theme=tokyo]{--bg:#1a1b26;--card:#1f2335;--card2:#24283b;--border:#2f334d;--text:#c0caf5;--muted:#7982a9;--accent:#7aa2f7;--green:#9ece6a;--red:#f7768e;--amber:#e0af68;--proj:#bb9af7;--on-accent:#1a1b26;}
html[data-theme=paper]{--bg:#f6f8fa;--card:#ffffff;--card2:#eef1f5;--border:#d0d7de;--text:#1f2328;--muted:#656d76;--accent:#0969da;--green:#1a7f37;--red:#cf222e;--amber:#9a6700;--proj:#8250df;--on-accent:#ffffff;--scheme:light;}
*{box-sizing:border-box;}
html{scroll-behavior:smooth;}
body{font-family:var(--font);font-optical-sizing:auto;margin:0;background:var(--bg);background-image:var(--bg-grad);background-attachment:fixed;color:var(--text);line-height:1.55;transition:background-color .35s ease,color .35s ease;}
@keyframes wlFade{from{opacity:0;transform:translateY(8px);}to{opacity:1;transform:none;}}
@keyframes wlPulse{0%{box-shadow:0 0 0 0 var(--green-line);}70%{box-shadow:0 0 0 6px transparent;}100%{box-shadow:0 0 0 0 transparent;}}
.card,table.log,table.log th,.pill,.cbtn,.themesel,.helpbar{transition:background-color .3s ease,border-color .3s ease,color .3s ease,box-shadow .18s ease,transform .18s ease;}
.page{max-width:none;margin:0;padding:26px 15% 80px;}
a{color:var(--accent);text-decoration:none;}a:hover{text-decoration:underline;}
.rpt-hero{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;padding:6px 2px 16px;border-bottom:2px solid var(--border);border-image:linear-gradient(90deg,var(--accent),transparent 75%) 1;}
.rpt-hero h1{font-size:26px;font-weight:800;letter-spacing:-.3px;margin:0;background:linear-gradient(92deg,var(--text) 30%,var(--accent));-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;}
.meta{color:var(--muted);font-size:13px;margin-top:6px;}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.7px;color:var(--muted);margin:26px 0 10px;font-weight:600;}
.card{background:var(--card);border:1px solid var(--border);border-radius:0;padding:18px;}
.card:hover{border-color:var(--a33);box-shadow:0 8px 26px rgba(0,0,0,.22);}
.muted{color:var(--muted);}.nowrap{white-space:nowrap;}.center{text-align:center;}
.run{color:var(--green);font-weight:600;}
.blk{color:var(--red);font-size:12px;margin-top:4px;}
.cat{display:inline-block;background:var(--a14);color:var(--accent2);border-radius:0;padding:2px 10px;font-size:11px;font-weight:600;white-space:nowrap;}
.proj{display:inline-block;background:var(--proj-soft);color:var(--proj-fg);border-radius:0;padding:2px 10px;font-size:11px;font-weight:600;}
.sbadge{display:inline-block;border-radius:0;padding:1px 8px;font-size:10px;font-weight:700;letter-spacing:.4px;text-transform:uppercase;margin-left:8px;vertical-align:middle;white-space:nowrap;border:1px solid transparent;}
.sbadge.open{background:var(--green-soft);color:var(--green);border-color:var(--green-line);animation:wlPulse 2.4s ease-out infinite;}
.sbadge.paused{background:color-mix(in srgb,var(--amber) 14%,transparent);color:var(--amber);border-color:color-mix(in srgb,var(--amber) 33%,transparent);}
.sbadge.inprogress{background:var(--a14);color:var(--accent2);border-color:var(--a33);}
tr.unstopped td{background:var(--amber-faint);}
tr.unstopped td:first-child{box-shadow:inset 3px 0 0 var(--amber);}
.adoid{color:var(--muted);font-family:var(--mono);font-size:11.5px;font-weight:500;}
.idnum{font-family:var(--mono);font-size:12px;font-weight:600;color:var(--accent);}
.chip{display:inline-block;background:var(--a10);color:var(--accent2);border:1px solid var(--a22);border-radius:0;padding:3px 11px;font-size:12px;margin:0 6px 6px 0;}
.ncount{display:inline-block;min-width:20px;text-align:center;background:var(--a22);color:var(--accent2);border-radius:0;font-size:11px;padding:1px 7px;font-weight:600;cursor:default;}
table.log{width:100%;border-collapse:separate;border-spacing:0;background:var(--card);border:1px solid var(--border);border-radius:0;overflow:hidden;}
table.log th{background:var(--card2);color:var(--muted);text-transform:uppercase;font-size:10.5px;letter-spacing:.5px;font-weight:600;text-align:left;padding:10px 14px;position:sticky;top:0;z-index:3;}
table.log td{padding:11px 14px;border-top:1px solid var(--border);font-size:13.5px;vertical-align:top;}
table.log tbody tr:hover td{background:var(--hover);}
table.log tbody tr:hover td:first-child{box-shadow:inset 3px 0 0 var(--accent);}
table.log.day{table-layout:fixed;}
table.log.day th,table.log.day td{overflow-wrap:anywhere;word-break:break-word;}
table.log.day td.nowrap{white-space:normal;}
.callout{display:flex;gap:9px;background:var(--a06);border-left:3px solid var(--accent);border-radius:0;padding:11px 15px;font-size:13.5px;margin:8px 0;}
.callout.warn{background:var(--red-soft);border-left-color:var(--red);}
.top{display:grid;grid-template-columns:300px 1fr;gap:16px;margin:18px 0 8px;}
.sum-row{display:flex;gap:28px;flex-wrap:wrap;margin-bottom:14px;}
.stat .big{font-size:26px;font-weight:700;font-variant-numeric:tabular-nums;background:linear-gradient(92deg,var(--text),var(--accent));-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;}
.stat .lbl{font-size:10.5px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted);}
.chips{margin-bottom:8px;}.scope{font-size:12.5px;color:var(--muted);}
.commentary{margin:10px 0 2px;padding:7px 10px;border-left:3px solid var(--accent);background:var(--a06);border-radius:4px;font-size:12.5px;font-style:italic;line-height:1.45;color:var(--muted);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;}
.commentary b{font-style:normal;color:var(--text);font-weight:600;}
.daygrp{margin:0 0 18px;animation:wlFade .4s ease both;}
.dayhdr{display:flex;justify-content:space-between;align-items:baseline;margin:0 0 8px;padding:0 2px;}
.dayhdr span:first-child{font-size:15px;font-weight:700;color:var(--accent);}
.daytot{font-size:12px;color:var(--muted);}
.empty{color:var(--muted);padding:34px;text-align:center;background:var(--card);border:1px solid var(--border);border-radius:0;}
.cal-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;}
.cal-title{font-size:14px;font-weight:700;}
.cbtn{background:var(--card2);border:1px solid var(--border);color:var(--text);border-radius:0;width:30px;height:30px;cursor:pointer;font-size:16px;line-height:1;}
.cbtn:hover{background:var(--hover);}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:5px;}
.cal-grid .dow{font-size:9.5px;color:var(--muted);text-align:center;text-transform:uppercase;padding-bottom:3px;}
.cal-day{aspect-ratio:1;display:flex;flex-direction:column;align-items:center;justify-content:center;border-radius:0;font-size:13px;color:color-mix(in srgb,var(--muted) 60%,transparent);transition:background .15s ease,transform .1s ease;}
.cal-day.in{color:var(--text);}
.cal-day.has{background:var(--a14);cursor:pointer;font-weight:600;}
.cal-day.has:hover{background:var(--a33);transform:scale(1.08);}
.cal-day.today{outline:1.5px solid var(--accent);outline-offset:-1.5px;}
.cal-day.sel{background:var(--accent);color:var(--on-accent);}
.cal-day .dot{width:5px;height:5px;border-radius:50%;background:var(--accent);margin-top:3px;}
.cal-day.sel .dot{background:var(--on-accent);}
.cal-foot{margin-top:12px;text-align:center;}
.pill{background:var(--card2);border:1px solid var(--border);color:var(--text);border-radius:0;padding:5px 14px;font-size:12px;cursor:pointer;}
.pill:hover{background:var(--hover);}
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
            kind  = $_.Kind
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
    $notesData = @(Get-Notes | ForEach-Object {
        [pscustomobject]@{
            id       = $_.Id
            date     = $_.Date
            category = $_.Category
            tags     = @($_.Tags)
            text     = $_.Text
            created  = $_.Created
        }
    })
    $notesJson = ConvertTo-Json -InputObject $notesData -Depth 5 -AsArray
    $notesJson = $notesJson.Replace('</', '<\/')
    $count = $data.Count
    $totalMin = (@($data) | Measure-Object min -Sum).Sum; if (-not $totalMin) { $totalMin = 0 }
    $meta = "Generated $((Get-Date).ToString('yyyy-MM-dd HH:mm')) &bull; $count session(s) &bull; $(FmtMin ([int]$totalMin)) total &bull; click a highlighted day to filter"

    $js = @'
var MONTHS=['January','February','March','April','May','June','July','August','September','October','November','December'];
var WEEKDAYS=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
var DOW=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
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
  var startDow=first.getDay();
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
var SHOW_GAPS=false; try{ SHOW_GAPS=(localStorage.getItem('wl_gaps')==='1'); }catch(e){}
function noteOnly(){ return SEARCH==='is_note' || SEARCH==='is_notes'; }
function matchQ(s,q){
  if(!q) return true;
  if(noteOnly()) return false;
  var hay=[s.title,s.accomplishment,s.blocker,s.project,s.category,s.adoId].join('\n');
  hay+='\n'+(s.end ? ('is_done '+(s.status||'done')) : ('is_open in-progress '+(s.status||'')));
  if(s.notes){ s.notes.forEach(function(n){ hay+='\n'+(n.text||''); }); }
  return hay.toLowerCase().indexOf(q)!==-1;
}
function onSearch(v){ SEARCH=(v||'').trim().toLowerCase(); renderView(); }
function clearSearch(){ var b=document.getElementById('q'); if(b){ b.value=''; b.focus(); } onSearch(''); }
var _wlToastT;
function wlToast(msg){ var el=document.getElementById('wlToast'); if(!el) return; el.innerHTML=msg; el.classList.add('show'); clearTimeout(_wlToastT); _wlToastT=setTimeout(function(){ el.classList.remove('show'); }, 1600); }
function focusSearch(){ var q=document.getElementById('q'); if(q){ q.focus(); q.select(); } }
function parseYMD(s){ var p=s.split('-'); return new Date(+p[0],+p[1]-1,+p[2]); }
function gotoDay(dt){
  var ds=ymd(dt.getFullYear(),dt.getMonth(),dt.getDate());
  sel=[ds]; calY=dt.getFullYear(); calM=dt.getMonth();
  renderCal(); renderView();
  wlToast('<b>'+dt.toLocaleDateString(undefined,{weekday:'short',month:'short',day:'numeric'})+'</b>');
}
function shiftDay(delta){
  var base = (sel.length===1) ? parseYMD(sel[0]) : (function(){ var n=new Date(); return new Date(n.getFullYear(),n.getMonth(),n.getDate()); })();
  base.setDate(base.getDate()+delta);
  gotoDay(base);
}
function gotoToday(){ var n=new Date(); gotoDay(new Date(n.getFullYear(),n.getMonth(),n.getDate())); }
function cycleTheme(dir){
  var s=document.getElementById('themeSel'); if(!s) return;
  var n=s.options.length; s.selectedIndex=((s.selectedIndex+(dir||1))%n+n)%n;
  wlSetTheme(s.value); wlToast('Theme: <b>'+s.options[s.selectedIndex].text+'</b>');
}
function showShortcutHelp(){ toggleHelp(); }
function toggleHelp(show){
  var el=document.getElementById('helpbar'); if(!el) return;
  var willShow = (show===undefined) ? !el.classList.contains('show') : !!show;
  el.classList.toggle('show', willShow);
  try{ localStorage.setItem('wl_help', willShow?'1':'0'); }catch(e){}
}
(function(){ try{ if(localStorage.getItem('wl_help')!=='0'){ var el=document.getElementById('helpbar'); if(el){ setTimeout(function(){ el.classList.add('show'); },140); } } }catch(e){} })();
document.addEventListener('keydown', function(e){
  var t=e.target||{}, tag=t.tagName||'';
  var typing=(tag==='INPUT'||tag==='TEXTAREA'||tag==='SELECT'||t.isContentEditable);
  if(e.key==='Escape'){ if(typing && t.id==='q'){ t.blur(); } var hb=document.getElementById('helpbar'); if(hb && hb.classList.contains('show')){ toggleHelp(false); } return; }
  if(e.ctrlKey||e.metaKey||e.altKey) return;
  if(typing) return;
  switch(e.key){
    case '/': e.preventDefault(); focusSearch(); break;
    case '[': e.preventDefault(); shiftDay(-1); break;
    case ']': e.preventDefault(); shiftDay(1); break;
    case 'd': case 'D': e.preventDefault(); gotoToday(); break;
    case '0': e.preventDefault(); clearSel(); wlToast('<b>All dates</b>'); break;
    case 't': e.preventDefault(); cycleTheme(1); break;
    case 'T': e.preventDefault(); cycleTheme(-1); break;
    case 'u': case 'U': e.preventDefault(); toggleGaps(); break;
    case '?': e.preventDefault(); showShortcutHelp(); break;
  }
});
function curSet(){ if(SEARCH){ return SESSIONS.filter(function(s){ return matchQ(s,SEARCH); }); } return sel.length ? SESSIONS.filter(function(s){ return isSel(s.date); }) : SESSIONS.slice(); }
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
  if(noteOnly()){
    document.getElementById('sum').innerHTML="<div class='sum-row'><div class='stat'><div class='big'>"+NOTES.length+"</div><div class='lbl'>Notes</div></div></div><div class='scope'>Showing: <b>notes only</b></div>";
    return;
  }
  var set=curSet().filter(function(s){ return !isMarker(s); }); var total=0; var cat={};
  set.forEach(function(s){ total+=liveMin(s); var c=s.category||'Other'; cat[c]=(cat[c]||0)+liveMin(s); });
  var label = sel.length ? (sel.length===1 ? sel[0] : (sel.length+' dates: '+sel.slice().sort().join(', '))) : 'All time';
  if(SEARCH){ label += ' \u2022 \u201C'+SEARCH+'\u201D'; }
  var comm = dayCommentary(set);
  document.getElementById('sum').innerHTML =
    "<div class='sumgrid'>"+goalRingHtml()+"<div class='summain'>"+
    "<div class='sum-row'><div class='stat'><div class='big' id='totBig'>"+fmtMin(total)+"</div><div class='lbl'>Total time</div></div>"+
    "<div class='stat'><div class='big'>"+set.length+"</div><div class='lbl'>Sessions</div></div>"+
    "<div class='stat'><div class='big'>"+Object.keys(cat).length+"</div><div class='lbl'>Categories</div></div></div>"+
    "<div class='scope'>Showing: <b>"+esc(label)+"</b></div>"+
    (comm ? "<div class='commentary' title='"+esc(comm)+"'><b>Highlights:</b> "+esc(comm)+"</div>" : "")+
    "</div></div>";
}
function renderTable(){
  if(noteOnly()){ document.getElementById('log').innerHTML=''; return; }
  var set=curSet().slice().sort(function(a,b){ if(a.date!==b.date){ return a.date<b.date?1:-1; } if(a.start!==b.start){ return a.start<b.start?-1:1; } return markerRank(a)-markerRank(b); });
  if(!set.length){ document.getElementById('log').innerHTML="<div class='empty'>No sessions"+(SEARCH?" matching \u201C"+esc(SEARCH)+"\u201D":"")+" for this selection.</div>"; return; }
  var groups={}; var order=[];
  set.forEach(function(s){ if(!groups[s.date]){ groups[s.date]=[]; order.push(s.date); } groups[s.date].push(s); });
  var h='';
  order.forEach(function(dt){
    var rows=groups[dt]; var dmin=0; var rcount=0; rows.forEach(function(r){ dmin+=r.min; if(!isMarker(r)) rcount++; });
    var o=new Date(dt+'T00:00:00');
    var dl=WEEKDAYS[(o.getDay()+6)%7]+', '+MONTHS[o.getMonth()]+' '+o.getDate()+', '+o.getFullYear();
    h+="<div class='daygrp'><div class='dayhdr'><span>"+esc(dl)+"</span><span class='daytot'>"+fmtMin(dmin)+" &bull; "+rcount+" session(s)</span></div>";
    h+="<table class='log day'><colgroup><col style='width:9%'><col style='width:10%'><col style='width:6%'><col style='width:9%'><col style='width:11%'><col style='width:22%'><col style='width:28%'><col style='width:5%'></colgroup><thead><tr><th class='center'>#</th><th>Time</th><th>Dur</th><th>Category</th><th>Project</th><th>Item</th><th>Accomplishment</th><th class='center'>Notes</th></tr></thead><tbody>";
    var num=0;
    rows.forEach(function(s,ri){
      if(ri>0){ var p=rows[ri-1]; if(p.end && s.start && hm2min(p.end)>=hm2min(p.start)){ var g=hm2min(s.start)-hm2min(p.end); if(g>=10 && (dt===todayISO() || SHOW_GAPS)){ h+="<tr class='gaprow'><td colspan='8' class='gapcell'><span class='gaplabel'>&#9203; "+fmtMin(g)+" untracked</span><button class='gapfill' onclick=\"openFill('"+dt+"','"+min2hm(hm2min(p.end))+"','"+esc(s.start)+"')\">+ fill</button></td></tr>"; } } }
      if(isMarker(s)){
        var mc=(s.kind==='marker-start')?'mstart':'mend';
        var ic=(s.kind==='marker-start')?'&#9654;':'&#9632;';
        h+="<tr class='markrow "+mc+"'><td colspan='8' class='markcell'><span class='marklabel'>"+ic+" "+esc(s.title)+"</span><span class='marktime'>"+esc(s.start)+"</span></td></tr>";
        return;
      }
      num++;
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
      var edit="<button class='nbtn ebtn' onclick='openEdit("+s._uid+")' title='Edit session'>&#9998;</button>";
      var resume="<button class='nbtn rbtn' onclick='resumeSession("+s._uid+")' title='Resume as a new running task'>&#8635;</button>";
      var proj = s.project ? "<span class='proj'>"+esc(s.project)+"</span>" : "<span class='muted'>&mdash;</span>";
      var durCell = s.end ? ("<td class='nowrap'>"+fmtMin(s.min)+"</td>") : ("<td class='nowrap liveDur' data-uid='"+s._uid+"'>"+fmtMin(liveMin(s))+"</td>");
      h+="<tr class='"+(stopped?'':'unstopped')+"'><td class='center nowrap'><span class='idnum' title='id "+s.id+"'>"+num+"</span>"+edit+resume+"</td><td class='nowrap'>"+time+"</td>"+durCell+"<td><span class='cat'>"+esc(s.category||'Other')+"</span></td><td>"+proj+"</td><td>"+item+"</td><td>"+acc+"</td><td class='center'>"+notes+"</td></tr>";
    });
    h+="</tbody></table></div>";
  });
  document.getElementById('log').innerHTML=h;
}
function renderView(){ renderSummary(); renderTimeline(); renderBreakdown(); renderTable(); renderNotes(); renderRunPill(); }
// ---- Category colors (stable hash) ---------------------------------------
function catColor(name){ name=String(name||'Other'); var h=0; for(var i=0;i<name.length;i++){ h=(h*31+name.charCodeAt(i))%360; } return 'hsl('+h+',60%,58%)'; }
function isMarker(s){ return !!(s && (s.kind==='marker-start' || s.kind==='marker-end')); }
function markerRank(s){ if(s&&s.kind==='marker-start') return -1; if(s&&s.kind==='marker-end') return 1; return 0; }
// ---- Day timeline strip ---------------------------------------------------
function renderTimeline(){
  var el=document.getElementById('timeline'); if(!el) return;
  if(noteOnly() || SEARCH || sel.length!==1){ el.innerHTML=''; return; }
  var ds=sel[0];
  var rows=SESSIONS.filter(function(s){ return s.date===ds; });
  if(!rows.length){ el.innerHTML=''; return; }
  var DAY=1440, segs='', flags='', tot=0;
  rows.forEach(function(s){
    if(isMarker(s)){
      var mx=hm2min(s.start)/DAY*100;
      var mcls=(s.kind==='marker-start')?'start':'end';
      flags+="<div class='tlmark "+mcls+"' style='left:"+mx+"%' title='"+esc(s.title+' \u2014 '+s.start)+"'></div>";
      return;
    }
    var a=hm2min(s.start); var lm=liveMin(s);
    var b=s.end?hm2min(s.end):Math.min(DAY, a+lm);
    if(b<=a){ b=a+1; }
    tot+=lm;
    var col=catColor(s.category);
    var tip=(s.title||'(untitled)')+' \u2014 '+s.start+(s.end?' \u2013 '+s.end:' (open)')+' \u2022 '+fmtMin(lm)+(s.category?' \u2022 '+s.category:'')+(s.project?' \u2022 '+s.project:'');
    segs+="<div class='tlseg"+(s.end?'':' open')+"' data-uid='"+s._uid+"' style='left:"+(a/DAY*100)+"%;width:"+((b-a)/DAY*100)+"%;background:"+col+"' title='"+esc(tip)+"'></div>";
  });
  var ticks='';
  for(var hh=0; hh<=24; hh+=3){ ticks+="<div class='tltick' style='left:"+(hh/24*100)+"%'>"+pad(hh)+"</div>"; }
  var nowMark='';
  if(ds===todayISO()){ var nm=new Date(); nowMark="<div class='tlnow' style='left:"+((nm.getHours()*60+nm.getMinutes())/DAY*100)+"%' title='now'></div>"; }
  el.innerHTML="<div class='tlcard'><div class='tlhead'><span>Day timeline &middot; "+esc(ds)+"</span><span>"+fmtMin(tot)+" tracked</span></div>"
    +"<div class='tlbar'>"+segs+flags+nowMark+"</div><div class='tlticks'>"+ticks+"</div></div>";
}
// ---- Category / project totals -------------------------------------------
function renderBreakdown(){
  var el=document.getElementById('breakdown'); if(!el) return;
  if(noteOnly()){ el.innerHTML=''; return; }
  var set=curSet().filter(function(s){ return !isMarker(s); });
  if(!set.length){ el.innerHTML=''; return; }
  var cat={}, prj={};
  set.forEach(function(s){ var m=liveMin(s); var c=s.category||'Other'; cat[c]=(cat[c]||0)+m; var p=s.project||'\u2014'; prj[p]=(prj[p]||0)+m; });
  function bars(obj,byCat){
    var keys=Object.keys(obj).sort(function(a,b){ return obj[b]-obj[a]; });
    var max=0; keys.forEach(function(k){ if(obj[k]>max) max=obj[k]; });
    var h='';
    keys.forEach(function(k){
      var c=byCat?catColor(k):'var(--accent)';
      var w=max?Math.max(3,obj[k]/max*100):0;
      h+="<div class='bdrow'><span class='bdname'><span class='bddot' style='background:"+c+"'></span><span class='bdlabel'>"+esc(k)+"</span></span><span class='bdtrack'><span class='bdfill' style='width:"+w+"%;background:"+c+"'></span></span><span class='bdtime'>"+fmtMin(obj[k])+"</span></div>";
    });
    return h;
  }
  el.innerHTML="<div class='bdcard'><div class='bdgrid'>"
    +"<div class='bdcol'><h4>By category</h4>"+bars(cat,true)+"</div>"
    +"<div class='bdcol'><h4>By project</h4>"+bars(prj,false)+"</div></div></div>";
}
// ---- Quick resume ---------------------------------------------------------
function resumeSession(uid){
  var s=byId(uid); if(!s) return;
  if(!confirm('Start a new running task from \u201C'+(s.title||'session')+'\u201D now?')) return;
  if(LIVE){
    fetch('/api/start',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({title:s.title,category:s.category,project:s.project,adoId:s.adoId})})
      .then(function(r){ return r.json(); })
      .then(function(j){ if(j&&j.ok){ location.reload(); } else { wlToast('<b>Resume failed:</b> '+((j&&j.error)||'?')); } })
      .catch(function(e){ wlToast('<b>Resume failed:</b> '+e); });
  } else {
    var cmd='pwsh -File '+SCRIPT_DIR+'\\Work.ps1 start '+JSON.stringify(s.title||'');
    if(s.category){ cmd+=' -Category '+JSON.stringify(s.category); }
    if(s.project){ cmd+=' -Project '+JSON.stringify(s.project); }
    if(navigator.clipboard && navigator.clipboard.writeText){ navigator.clipboard.writeText(cmd); wlToast('<b>Command copied</b> \u2014 run it to resume'); }
    else { wlToast(esc(cmd)); }
  }
}
function byId(uid){ for(var i=0;i<SESSIONS.length;i++){ if(SESSIONS[i]._uid===uid) return SESSIONS[i]; } return null; }
// ---- Live timer / running pill -------------------------------------------
function parseStart(s){ return new Date(s.date+'T'+s.start+':00').getTime(); }
function liveSec(s){ return Math.max(0,(Date.now()-parseStart(s))/1000); }
function liveMin(s){ return s.end ? s.min : Math.round(liveSec(s)/60); }
function fmtDur(sec){ sec=Math.max(0,Math.floor(sec)); var h=Math.floor(sec/3600),m=Math.floor((sec%3600)/60),x=sec%60; return (h?h+'h ':'')+((h||m)?pad(m)+'m ':'')+pad(x)+'s'; }
function openSessions(){ return SESSIONS.filter(function(s){ return !s.end; }); }
function renderRunPill(){
  var el=document.getElementById('runPill'); if(!el) return;
  var open=openSessions();
  if(!open.length){ el.classList.remove('show'); el.innerHTML=''; return; }
  var h='';
  open.forEach(function(s){
    h+="<div class='runrow'><span class='rundot'></span><div class='runinfo'><div class='runtitle' title='"+esc(s.title||'')+"'>"+esc(s.title||'(untitled)')+"</div><div class='runtime' data-uid='"+s._uid+"'>"+fmtDur(liveSec(s))+"</div></div><button class='runstop' onclick='stopSession("+s._uid+")'>Stop</button></div>";
  });
  el.innerHTML=h; el.classList.add('show');
}
function stopSession(uid){
  var s=byId(uid); if(!s) return;
  if(!confirm('Stop \u201C'+(s.title||'session')+'\u201D now?')) return;
  if(LIVE){
    fetch('/api/stop',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:s.id})})
      .then(function(r){ return r.json(); })
      .then(function(j){ if(j&&j.ok){ location.reload(); } else { wlToast('<b>Stop failed:</b> '+((j&&j.error)||'?')); } })
      .catch(function(e){ wlToast('<b>Stop failed:</b> '+e); });
  } else {
    var cmd='pwsh -File '+SCRIPT_DIR+'\\Work.ps1 stop -Id '+s.id;
    if(navigator.clipboard && navigator.clipboard.writeText){ navigator.clipboard.writeText(cmd); wlToast('<b>Command copied</b> \u2014 run it to stop #'+s.id); }
    else { wlToast(esc(cmd)); }
  }
}
// ---- Daily goal ring ------------------------------------------------------
function getGoal(){ var g=parseFloat(localStorage.getItem('wl_goal')); return (g>0)?g:6; }
function setGoal(){ var v=prompt('Daily goal (hours):',getGoal()); if(v===null) return; v=parseFloat(v); if(v>0){ try{ localStorage.setItem('wl_goal',v); }catch(e){} renderSummary(); } }
function ringDate(){ return (sel.length===1)?sel[0]:todayISO(); }
function dayTotalLive(ds){ var t=0; SESSIONS.forEach(function(s){ if(s.date===ds) t+=liveMin(s); }); return t; }
function goalRingHtml(){
  var ds=ringDate(), mins=dayTotalLive(ds), goalMin=getGoal()*60;
  var pct=Math.max(0,Math.min(1, goalMin?mins/goalMin:0));
  var r=34, C=2*Math.PI*r;
  var lbl=(ds===todayISO())?'Today':ds;
  return "<div class='goalwrap' onclick='setGoal()' title='Click to set your daily goal'>"
   +"<svg class='goalring' width='86' height='86' viewBox='0 0 86 86'>"
   +"<circle class='gtrack' cx='43' cy='43' r='"+r+"'></circle>"
   +"<circle class='gprog' cx='43' cy='43' r='"+r+"' style='stroke-dasharray:"+C+";stroke-dashoffset:"+(C*(1-pct))+"'></circle>"
   +"<text class='gpct' x='43' y='41'>"+Math.round(pct*100)+"%</text>"
   +"<text class='gsub' x='43' y='55'>"+fmtMin(mins)+"</text></svg>"
   +"<div class='goallbl'>"+esc(lbl)+" &middot; goal "+getGoal()+"h</div></div>";
}
function updateGoalRing(){
  var prog=document.querySelector('.gprog'); if(!prog) return;
  var ds=ringDate(), mins=dayTotalLive(ds), goalMin=getGoal()*60;
  var pct=Math.max(0,Math.min(1, goalMin?mins/goalMin:0));
  var r=34, C=2*Math.PI*r; prog.style.strokeDashoffset=C*(1-pct);
  var pe=document.querySelector('.gpct'); if(pe) pe.textContent=Math.round(pct*100)+'%';
  var se=document.querySelector('.gsub'); if(se) se.textContent=fmtMin(mins);
}
// ---- Gap detector helpers -------------------------------------------------
function hm2min(hm){ var p=String(hm).split(':'); return (+p[0])*60+(+p[1]); }
function min2hm(m){ return pad(Math.floor(m/60))+':'+pad(m%60); }
function openFill(date,startHM,endHM){ openNew(); var a=document.getElementById('eStart'); var b=document.getElementById('eEnd'); if(a) a.value=dtLocal(date,startHM); if(b) b.value=dtLocal(date,endHM); }
function syncGapBtn(){ var b=document.getElementById('gapToggle'); if(!b) return; b.textContent=SHOW_GAPS?'Hide untracked':'Show untracked'; }
function toggleGaps(){ SHOW_GAPS=!SHOW_GAPS; try{ localStorage.setItem('wl_gaps',SHOW_GAPS?'1':'0'); }catch(e){} syncGapBtn(); renderTable(); wlToast(SHOW_GAPS?'<b>Showing</b> untracked time for all days':'<b>Untracked</b> shown for today only'); }
// ---- Per-second live tick -------------------------------------------------
function updateLive(){
  openSessions().forEach(function(s){
    var sec=liveSec(s);
    var rt=document.querySelector(".runtime[data-uid='"+s._uid+"']"); if(rt) rt.textContent=fmtDur(sec);
    var dc=document.querySelector(".liveDur[data-uid='"+s._uid+"']"); if(dc) dc.textContent=fmtMin(Math.round(sec/60));
    var sg=document.querySelector(".tlseg[data-uid='"+s._uid+"']");
    if(sg){ var a=hm2min(s.start); var b=Math.min(1440,a+Math.round(sec/60)); sg.style.width=Math.max(0.2,(b-a)/1440*100)+'%'; }
  });
  var nowEl=document.querySelector('.tlnow'); if(nowEl){ var nm=new Date(); nowEl.style.left=((nm.getHours()*60+nm.getMinutes())/1440*100)+'%'; }
  var tb=document.getElementById('totBig'); if(tb){ var set=curSet(), total=0; set.forEach(function(s){ total+=liveMin(s); }); tb.textContent=fmtMin(total); }
  updateGoalRing();
}
setInterval(updateLive,1000);
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
document.addEventListener('keydown', function(e){ if(e.key==='Escape'){ closeNotes(); closeEdit(); closeNote(); } });
// ---- Inline editing -------------------------------------------------------
var LIVE = (location.protocol==='http:' || location.protocol==='https:');
var EDIT_UID=null;
var EDIT_MODE='edit';
function nowLocal(){ var d=new Date(); return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate())+'T'+pad(d.getHours())+':'+pad(d.getMinutes()); }
function uniqVals(key){
  var seen={}, out=[];
  SESSIONS.forEach(function(s){ var v=String(s[key]==null?'':s[key]).trim(); if(v && !seen[v.toLowerCase()]){ seen[v.toLowerCase()]=1; out.push(v); } });
  out.sort(function(a,b){ return a.toLowerCase()<b.toLowerCase()?-1:1; });
  return out;
}
function fillSelect(selId, vals, cur){
  var sel=document.getElementById(selId); sel.innerHTML='';
  if(cur && vals.indexOf(cur)===-1){ vals=[cur].concat(vals); }
  vals.forEach(function(v){ var o=document.createElement('option'); o.value=v; o.textContent=v; sel.appendChild(o); });
  var on=document.createElement('option'); on.value='__new__'; on.textContent='+ New\u2026'; sel.appendChild(on);
  sel.value = cur ? cur : (vals.length ? vals[0] : '__new__');
}
function onSelChange(pfx){
  var sel=document.getElementById(pfx+'Sel'), nw=document.getElementById(pfx+'New');
  if(sel.value==='__new__'){ nw.style.display=''; nw.focus(); } else { nw.style.display='none'; }
}
function selVal(pfx){
  var sel=document.getElementById(pfx+'Sel');
  if(sel.value==='__new__'){ return document.getElementById(pfx+'New').value.trim(); }
  return sel.value;
}
function dtLocal(date,hm){ return (date&&hm) ? date+'T'+hm : ''; }
function dtStamp(v){ return v ? v.replace('T',' ')+':00' : ''; }
function openEdit(uid){
  var s=byId(uid); if(!s) return; EDIT_UID=uid; EDIT_MODE='edit';
  document.getElementById('eHdr').textContent='Edit session #'+s.id;
  document.getElementById('eStart').value = dtLocal(s.date, s.start);
  var endDate=s.date;
  if(s.end && s.start && s.end < s.start){ var d=new Date(s.date+'T00:00:00'); d.setDate(d.getDate()+1); endDate=ymd(d.getFullYear(),d.getMonth(),d.getDate()); }
  document.getElementById('eEnd').value = s.end ? dtLocal(endDate, s.end) : '';
  document.getElementById('eCatNew').value=''; document.getElementById('eProjNew').value='';
  fillSelect('eCatSel', uniqVals('category'), s.category||'');
  fillSelect('eProjSel', uniqVals('project'), s.project||'');
  onSelChange('eCat'); onSelChange('eProj');
  document.getElementById('eItem').value = s.title||'';
  document.getElementById('eAcc').value = s.accomplishment||'';
  setEMsg('', '');
  document.getElementById('emodal').classList.add('show');
}
function openNew(){
  EDIT_UID=null; EDIT_MODE='new';
  document.getElementById('eHdr').textContent='New session';
  document.getElementById('eStart').value = nowLocal();
  document.getElementById('eEnd').value = '';
  document.getElementById('eCatNew').value=''; document.getElementById('eProjNew').value='';
  fillSelect('eCatSel', uniqVals('category'), '');
  fillSelect('eProjSel', uniqVals('project'), '');
  onSelChange('eCat'); onSelChange('eProj');
  document.getElementById('eItem').value = '';
  document.getElementById('eAcc').value = '';
  setEMsg('', '');
  document.getElementById('emodal').classList.add('show');
  document.getElementById('eItem').focus();
}
function closeEdit(){ var m=document.getElementById('emodal'); if(m) m.classList.remove('show'); EDIT_UID=null; }
function setEMsg(t, cls){ var m=document.getElementById('eMsg'); if(!m) return; m.className='emsg'+(cls?' '+cls:''); m.textContent=t; }
function qarg(v){ return '"'+String(v==null?'':v).replace(/"/g,'""')+'"'; }
function buildEditCmd(p){
  var parts;
  if(EDIT_MODE==='new'){
    parts=['pwsh','-File',qarg(SCRIPT_DIR+'\\Work.ps1'),'add','-Profile',qarg(PROFILE)];
  } else {
    parts=['pwsh','-File',qarg(SCRIPT_DIR+'\\Work.ps1'),'edit','-Id',p.id,'-Profile',qarg(PROFILE)];
  }
  parts.push('-Start',qarg(dtStamp(p.start)));
  if(p.end){ parts.push('-End',qarg(dtStamp(p.end))); }
  parts.push('-Category',qarg(p.category));
  parts.push('-Project',qarg(p.project));
  parts.push('-Title',qarg(p.title));
  parts.push('-Accomplishment',qarg(p.accomplishment));
  return parts.join(' ');
}
function showEditCmd(cmd){
  var m=document.getElementById('eMsg'); m.className='emsg';
  m.innerHTML="Run this in your terminal to apply (auto-rebuilds the dashboard):<br><textarea class='ecmd' readonly rows='3'></textarea>";
  var ta=m.querySelector('textarea'); ta.value=cmd; ta.focus(); ta.select();
}
function saveEdit(){
  var newMode=(EDIT_MODE==='new');
  var s = newMode ? null : byId(EDIT_UID);
  if(!newMode && !s) return;
  var payload={ id: newMode ? null : s.id,
    start: document.getElementById('eStart').value,
    end: document.getElementById('eEnd').value,
    category: selVal('eCat'),
    project: selVal('eProj'),
    title: document.getElementById('eItem').value,
    accomplishment: document.getElementById('eAcc').value };
  if(!payload.start){ setEMsg('Start time is required.','err'); return; }
  if(newMode && !payload.title.trim()){ setEMsg('Item (title) is required.','err'); return; }
  var endpoint = newMode ? '/api/new' : '/api/edit';
  if(LIVE){
    setEMsg('Saving\u2026','');
    fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)})
      .then(function(r){ return r.json(); })
      .then(function(j){ if(j && j.ok){ location.reload(); } else { setEMsg('Error: '+((j&&j.error)||'save failed'),'err'); } })
      .catch(function(e){ setEMsg('Error: '+e,'err'); });
  } else {
    var cmd=buildEditCmd(payload);
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(cmd).then(
        function(){ setEMsg('Command copied to clipboard \u2014 paste it into your terminal to apply.','ok'); setTimeout(closeEdit, 3000); },
        function(){ showEditCmd(cmd); });
    } else { showEditCmd(cmd); }
  }
}
// ---- Notes (date-bound) ---------------------------------------------------
var NOTE_ID=null;
var NOTE_DATE=null;
function noteById(id){ for(var i=0;i<NOTES.length;i++){ if(NOTES[i].id===id) return NOTES[i]; } return null; }
function todayISO(){ var d=new Date(); return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate()); }
function uniqNoteCats(){
  var seen={}, out=[];
  function add(v){ v=String(v==null?'':v).trim(); if(v && !seen[v.toLowerCase()]){ seen[v.toLowerCase()]=1; out.push(v); } }
  NOTES.forEach(function(n){ add(n.category); });
  SESSIONS.forEach(function(s){ add(s.category); });
  out.sort(function(a,b){ return a.toLowerCase()<b.toLowerCase()?-1:1; });
  return out;
}
function noteMatch(n,q){ return [n.text,n.category,(n.tags||[]).join(' ')].join('\n').toLowerCase().indexOf(q)!==-1; }
function renderNotes(){
  var el=document.getElementById('noteList'); if(!el) return;
  if(!NOTES.length){ el.innerHTML=''; return; }
  var set=NOTES.slice();
  if(noteOnly()){ /* show all notes */ }
  else if(SEARCH){ set=set.filter(function(n){ return noteMatch(n,SEARCH); }); }
  else if(sel.length){ set=set.filter(function(n){ return isSel(n.date); }); }
  if(!set.length){ el.innerHTML=''; return; }
  set.sort(function(a,b){ if(a.date!==b.date){ return a.date<b.date?1:-1; } return b.id-a.id; });
  var h="<div class='dayhdr' style='margin:30px 0 12px'><span style='font-size:15px;font-weight:700;color:var(--accent)'>Notes</span></div>";
  set.forEach(function(n){
    var cat=n.category?"<span class='cat'>"+esc(n.category)+"</span> ":'';
    var tags=''; (n.tags||[]).forEach(function(t){ if(t) tags+="<span class='chip'>"+esc(t)+"</span>"; });
    h+="<div class='card notecard' style='margin-bottom:10px'>";
    h+="<div style='display:flex;justify-content:space-between;gap:12px;align-items:baseline'><div>"+cat+"<span class='idnum' title='note id "+n.id+"'>#"+n.id+"</span></div><button class='nbtn ebtn' onclick='openNoteEdit("+n.id+")' title='Edit note'>&#9998;</button></div>";
    h+="<div style='margin-top:6px'>"+mdNote(n.text)+"</div>";
    if(tags){ h+="<div style='margin-top:8px'>"+tags+"</div>"; }
    h+="</div>";
  });
  el.innerHTML=h;
}
function setNMsg(t,cls){ var m=document.getElementById('nMsg'); if(!m) return; m.className='emsg'+(cls?' '+cls:''); m.textContent=t; }
function openNoteNew(){
  NOTE_ID=null;
  NOTE_DATE=(sel.length===1?sel[0]:todayISO());
  document.getElementById('nHdr').textContent='New note';
  document.getElementById('nCatNew').value='';
  fillSelect('nCatSel', uniqNoteCats(), '');
  onSelChange('nCat');
  document.getElementById('nTags').value='';
  document.getElementById('nText').value='';
  document.getElementById('nDel').style.display='none';
  setNMsg('','');
  document.getElementById('nmodal').classList.add('show');
  document.getElementById('nText').focus();
}
function openNoteEdit(id){
  var n=noteById(id); if(!n) return; NOTE_ID=id; NOTE_DATE=n.date;
  document.getElementById('nHdr').textContent='Edit note #'+id;
  document.getElementById('nCatNew').value='';
  fillSelect('nCatSel', uniqNoteCats(), n.category||'');
  onSelChange('nCat');
  document.getElementById('nTags').value=(n.tags||[]).join(', ');
  document.getElementById('nText').value=n.text||'';
  document.getElementById('nDel').style.display='';
  setNMsg('','');
  document.getElementById('nmodal').classList.add('show');
  document.getElementById('nText').focus();
}
function closeNote(){ var m=document.getElementById('nmodal'); if(m) m.classList.remove('show'); NOTE_ID=null; }
function noteCmd(action,p){
  var parts=['pwsh','-File',qarg(SCRIPT_DIR+'\\Work.ps1'),'note','-Profile',qarg(PROFILE)];
  if(action!=='add'){ parts.push('-Id',p.id); }
  if(action==='remove'){ parts.push('-Remove'); return parts.join(' '); }
  parts.push('-Text',qarg(p.text));
  if(p.date){ parts.push('-Date',qarg(p.date)); }
  if(p.category){ parts.push('-Category',qarg(p.category)); }
  if(p.tags){ parts.push('-Tags',qarg(p.tags)); }
  return parts.join(' ');
}
function showNoteCmd(cmd){
  var m=document.getElementById('nMsg'); m.className='emsg';
  m.innerHTML="Run this in your terminal to apply:<br><textarea class='ecmd' readonly rows='3'></textarea>";
  var ta=m.querySelector('textarea'); ta.value=cmd; ta.focus(); ta.select();
}
function copyOrShowNote(cmd){
  if(navigator.clipboard && navigator.clipboard.writeText){
    navigator.clipboard.writeText(cmd).then(
      function(){ setNMsg('Command copied \u2014 paste into your terminal to apply.','ok'); setTimeout(closeNote,3000); },
      function(){ showNoteCmd(cmd); });
  } else { showNoteCmd(cmd); }
}
function saveNote(){
  var payload={ id: NOTE_ID,
    date: NOTE_DATE,
    category: selVal('nCat'),
    tags: document.getElementById('nTags').value,
    text: document.getElementById('nText').value };
  if(!payload.text.trim()){ setNMsg('Note text is required.','err'); return; }
  if(LIVE){
    setNMsg('Saving\u2026','');
    fetch('/api/note',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)})
      .then(function(r){ return r.json(); })
      .then(function(j){ if(j && j.ok){ location.reload(); } else { setNMsg('Error: '+((j&&j.error)||'save failed'),'err'); } })
      .catch(function(e){ setNMsg('Error: '+e,'err'); });
  } else {
    copyOrShowNote(noteCmd(NOTE_ID==null?'add':'edit', payload));
  }
}
function deleteNote(){
  if(NOTE_ID==null) return;
  if(!confirm('Delete note #'+NOTE_ID+'?')) return;
  if(LIVE){
    setNMsg('Deleting\u2026','');
    fetch('/api/note-delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:NOTE_ID})})
      .then(function(r){ return r.json(); })
      .then(function(j){ if(j && j.ok){ location.reload(); } else { setNMsg('Error: '+((j&&j.error)||'delete failed'),'err'); } })
      .catch(function(e){ setNMsg('Error: '+e,'err'); });
  } else {
    copyOrShowNote(noteCmd('remove',{id:NOTE_ID}));
  }
}
(function(){
  var n=new Date(); var today=ymd(n.getFullYear(), n.getMonth(), n.getDate());
  calY=n.getFullYear(); calM=n.getMonth();
  sel=[today]; syncGapBtn(); renderCal(); renderView();
})();
'@

    $html = @"
<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'><title>Work Log</title>
<script>(function(){try{var t=localStorage.getItem('wl_theme');if(t)document.documentElement.setAttribute('data-theme',t);}catch(e){}})();</script>
<style>$script:BaseCss
@media(max-width:1600px){.page{padding-left:5%;padding-right:5%;}}
.searchbar{display:flex;gap:.5rem;align-items:center;margin:0 0 .75rem 0;}
.searchbar input{flex:1;padding:.55rem .8rem;border-radius:0;border:1px solid var(--bd,#d0d7de);background:var(--card,#fff);color:inherit;font-size:.95rem;outline:none;}
.searchwrap{position:relative;flex:1;display:flex;}
.searchwrap input{padding-right:2.1rem;}
.searchbar input[type=search]::-webkit-search-cancel-button{-webkit-appearance:none;appearance:none;}
.qclear{position:absolute;right:.5rem;top:50%;transform:translateY(-50%);color:var(--muted);font-size:1.2rem;line-height:1;cursor:pointer;padding:0 .3rem;display:none;user-select:none;transition:color .15s;}
.qclear:hover{color:var(--text);}
.searchwrap input:not(:placeholder-shown) ~ .qclear{display:block;}
.searchbar input:focus{border-color:var(--accent);box-shadow:0 0 0 2px var(--a22);}
.searchbar button{padding:.55rem 1rem;font-size:.9rem;line-height:1;color:var(--muted);transition:background .15s,border-color .15s,color .15s;}
.searchbar button:hover{background:var(--card2);border-color:var(--accent);color:var(--text);}
.nh{font-weight:700;margin:.5rem 0 .25rem;}
.np{margin:.25rem 0;}
.nlist{margin:.25rem 0 .25rem 1.1rem;padding:0;}
.nlist li{margin:.15rem 0;}
.modal-body code{background:var(--card2,rgba(127,127,127,.18));padding:.05rem .35rem;border-radius:3px;font-size:.86em;}
.ebtn{background:var(--green-soft);color:var(--green);border:1px solid var(--green-line);margin-left:16px;}
.ebtn:hover{background:color-mix(in srgb,var(--green) 30%,transparent);}
.eform{display:grid;grid-template-columns:1fr 1fr;gap:12px 16px;}
.eform label{display:flex;flex-direction:column;gap:4px;font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted);font-weight:600;}
.eform label.wide{grid-column:1 / -1;}
.eform input,.eform select,.eform textarea{background:var(--card2);border:1px solid var(--border);color:var(--text);padding:.5rem .6rem;font-size:13.5px;font-family:inherit;border-radius:0;outline:none;}
.eform input[type=datetime-local]{color-scheme:var(--scheme);}
.eform input:focus,.eform select:focus,.eform textarea:focus{border-color:var(--accent);box-shadow:0 0 0 2px var(--a22);}
.eform .enew{margin-top:6px;}
.eform textarea{resize:vertical;}
.eactions{display:flex;gap:10px;margin-top:18px;justify-content:flex-end;}
.pill.save{background:var(--accent);color:var(--on-accent);border-color:var(--accent);font-weight:700;}
.pill.save:hover{background:var(--accent-hover);}
.pill.active{background:var(--accent);color:var(--on-accent);border-color:var(--accent);font-weight:700;}
.emsg{margin-top:12px;font-size:12.5px;min-height:1em;}
.emsg.ok{color:var(--green);}
.emsg.err{color:var(--red);}
.ecmd{width:100%;margin-top:6px;background:var(--card2);border:1px solid var(--border);color:var(--text);font-family:var(--mono);font-size:12px;padding:8px;border-radius:0;}
.newbtn,.searchbar button.newbtn{background:transparent;color:var(--accent);border:1px solid var(--accent);font-weight:700;}
.newbtn:hover,.searchbar button.newbtn:hover{background:var(--a10);border-color:var(--accent);color:var(--accent);}
.themewrap{display:flex;align-items:center;gap:7px;}
.themewrap .tlbl{font-size:10.5px;text-transform:uppercase;letter-spacing:.6px;color:var(--muted);font-weight:600;}
.themesel{background:var(--card2);border:1px solid var(--border);color:var(--text);font-family:inherit;font-size:12.5px;padding:6px 10px;border-radius:0;cursor:pointer;outline:none;}
.themesel:focus{border-color:var(--accent);box-shadow:0 0 0 2px var(--a22);}
kbd{font-family:var(--mono);font-size:11px;background:var(--card2);border:1px solid var(--border);border-bottom-width:2px;padding:1px 6px;border-radius:3px;color:var(--text);white-space:nowrap;}
.shorthint{font-size:11.5px;color:var(--muted);margin:-2px 0 12px;}
.shorthint kbd{margin:0 2px;}
.wltoast{position:fixed;left:50%;bottom:26px;transform:translateX(-50%) translateY(8px);background:var(--card2);border:1px solid var(--border);border-left:3px solid var(--accent);color:var(--text);padding:8px 16px;font-size:13px;border-radius:0;opacity:0;pointer-events:none;transition:opacity .18s,transform .18s;z-index:80;box-shadow:0 8px 28px rgba(0,0,0,.45);-webkit-backdrop-filter:blur(4px);backdrop-filter:blur(4px);}
.wltoast.show{opacity:1;transform:translateX(-50%) translateY(0);}
.wltoast b{color:var(--accent);font-weight:700;}
.wltoast kbd{font-size:10.5px;}
.helpbar{position:fixed;top:0;left:0;right:0;z-index:100;display:flex;align-items:center;justify-content:center;gap:18px;flex-wrap:wrap;background:linear-gradient(135deg,var(--a22),transparent 60%),var(--card2);border-bottom:2px solid var(--accent);padding:12px 20px;font-size:12.5px;color:var(--muted);box-shadow:0 10px 34px rgba(0,0,0,.45);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);transform:translateY(-100%);transition:transform .32s cubic-bezier(.2,.85,.25,1);}
.helpbar.show{transform:translateY(0);}
.helpbar .htitle{font-weight:700;color:var(--text);text-transform:uppercase;letter-spacing:.7px;font-size:11px;display:flex;align-items:center;gap:7px;white-space:nowrap;}
.helpbar .htitle .hdot{width:7px;height:7px;border-radius:50%;background:var(--accent);box-shadow:0 0 8px var(--accent);}
.helpbar .hitems{display:flex;flex-wrap:wrap;gap:6px 18px;align-items:center;justify-content:center;}
.helpbar .hitems span{display:inline-flex;align-items:center;gap:5px;white-space:nowrap;}
.helpbar .hx{margin-left:auto;background:transparent;border:none;color:var(--muted);cursor:pointer;font-size:20px;line-height:1;padding:0 4px;}
.helpbar .hx:hover{color:var(--accent);}
.sumgrid{display:flex;gap:18px;align-items:flex-start;}
.summain{flex:1;min-width:0;}
.goalwrap{display:flex;flex-direction:column;align-items:center;gap:6px;cursor:pointer;flex:none;-webkit-user-select:none;user-select:none;}
.goalring{display:block;}
.goalring .gtrack{fill:none;stroke:var(--border);stroke-width:8;}
.goalring .gprog{fill:none;stroke:var(--accent);stroke-width:8;stroke-linecap:round;transform:rotate(-90deg);transform-origin:43px 43px;transition:stroke-dashoffset .6s cubic-bezier(.2,.8,.2,1);filter:drop-shadow(0 0 4px var(--a33));}
.goalring .gpct{fill:var(--text);font-size:17px;font-weight:700;text-anchor:middle;font-variant-numeric:tabular-nums;}
.goalring .gsub{fill:var(--muted);font-size:10px;text-anchor:middle;}
.goalwrap:hover .gprog{filter:drop-shadow(0 0 7px var(--accent));}
.goallbl{font-size:10.5px;color:var(--muted);text-transform:uppercase;letter-spacing:.4px;white-space:nowrap;}
.runpill{position:fixed;right:22px;bottom:22px;z-index:85;display:none;flex-direction:column;gap:8px;}
.runpill.show{display:flex;}
.runrow{display:flex;align-items:center;gap:11px;background:var(--card2);border:1px solid var(--border);border-left:3px solid var(--green);padding:9px 12px;box-shadow:0 10px 30px rgba(0,0,0,.45);min-width:240px;-webkit-backdrop-filter:blur(5px);backdrop-filter:blur(5px);animation:wlFade .35s ease both;}
.runrow .rundot{width:9px;height:9px;border-radius:50%;background:var(--green);animation:wlPulse 1.6s infinite;flex:none;}
.runinfo{flex:1;min-width:0;}
.runtitle{font-size:12.5px;font-weight:600;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:175px;}
.runtime{font-family:var(--mono);font-size:13px;color:var(--green);font-variant-numeric:tabular-nums;margin-top:1px;}
.runstop{background:var(--red-soft);color:var(--red);border:1px solid color-mix(in srgb,var(--red) 40%,transparent);padding:5px 13px;font-size:12px;font-weight:700;cursor:pointer;border-radius:0;flex:none;}
.runstop:hover{background:color-mix(in srgb,var(--red) 26%,transparent);}
tr.gaprow td{background:repeating-linear-gradient(45deg,transparent,transparent 7px,var(--a06) 7px,var(--a06) 14px);}
.gapcell{font-size:11.5px;color:var(--muted);padding:5px 14px !important;}
.gaplabel{color:var(--amber);font-weight:600;letter-spacing:.2px;}
.gapfill{margin-left:12px;background:transparent;border:1px solid var(--accent);color:var(--accent);font-size:11px;font-weight:700;padding:2px 9px;cursor:pointer;border-radius:0;}
.gapfill:hover{background:var(--a10);}
tr.markrow td{padding:5px 14px !important;}
.markrow.mstart td{background:linear-gradient(90deg,var(--green-soft),transparent 72%);border-left:3px solid var(--green);}
.markrow.mend td{background:linear-gradient(90deg,var(--red-soft),transparent 72%);border-left:3px solid var(--red);}
.marklabel{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.7px;}
.markrow.mstart .marklabel{color:var(--green);}
.markrow.mend .marklabel{color:var(--red);}
.marktime{float:right;font-family:var(--mono);font-size:11.5px;color:var(--muted);}
.tlmark{position:absolute;top:0;bottom:0;width:2px;background:var(--green);z-index:4;cursor:help;}
.tlmark.end{background:var(--red);}
.tlmark::after{content:'';position:absolute;top:0;left:-2px;width:6px;height:6px;background:inherit;}
.rbtn{background:var(--a10);color:var(--accent);border:1px solid color-mix(in srgb,var(--accent) 35%,transparent);margin-left:6px;}
.rbtn:hover{background:var(--a22);border-color:var(--accent);}
.tlcard,.bdcard{margin:0 0 14px;background:var(--card);border:1px solid var(--border);padding:12px 16px 10px;animation:wlFade .35s ease both;}
.tlhead{display:flex;justify-content:space-between;align-items:center;font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted);font-weight:700;margin-bottom:9px;}
.tlbar{position:relative;height:30px;background:var(--card2);border:1px solid var(--border);overflow:hidden;}
.tlseg{position:absolute;top:2px;bottom:2px;border-radius:2px;opacity:.92;transition:opacity .15s,transform .12s,box-shadow .15s;min-width:2px;}
.tlseg:hover{opacity:1;transform:scaleY(1.12);box-shadow:0 0 0 1px var(--text);z-index:2;cursor:default;}
.tlseg.open{outline:1px dashed var(--green);outline-offset:-1px;}
.tlnow{position:absolute;top:-3px;bottom:-3px;width:2px;background:var(--red);box-shadow:0 0 6px var(--red);z-index:3;pointer-events:none;}
.tlticks{position:relative;height:14px;margin-top:3px;}
.tltick{position:absolute;font-size:9px;color:var(--muted);transform:translateX(-50%);font-variant-numeric:tabular-nums;}
.tltick::before{content:'';position:absolute;top:-4px;left:50%;width:1px;height:3px;background:var(--border);}
.bdcard{max-width:760px;}
.bdgrid{display:grid;grid-template-columns:1fr 1fr;gap:6px 36px;}
.bdcol h4{margin:0 0 8px;font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted);font-weight:700;}
.bdrow{display:grid;grid-template-columns:110px 120px 1fr;gap:11px;align-items:center;margin:6px 0;font-size:12.5px;}
.bdname{display:flex;align-items:center;gap:7px;min-width:0;}
.bddot{width:9px;height:9px;border-radius:2px;flex:none;}
.bdlabel{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.bdtime{font-variant-numeric:tabular-nums;color:var(--muted);font-size:11.5px;white-space:nowrap;text-align:right;}
.bdtrack{height:6px;background:var(--card2);overflow:hidden;border-radius:3px;}
.bdfill{display:block;height:100%;border-radius:3px;transition:width .4s cubic-bezier(.2,.8,.2,1);}
@media(max-width:680px){.bdgrid{grid-template-columns:1fr;gap:2px 0;}}
</style></head><body>
<div class='page'>
<header class='rpt-hero'><div><h1>Work Log</h1><div class='meta'>$meta</div></div>
<div class='themewrap'><span class='tlbl'>Theme</span><select id='themeSel' class='themesel' onchange='wlSetTheme(this.value)'>
<option value=''>Midnight Blue</option><option value='tokyo'>Tokyo Night</option><option value='nord'>Nord</option><option value='dracula'>Dracula</option><option value='rose'>Ros&eacute; Pine</option><option value='paper'>Paper (Light)</option>
</select></div></header>
<div id='helpbar' class='helpbar'>
  <span class='htitle'><span class='hdot'></span>Keyboard shortcuts</span>
  <span class='hitems'>
    <span><kbd>/</kbd> search</span><span><kbd>[</kbd> <kbd>]</kbd> prev/next day</span><span><kbd>d</kbd> today</span><span><kbd>0</kbd> all dates</span><span><kbd>u</kbd> untracked</span><span><kbd>t</kbd> <kbd>T</kbd> cycle theme</span><span><kbd>?</kbd> toggle help</span><span><kbd>Esc</kbd> close</span>
  </span>
  <button class='hx' onclick='toggleHelp(false)' title='Hide (press ? to reopen)'>&times;</button>
</div>
<script>
function wlSetTheme(t){var d=document.documentElement;if(t){d.setAttribute('data-theme',t);}else{d.removeAttribute('data-theme');}try{localStorage.setItem('wl_theme',t);}catch(e){}}
(function(){var t='';try{t=localStorage.getItem('wl_theme')||'';}catch(e){}var s=document.getElementById('themeSel');if(s)s.value=t;})();
</script>
<div class='top'>
  <div class='card'><div id='cal'></div></div>
  <div class='card'><div id='sum'></div></div>
</div>
<div id='timeline'></div>
<div id='breakdown'></div>
<div class='searchbar'>
  <span class='searchwrap'>
    <input id='q' type='search' placeholder='Search title, notes, project, status&hellip; (tokens: is_open, is_note)' oninput='onSearch(this.value)' autocomplete='off'>
    <span id='qx' class='qclear' onclick='clearSearch()' role='button' aria-label='Clear search' title='Clear'>&times;</span>
  </span>
  <button class='pill newbtn' onclick='openNew()'>+ New item</button>
  <button class='pill newbtn' onclick='openNoteNew()'>+ Add note</button>
  <button id='gapToggle' class='pill newbtn' onclick='toggleGaps()'>Show untracked</button>
</div>
<div id='log'></div>
<div id='noteList'></div>
</div>
<div id='wlToast' class='wltoast'></div>
<div id='runPill' class='runpill'></div>
<div id='modal' class='modal' onclick='if(event.target===this)closeNotes()'>
  <div class='modal-box'>
    <div class='modal-head'><span id='mTitle'></span><button class='cbtn' onclick='closeNotes()'>&times;</button></div>
    <div id='mBody' class='modal-body'></div>
  </div>
</div>
<div id='emodal' class='modal' onclick='if(event.target===this)closeEdit()'>
  <div class='modal-box'>
    <div class='modal-head'><span id='eHdr'>Edit session</span><button class='cbtn' onclick='closeEdit()'>&times;</button></div>
    <div class='modal-body'>
      <div class='eform'>
        <label>Start time<input type='datetime-local' id='eStart'></label>
        <label>End time<input type='datetime-local' id='eEnd'></label>
        <label>Category
          <select id='eCatSel' onchange="onSelChange('eCat')"></select>
          <input type='text' id='eCatNew' class='enew' placeholder='New category&hellip;' style='display:none'>
        </label>
        <label>Project
          <select id='eProjSel' onchange="onSelChange('eProj')"></select>
          <input type='text' id='eProjNew' class='enew' placeholder='New project&hellip;' style='display:none'>
        </label>
        <label class='wide'>Item<input type='text' id='eItem'></label>
        <label class='wide'>Accomplishment<textarea id='eAcc' rows='3'></textarea></label>
      </div>
      <div id='eMsg' class='emsg'></div>
      <div class='eactions'>
        <button class='pill save' onclick='saveEdit()'>Save</button>
        <button class='pill' onclick='closeEdit()'>Cancel</button>
      </div>
    </div>
  </div>
</div>
<div id='nmodal' class='modal' onclick='if(event.target===this)closeNote()'>
  <div class='modal-box'>
    <div class='modal-head'><span id='nHdr'>New note</span><button class='cbtn' onclick='closeNote()'>&times;</button></div>
    <div class='modal-body'>
      <div class='eform'>
        <label>Category
          <select id='nCatSel' onchange="onSelChange('nCat')"></select>
          <input type='text' id='nCatNew' class='enew' placeholder='New category&hellip;' style='display:none'>
        </label>
        <label class='wide'>Tags (comma-separated)<input type='text' id='nTags' placeholder='e.g. followup, bedrock'></label>
        <label class='wide'>Note<textarea id='nText' rows='4'></textarea></label>
      </div>
      <div id='nMsg' class='emsg'></div>
      <div class='eactions'>
        <button class='pill save' onclick='saveNote()'>Save</button>
        <button id='nDel' class='pill' style='display:none;border-color:var(--red);color:var(--red)' onclick='deleteNote()'>Delete</button>
        <button class='pill' onclick='closeNote()'>Cancel</button>
      </div>
    </div>
  </div>
</div>
<script>
var SESSIONS = $json;
var COMMENTARY = $commentaryJson;
var NOTES = $notesJson;
var ADO_BASE = "$($script:Org)";
var SCRIPT_DIR = $($script:ScriptDir | ConvertTo-Json);
var PROFILE = $($script:Profile | ConvertTo-Json);
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

# ---- Public: Live-edit server ---------------------------------------------
# Serves the dashboard over http://localhost:<port> so the in-page Edit button
# can POST changes back and persist them via Edit-Work (single-user, local-only).
function Write-WorkServerJson($res, [int]$code, $obj) {
    $res.StatusCode = $code
    $res.ContentType = 'application/json'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Invoke-WorkEditRequest {
    param($ctx)
    $req = $ctx.Request
    $res = $ctx.Response
    try {
        $path = $req.Url.AbsolutePath
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/edit') {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $d = $body | ConvertFrom-Json
            $names = $d.PSObject.Properties.Name
            $p = @{ Id = [int]$d.id }
            if (($names -contains 'start')          -and $d.start) { $p.Start = [datetime]$d.start }
            if (($names -contains 'end')            -and $d.end)   { $p.End   = [datetime]$d.end }
            if  ($names -contains 'category')        { $p.Category       = [string]$d.category }
            if  ($names -contains 'project')         { $p.Project        = [string]$d.project }
            if  ($names -contains 'title')           { $p.Title          = [string]$d.title }
            if  ($names -contains 'accomplishment')  { $p.Accomplishment  = [string]$d.accomplishment }
            $script:SuppressDashboard = $false
            Edit-Work @p | Out-Null   # persists state and rebuilds the dashboard
            Write-Host ("~ Live edit applied to #{0}" -f $p.Id)
            Write-WorkServerJson $res 200 @{ ok = $true }
            return
        }
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/stop') {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $d = $body | ConvertFrom-Json
            $sp = @{ Id = [int]$d.id; At = (Get-Date) }
            if ($d.PSObject.Properties.Name -contains 'accomplishment' -and $d.accomplishment) { $sp.Accomplishment = [string]$d.accomplishment }
            $script:SuppressDashboard = $false
            Stop-Work @sp | Out-Null   # sets end=now, status=done, persists + rebuilds
            Write-Host ("# Live stop applied to #{0}" -f $sp.Id)
            Write-WorkServerJson $res 200 @{ ok = $true }
            return
        }
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/start') {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $d = $body | ConvertFrom-Json
            $names = $d.PSObject.Properties.Name
            $p = @{ Title = [string]$d.title }
            if (($names -contains 'category') -and $d.category) { $p.Category = [string]$d.category }
            if (($names -contains 'project')  -and $d.project)  { $p.Project  = [string]$d.project }
            if (($names -contains 'adoId')    -and $d.adoId)    { $p.AdoId    = [string]$d.adoId }
            $script:SuppressDashboard = $false
            Start-Work @p | Out-Null   # starts a new running session, persists + rebuilds
            Write-Host ("> Live resume started: {0}" -f $p.Title)
            Write-WorkServerJson $res 200 @{ ok = $true }
            return
        }
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/new') {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $d = $body | ConvertFrom-Json
            $names = $d.PSObject.Properties.Name
            $p = @{}
            if (($names -contains 'start') -and $d.start) { $p.Start = [datetime]$d.start }
            if (($names -contains 'end')   -and $d.end)   { $p.End   = [datetime]$d.end }
            if  ($names -contains 'category')        { $p.Category       = [string]$d.category }
            if  ($names -contains 'project')         { $p.Project        = [string]$d.project }
            if  ($names -contains 'title')           { $p.Title          = [string]$d.title }
            if  ($names -contains 'accomplishment')  { $p.Accomplishment  = [string]$d.accomplishment }
            $script:SuppressDashboard = $false
            New-WorkSession @p | Out-Null   # persists state and rebuilds the dashboard
            Write-Host '+ Live add applied'
            Write-WorkServerJson $res 200 @{ ok = $true }
            return
        }
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/note') {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $d = $body | ConvertFrom-Json
            $names = $d.PSObject.Properties.Name
            $p = @{ Text = [string]$d.text }
            if (($names -contains 'date') -and $d.date) { $p.Date = [datetime]$d.date }
            if  ($names -contains 'category')           { $p.Category = [string]$d.category }
            if  ($names -contains 'tags') {
                $p.Tags = @(([string]$d.tags) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            if (($names -contains 'id') -and $d.id) { Edit-Note -Id ([int]$d.id) @p; Write-Host ("~ Live note edit #{0}" -f [int]$d.id) }
            else       { Add-Note @p; Write-Host '+ Live note added' }
            $script:SuppressDashboard = $false
            New-WorkDashboard -NoOpen | Out-Null   # refresh embedded NOTES for reload
            Write-WorkServerJson $res 200 @{ ok = $true }
            return
        }
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/note-delete') {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $d = $body | ConvertFrom-Json
            Remove-Note -Id ([int]$d.id)
            $script:SuppressDashboard = $false
            New-WorkDashboard -NoOpen | Out-Null
            Write-Host ("- Live note removed #{0}" -f [int]$d.id)
            Write-WorkServerJson $res 200 @{ ok = $true }
            return
        }
        $file = Join-Path $script:OutDir 'work-dashboard.html'
        if (-not (Test-Path -LiteralPath $file)) { $script:SuppressDashboard = $false; New-WorkDashboard -NoOpen | Out-Null }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $res.ContentType = 'text/html; charset=utf-8'
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    catch {
        try { Write-WorkServerJson $res 500 @{ ok = $false; error = $_.Exception.Message } } catch {}
    }
    finally {
        try { $res.OutputStream.Close() } catch {}
    }
}

function Start-WorkServer {
    [CmdletBinding()]
    param([int]$Port = 8787, [switch]$NoOpen)
    $script:SuppressDashboard = $false
    New-WorkDashboard -NoOpen | Out-Null
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://localhost:$Port/"
    $listener.Prefixes.Add($prefix)
    try { $listener.Start() }
    catch { throw "Could not start WorkLog server on $prefix - $($_.Exception.Message)" }
    Write-Host "WorkLog live-edit server running at $prefix"
    Write-Host "Profile: $script:Profile  |  Edit sessions in the page; changes save instantly. Press Ctrl+C to stop."
    if (-not $NoOpen) { Start-Process $prefix }
    try {
        while ($listener.IsListening) {
            $ctx = $listener.GetContext()
            Invoke-WorkEditRequest -ctx $ctx
        }
    }
    finally {
        $listener.Stop(); $listener.Close()
        Write-Host 'WorkLog server stopped.'
    }
}

# ---- Public: Notes dashboard ----------------------------------------------
function New-NotesDashboard {
    [CmdletBinding()]
    param([switch]$NoOpen)

    $notes = @(Get-Notes)
    $count = $notes.Count

    # Build per-date groups (newest date first), server-rendered as cards.
    $groups = $notes | Group-Object Date | Sort-Object Name -Descending
    $sb = New-Object System.Text.StringBuilder
    if (-not $count) {
        [void]$sb.Append("<div class='empty'>No notes yet. Add one with <code>note `"text`"</code>.</div>")
    }
    foreach ($g in $groups) {
        $d = [datetime]::ParseExact($g.Name, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $hdr = $d.ToString('dddd, MMMM d, yyyy')
        $n = @($g.Group).Count
        [void]$sb.Append("<div class='daygrp' data-date='$($g.Name)'>")
        [void]$sb.Append("<div class='dayhdr'><span>$hdr</span><span class='ncount'>$n</span></div>")
        foreach ($note in ($g.Group | Sort-Object Id -Descending)) {
            $cat = if ($note.Category) { "<span class='cat'>$(HtmlEnc $note.Category)</span> " } else { '' }
            $tags = ''
            foreach ($t in @($note.Tags)) { if ($t) { $tags += "<span class='chip'>$(HtmlEnc $t)</span>" } }
            $txt = HtmlEnc $note.Text
            $search = (HtmlEnc (("{0} {1} {2}" -f $note.Text, $note.Category, ($note.Tags -join ' ')).ToLower()))
            [void]$sb.Append("<div class='card' style='margin-bottom:10px' data-search='$search'>")
            [void]$sb.Append("<div style='display:flex;justify-content:space-between;gap:12px;align-items:baseline'>")
            [void]$sb.Append("<div>$cat<span class='idnum'>#$($note.Id)</span></div>")
            [void]$sb.Append("<div class='muted' style='font-size:11px'>$(HtmlEnc $note.Created)</div></div>")
            [void]$sb.Append("<div style='margin-top:6px;font-size:14px'>$txt</div>")
            if ($tags) { [void]$sb.Append("<div style='margin-top:8px'>$tags</div>") }
            [void]$sb.Append("</div>")
        }
        [void]$sb.Append("</div>")
    }

    $meta = "Generated $((Get-Date).ToString('yyyy-MM-dd HH:mm')) &bull; $count note(s) &bull; date-bound, not time-bound"
    $search = "<input id='q' placeholder='Search notes&hellip;' oninput='filt()' style='width:100%;padding:10px 14px;background:var(--card2);border:1px solid var(--border);color:var(--text);font-size:14px;margin:6px 0 18px' autocomplete='off'>"
    $js = @'
<script>
function filt(){
  var q=document.getElementById('q').value.trim().toLowerCase();
  document.querySelectorAll('.daygrp').forEach(function(g){
    var any=false;
    g.querySelectorAll('.card').forEach(function(c){
      var hit = !q || (c.getAttribute('data-search')||'').indexOf(q)!==-1;
      c.style.display = hit ? '' : 'none';
      if(hit) any=true;
    });
    g.style.display = any ? '' : 'none';
  });
}
</script>
'@
    $body = "$search<div id='notes'>$($sb.ToString())</div>$js"
    $html = New-ReportHtml 'Notes' $meta $body

    # Markdown export
    $md = New-Object System.Text.StringBuilder
    [void]$md.Append("# Notes`n`n")
    foreach ($g in $groups) {
        $d = [datetime]::ParseExact($g.Name, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        [void]$md.Append("## $($d.ToString('dddd, MMMM d, yyyy'))`n`n")
        foreach ($note in ($g.Group | Sort-Object Id -Descending)) {
            $catMd = if ($note.Category) { "**[$($note.Category)]** " } else { '' }
            $tagMd = if (@($note.Tags).Count) { " _($(@($note.Tags) -join ', '))_" } else { '' }
            [void]$md.Append("- $catMd$($note.Text)$tagMd  `n")
        }
        [void]$md.Append("`n")
    }

    Write-Report -BaseName 'notes-dashboard' -Html $html -Md $md.ToString() -NoOpen:$NoOpen
}

Export-ModuleMember -Function Start-Work, Switch-Work, Stop-Work, Complete-Work, New-WorkSession, Add-DayMarker, New-GhIssueNote, Add-WorkNote, Edit-Work, Set-DayCommentary, `
    Get-OpenSessions, Get-WorkLog, Find-WorkLog, Show-WorkSearch, Show-WorkStatus, New-Standup, New-WeeklySummary, New-WorkDashboard, Start-WorkServer, `
    Set-WorkProfile, Set-WorkDefaultProfile, Get-WorkProfile, `
    Add-Note, Edit-Note, Remove-Note, Get-Notes, New-NotesDashboard
