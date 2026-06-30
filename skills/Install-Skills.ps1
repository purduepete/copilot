<#
.SYNOPSIS
  Link the skills in this repo into the local Copilot CLI skills folder.

.DESCRIPTION
  The personal Copilot CLI skills live in this repo (copilot\skills\<name>) so they
  are version-controlled and shared across machines. Skills can span any topic, not
  just WorkLog. The Copilot CLI loads skills from %USERPROFILE%\.copilot\skills.
  This script creates a directory junction for each skill folder in this repo into
  that location, so edits in the repo are picked up directly (no copying).

  The script is self-healing: if a link already exists but is a junction pointing at
  a different (e.g. old/deleted) target, it is re-pointed at this repo. Real (non-
  junction) folders are left untouched so no data is lost.

  Run on each new laptop after cloning the repo to C:\Files\Dev\main\copilot.
  Junctions do not require admin rights (unlike symlinks).

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
#>
[CmdletBinding()]
param(
    [string]$SkillsRepo = $PSScriptRoot,
    [string]$CopilotTarget = (Join-Path $env:USERPROFILE '.copilot\skills'),
    # Additional skill source folders from other repos. Each is linked only if the
    # local path exists (the repo may not be cloned on every machine).
    [string[]]$ExtraSkillRepos = @(
        'C:\Files\Dev\msft\FDE_Revenue_Bedrock\.github\skills'
    )
)

function Install-SkillJunctions {
    param([string]$SkillsRepo, [string]$Target)

    New-Item -ItemType Directory -Path $Target -Force | Out-Null

    Get-ChildItem -Path $SkillsRepo -Directory | ForEach-Object {
        $name = $_.Name
        $link = Join-Path $Target $name
        $dest = $_.FullName

        if (Test-Path -LiteralPath $link) {
            $item = Get-Item -LiteralPath $link -Force
            if ($item.LinkType -eq 'Junction') {
                $current = @($item.Target)[0]
                if ($current -eq $dest) {
                    Write-Host "= $name already linked"
                    return
                }
                # Junction points somewhere else (old location or dangling) -> re-point it.
                Remove-Item -LiteralPath $link -Force -Recurse
                New-Item -ItemType Junction -Path $link -Target $dest | Out-Null
                Write-Host "~ Re-linked $name -> $dest (was $current)"
                return
            }
            Write-Warning "$link exists and is not a junction - skipping. Remove it manually to link."
            return
        }

        New-Item -ItemType Junction -Path $link -Target $dest | Out-Null
        Write-Host "+ Linked $name -> $dest"
    }
}

Write-Host "--- Copilot CLI ($CopilotTarget) ---"
Install-SkillJunctions -SkillsRepo $SkillsRepo -Target $CopilotTarget

foreach ($extra in $ExtraSkillRepos) {
    if (Test-Path -LiteralPath $extra) {
        Write-Host "`n--- Extra skills ($extra) ---"
        Install-SkillJunctions -SkillsRepo $extra -Target $CopilotTarget
    }
    else {
        Write-Host "`n- Skipping (not present): $extra"
    }
}

Write-Host "`nDone."
