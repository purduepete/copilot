<#
.SYNOPSIS
  CLI wrapper for the WorkLog framework (start / switch / stop / note / summary / status / standup / week / log).

.EXAMPLES
  pwsh -File Work.ps1 start "Fix MS Sales pull" -Ado 435324 -Category Dev
  pwsh -File Work.ps1 start "Standup meeting" -Category Meeting
  pwsh -File Work.ps1 add "Reviewed PR feedback" -Start "2026-06-16 14:00" -End "2026-06-16 14:45" -Category Review -Project bedrock
  pwsh -File Work.ps1 switch -Id 1
  pwsh -File Work.ps1 note "Found root cause in view definition"
  pwsh -File Work.ps1 summary "High-level recap of the day's accomplishments"
  pwsh -File Work.ps1 stop "Patched view, validated row counts" -Id 1
  pwsh -File Work.ps1 close "Fixed comma formatting" -Id 1 -Issue 17 -RepoPath C:\Files\Dev\main\webportfolio -CloseIssue
  pwsh -File Work.ps1 status
  pwsh -File Work.ps1 search "fabric"            # search all sessions (title, notes, project, etc.)
  pwsh -File Work.ps1 search "fabric" -Days 14   # limit search to last 14 days
  pwsh -File Work.ps1 standup
  pwsh -File Work.ps1 week
  pwsh -File Work.ps1 dashboard
  pwsh -File Work.ps1 serve                          # live-edit dashboard at http://localhost:8787 (Ctrl+C to stop)
  pwsh -File Work.ps1 serve -Port 9000               # use a custom port
  pwsh -File Work.ps1 log -Days 14

  # Profiles (keep work and personal logs separate):
  pwsh -File Work.ps1 status -Profile personal      # run any command against a profile
  pwsh -File Work.ps1 profile personal              # set THIS machine's default profile
  pwsh -File Work.ps1 profile                        # show current profile
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('start', 'switch', 'stop', 'close', 'add', 'note', 'tasknote', 'notes', 'edit', 'summary', 'commentary', 'status', 'search', 'standup', 'week', 'dashboard', 'serve', 'log', 'profile')]
    [string]$Command,

    [Parameter(Position = 1)][string]$Text,
    [int]$Id = 0,
    [string]$Ado = '',
    [string]$Category = '',
    [string]$Project = '',
    [string[]]$Tags = @(),
    [string]$Title = '',
    [string]$Accomplishment = '',
    [string]$Blocker = '',
    [ValidateSet('done', 'paused', 'in-progress')][string]$Status = 'done',
    [int]$Days = 7,
    [int]$Port = 8787,
    [string]$Profile = '',
    [datetime]$Start,
    [datetime]$End,
    [datetime]$At,
    [datetime]$Date,
    [int]$Issue = 0,
    [string]$RepoPath = '',
    [string]$Commit = '',
    [switch]$CloseIssue,
    [switch]$AfterLast,
    [switch]$Reopen,
    [switch]$Remove,
    [switch]$NoOpen
)

Import-Module (Join-Path $PSScriptRoot 'WorkLog.psm1') -Force
if ($Profile) { Set-WorkProfile -Profile $Profile | Out-Null }

