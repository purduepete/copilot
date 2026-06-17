<#
.SYNOPSIS
  CLI wrapper for the WorkLog framework (start / switch / stop / note / status / standup / week / log).

.EXAMPLES
  pwsh -File Work.ps1 start "Fix MS Sales pull" -Ado 435324 -Category Dev
  pwsh -File Work.ps1 start "Standup meeting" -Category Meeting
  pwsh -File Work.ps1 switch -Id 1
  pwsh -File Work.ps1 note "Found root cause in view definition"
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
    [ValidateSet('start', 'switch', 'stop', 'note', 'edit', 'status', 'standup', 'week', 'dashboard', 'log', 'profile')]
    [string]$Command,

    [Parameter(Position = 1)][string]$Text,
    [int]$Id = 0,
    [string]$Ado = '',
    [string]$Category = '',
    [string[]]$Tags = @(),
    [string]$Title = '',
    [string]$Accomplishment = '',
    [string]$Blocker = '',
    [ValidateSet('done', 'paused', 'in-progress')][string]$Status = 'done',
    [int]$Days = 7,
    [string]$Profile = '',
    [switch]$Reopen,
    [switch]$NoOpen
)

Import-Module (Join-Path $PSScriptRoot 'WorkLog.psm1') -Force
if ($Profile) { Set-WorkProfile -Profile $Profile | Out-Null }

switch ($Command) {
    'start'   { Start-Work -Title $Text -AdoId $Ado -Category $Category -Tags $Tags | Out-Null }
    'switch'  { Switch-Work -Id $Id }
    'stop'    { Stop-Work -Id $Id -Accomplishment $Text -Blocker $Blocker -Status $Status | Out-Null }
    'note'    { Add-WorkNote -Text $Text -Id $Id }
    'edit'    {
        $p = @{ Id = $Id }
        if     ($PSBoundParameters.ContainsKey('Title')) { $p.Title = $Title }
        elseif ($PSBoundParameters.ContainsKey('Text'))  { $p.Title = $Text }   # convenience: edit -Id 5 "new title"
        if ($PSBoundParameters.ContainsKey('Category'))       { $p.Category = $Category }
        if ($PSBoundParameters.ContainsKey('Ado'))            { $p.AdoId = $Ado }
        if ($PSBoundParameters.ContainsKey('Tags'))           { $p.Tags = $Tags }
        if ($PSBoundParameters.ContainsKey('Accomplishment')) { $p.Accomplishment = $Accomplishment }
        if ($PSBoundParameters.ContainsKey('Blocker'))        { $p.Blocker = $Blocker }
        if ($PSBoundParameters.ContainsKey('Status'))         { $p.Status = $Status }
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
