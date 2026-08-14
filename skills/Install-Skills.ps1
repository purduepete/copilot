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
    # Personal global instructions folder in this repo, linked into
    # %USERPROFILE%\.copilot\instructions so its *.instructions.md load in every repo.
    [string]$GlobalInstructionsRepo = (Join-Path (Split-Path $PSScriptRoot -Parent) 'global-instructions'),
    [string]$GlobalInstructionsTarget = (Join-Path $env:USERPROFILE '.copilot\instructions'),
    # Canonical copy of the CLI's own preference files (settings.json,
    # permissions-config.json). Copied in, not linked - see Sync-CopilotSettings.ps1.
    [string]$SettingsSync = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Sync-CopilotSettings.ps1'),
    # Additional skill source folders from other repos. Each is linked only if the
    # local path exists (the repo may not be cloned on every machine).
    [string[]]$ExtraSkillRepos = @(
        'C:\Files\Dev\msft\bedrock_analysis\skills'
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

function Install-DirectoryJunction {
    param([string]$Source, [string]$Link)

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "- Skipping global instructions (not present): $Source"
        return
    }

    $parent = Split-Path -Parent $Link
    New-Item -ItemType Directory -Path $parent -Force | Out-Null

    if (Test-Path -LiteralPath $Link) {
        $item = Get-Item -LiteralPath $Link -Force
        if ($item.LinkType -eq 'Junction') {
            $current = @($item.Target)[0]
            if ($current -eq $Source) {
                Write-Host "= global instructions already linked"
                return
            }
            Remove-Item -LiteralPath $Link -Force -Recurse
            New-Item -ItemType Junction -Path $Link -Target $Source | Out-Null
            Write-Host "~ Re-linked global instructions -> $Source (was $current)"
            return
        }
        Write-Warning "$Link exists and is not a junction - skipping. Remove it manually to link."
        return
    }

    New-Item -ItemType Junction -Path $Link -Target $Source | Out-Null
    Write-Host "+ Linked global instructions -> $Source"
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

Write-Host "`n--- Global instructions ($GlobalInstructionsTarget) ---"
Install-DirectoryJunction -Source $GlobalInstructionsRepo -Link $GlobalInstructionsTarget

# Seed CLI settings on a machine that has none, then report any drift. -IfMissing keeps
# this non-destructive: existing local preferences are never overwritten here.
if (Test-Path -LiteralPath $SettingsSync) {
    Write-Host "`n--- Copilot settings ---"
    & $SettingsSync -Mode Push -IfMissing
    & $SettingsSync -Mode Status
}

Write-Host "`nDone."