switch ($Command) {
    'start'   { $sp = @{ Title = $Text; AdoId = $Ado; Category = $Category; Project = $Project; Tags = $Tags }; if ($PSBoundParameters.ContainsKey('At')) { $sp.At = $At }; if ($AfterLast) { $sp.AfterLast = $true }; Start-Work @sp | Out-Null }
    'switch'  { Switch-Work -Id $Id }
    'stop'    { $sp = @{ Id = $Id; Accomplishment = $Text; Blocker = $Blocker; Status = $Status }; if ($PSBoundParameters.ContainsKey('At')) { $sp.At = $At }; Stop-Work @sp | Out-Null }
    'close'   {
        $sp = @{ Id = $Id; Accomplishment = $Text; Blocker = $Blocker; Status = $Status }
        if ($PSBoundParameters.ContainsKey('At')) { $sp.At = $At }
        if ($Issue)    { $sp.Issue = $Issue }
        if ($RepoPath) { $sp.RepoPath = $RepoPath }
        if ($Commit)   { $sp.Commit = $Commit }
        if ($CloseIssue) { $sp.CloseIssue = $true }
        Complete-Work @sp | Out-Null
    }
    'add'     {
        $p = @{}
        if ($PSBoundParameters.ContainsKey('Start')) { $p.Start = $Start } else { $p.Start = Get-Date }
        if ($PSBoundParameters.ContainsKey('End'))            { $p.End   = $End }
        if     ($PSBoundParameters.ContainsKey('Title'))      { $p.Title = $Title }
        elseif ($PSBoundParameters.ContainsKey('Text'))       { $p.Title = $Text }
        if ($PSBoundParameters.ContainsKey('Category'))       { $p.Category = $Category }
        if ($PSBoundParameters.ContainsKey('Project'))        { $p.Project = $Project }
        if ($PSBoundParameters.ContainsKey('Ado'))            { $p.AdoId = $Ado }
        if ($PSBoundParameters.ContainsKey('Tags'))           { $p.Tags = $Tags }
        if ($PSBoundParameters.ContainsKey('Accomplishment')) { $p.Accomplishment = $Accomplishment }
        New-WorkSession @p | Out-Null
    }
    'tasknote' { Add-WorkNote -Text $Text -Id $Id }
    'note'    {
        if ($Id -and $Remove) { Remove-Note -Id $Id }
        elseif ($Id) {
            $p = @{ Id = $Id }
            if     ($PSBoundParameters.ContainsKey('Text'))     { $p.Text = $Text }
            elseif ($PSBoundParameters.ContainsKey('Title'))    { $p.Text = $Title }
            if ($PSBoundParameters.ContainsKey('Date'))         { $p.Date = $Date }
            if ($PSBoundParameters.ContainsKey('Category'))     { $p.Category = $Category }
            if ($PSBoundParameters.ContainsKey('Tags'))         { $p.Tags = $Tags }
            Edit-Note @p
        }
        else {
            $p = @{ Text = $Text }
            if ($PSBoundParameters.ContainsKey('Date'))     { $p.Date = $Date }
            if ($PSBoundParameters.ContainsKey('Category')) { $p.Category = $Category }
            if ($PSBoundParameters.ContainsKey('Tags'))     { $p.Tags = $Tags }
            Add-Note @p
        }
    }
    'notes'   {
        New-NotesDashboard -NoOpen:$NoOpen | Out-Null
        Get-Notes -Since (Get-Date).AddDays(-$Days) | Format-Table Id, Date, Category, Text -AutoSize
    }
    'summary'    { Set-DayCommentary -Text $Text }
    'commentary' { Set-DayCommentary -Text $Text }
    'edit'    {
        $p = @{ Id = $Id }
        if     ($PSBoundParameters.ContainsKey('Title')) { $p.Title = $Title }
        elseif ($PSBoundParameters.ContainsKey('Text'))  { $p.Title = $Text }   # convenience: edit -Id 5 "new title"
        if ($PSBoundParameters.ContainsKey('Category'))       { $p.Category = $Category }
        if ($PSBoundParameters.ContainsKey('Project'))        { $p.Project = $Project }
        if ($PSBoundParameters.ContainsKey('Ado'))            { $p.AdoId = $Ado }
        if ($PSBoundParameters.ContainsKey('Tags'))           { $p.Tags = $Tags }
        if ($PSBoundParameters.ContainsKey('Accomplishment')) { $p.Accomplishment = $Accomplishment }
        if ($PSBoundParameters.ContainsKey('Blocker'))        { $p.Blocker = $Blocker }
        if ($PSBoundParameters.ContainsKey('Status'))         { $p.Status = $Status }
        if ($PSBoundParameters.ContainsKey('Start'))          { $p.Start = $Start }
        if ($PSBoundParameters.ContainsKey('End'))            { $p.End = $End }
        if ($Reopen)                                          { $p.Reopen = $true }
        Edit-Work @p | Out-Null
    }
    'status'  { Show-WorkStatus }
    'search'  { $sd = if ($PSBoundParameters.ContainsKey('Days')) { $Days } else { 0 }; Show-WorkSearch -Query $Text -Days $sd }
    'standup' { New-Standup -NoOpen:$NoOpen }
    'week'    { New-WeeklySummary -NoOpen:$NoOpen }
    'dashboard' { New-WorkDashboard -NoOpen:$NoOpen }
    'serve'     { Start-WorkServer -Port $Port -NoOpen:$NoOpen }
    'log'     { Get-WorkLog -Since (Get-Date).AddDays(-$Days) | Format-Table Id, Start, Min, Status, Kind, AdoId, Title -AutoSize }
    'profile' {
        if ($Text) { $r = Set-WorkDefaultProfile -Profile $Text; Write-Host "* Default profile for this machine set to '$($r.Profile)'" }
        else       { $r = Get-WorkProfile }
        Write-Host "Profile : $($r.Profile)"
        Write-Host "Log     : $($r.State)"
        Write-Host "Output  : $($r.OutDir)"
        Write-Host "ADO org : $(if ($r.Org) { $r.Org } else { '(none)' })"
    }
}
