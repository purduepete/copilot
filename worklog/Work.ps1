<#
.SYNOPSIS
  CLI wrapper for the WorkLog framework (start / switch / stop / note / summary / status / standup / week / log).

.EXAMPLES
  pwsh -File Work.ps1 start "Fix MS Sales pull" -Ado 435324 -Category Dev
  pwsh -File Work.ps1 start "Standup meeting" -Category Meeting
  pwsh -File Work.ps1 switch -Id 1
  pwsh -File Work.ps1 note "Found root cause in view definition"
  pwsh -File Work.ps1 summary "High-level recap of the day's accomplishments"
  pwsh -File Work.ps1 stop "Patched view, validated row counts" -Id 1
  pwsh -File Work.ps1 status
  pwsh -File Work.ps1 standup
  pwsh -File Work.ps1 week
  pwsh -File Work.ps1 log -Days 14

  # Profiles (keep work and personal logs separate):
  pwsh -File Work.ps1 status -Profile personal      # run any command against a profile
  pwsh -File Work.ps1 profile personal              # set THIS machine's default profile
  pwsh -File Work.ps1 profile                        # show current profile
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('start', 'switch', 'stop', 'note', 'edit', 'summary', 'commentary', 'status', 'standup', 'week', 'dashboard', 'log', 'profile')]
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
    [string]$Profile = '',
    [datetime]$Start,
    [datetime]$End,
    [datetime]$At,
    [switch]$Reopen,
    [switch]$NoOpen
)

Import-Module (Join-Path $PSScriptRoot 'WorkLog.psm1') -Force
if ($Profile) { Set-WorkProfile -Profile $Profile | Out-Null }

switch ($Command) {
    'start'   { $sp = @{ Title = $Text; AdoId = $Ado; Category = $Category; Project = $Project; Tags = $Tags }; if ($PSBoundParameters.ContainsKey('At')) { $sp.At = $At }; Start-Work @sp | Out-Null }
    'switch'  { Switch-Work -Id $Id }
    'stop'    { $sp = @{ Id = $Id; Accomplishment = $Text; Blocker = $Blocker; Status = $Status }; if ($PSBoundParameters.ContainsKey('At')) { $sp.At = $At }; Stop-Work @sp | Out-Null }
    'note'    { Add-WorkNote -Text $Text -Id $Id }
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
    'standup' { New-Standup -NoOpen:$NoOpen }
    'week'    { New-WeeklySummary -NoOpen:$NoOpen }
    'dashboard' { New-WorkDashboard -NoOpen:$NoOpen }
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
