<#
.SYNOPSIS
  Link the skills in this repo into the local Copilot CLI skills folder.

.DESCRIPTION
  The personal Copilot CLI skills live in this repo (copilot\skills\<name>) so they
  are version-controlled and shared across machines. The Copilot CLI loads skills
  from %USERPROFILE%\.copilot\skills. This script creates a directory junction for
  each skill folder in this repo into that location, so edits in the repo are picked
  up directly (no copying).

  Run on each new laptop after cloning the repo to C:\Files\Dev\main\copilot.
  Junctions do not require admin rights (unlike symlinks).

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
#>
[CmdletBinding()]
param(
    [string]$SkillsRepo = $PSScriptRoot,
    [string]$Target = (Join-Path $env:USERPROFILE '.copilot\skills')
)

New-Item -ItemType Directory -Path $Target -Force | Out-Null

Get-ChildItem -Path $SkillsRepo -Directory | ForEach-Object {
    $name = $_.Name
    $link = Join-Path $Target $name
    $dest = $_.FullName

    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -eq 'Junction') {
            Write-Host "= $name already linked"
            return
        }
        Write-Warning "$link exists and is not a junction - skipping. Remove it manually to link."
        return
    }

    New-Item -ItemType Junction -Path $link -Target $dest | Out-Null
    Write-Host "+ Linked $name -> $dest"
}

Write-Host "`nDone. Skills available at $Target"
