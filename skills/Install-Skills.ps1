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

  Skills can be excluded by machine class through settings\machine-overrides.json,
  using the shared work/home classification in tools\Machine-Class.ps1. A machine
  can add local exclusions in %USERPROFILE%\.copilot\skills-ignore.txt. Blank lines
  and lines beginning with # are ignored. An excluded skill's existing junction is
  removed.

  Run on each new laptop after cloning the repo to C:\Files\Dev\main\copilot.
  Junctions do not require admin rights (unlike symlinks).

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
#>
[CmdletBinding()]
param(
    [string]$SkillsRepo = $PSScriptRoot,
    [string]$CopilotTarget = (Join-Path $env:USERPROFILE '.copilot\skills'),
    [string]$IgnoreFile = (Join-Path $env:USERPROFILE '.copilot\skills-ignore.txt'),
    [string]$MachineOverridesFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'settings\machine-overrides.json'),
    [string]$MachineClassScript = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Machine-Class.ps1'),
    [string]$ComputerName = $env:COMPUTERNAME,
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

if (-not (Test-Path -LiteralPath $MachineClassScript -PathType Leaf)) {
    throw "Machine classification script not found: $MachineClassScript"
}
. $MachineClassScript

function Get-IgnoredSkillNames {
    param(
        [string]$Path,
        [string]$OverridesPath,
        [string]$MachineClass
    )

    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            $name = $line.Trim()
            if ($name -and -not $name.StartsWith('#')) {
                $null = $names.Add($name)
            }
        }
    }

    if ($MachineClass -and (Test-Path -LiteralPath $OverridesPath -PathType Leaf)) {
        $overrides = Get-Content -LiteralPath $OverridesPath -Raw | ConvertFrom-Json -AsHashtable
        if ($overrides.ContainsKey($MachineClass)) {
            foreach ($name in @($overrides[$MachineClass]['ignoredSkills'])) {
                $trimmed = ([string]$name).Trim()
                if ($trimmed) {
                    $null = $names.Add($trimmed)
                }
            }
        }
    }

    return ,$names
}

function Install-SkillJunctions {
    param(
        [string]$SkillsRepo,
        [string]$Target,
        [System.Collections.Generic.HashSet[string]]$IgnoredSkills
    )

    New-Item -ItemType Directory -Path $Target -Force | Out-Null

    Get-ChildItem -Path $SkillsRepo -Directory | ForEach-Object {
        $name = $_.Name
        $link = Join-Path $Target $name
        $dest = $_.FullName

        if ($IgnoredSkills.Contains($name)) {
            if (Test-Path -LiteralPath $link) {
                $item = Get-Item -LiteralPath $link -Force
                if ($item.LinkType -eq 'Junction') {
                    Remove-Item -LiteralPath $link -Force -Recurse
                    Write-Host "- Ignored $name (removed junction)"
                    return
                }
                Write-Warning "$link is ignored but exists and is not a junction - leaving it untouched."
                return
            }
            Write-Host "- Ignored $name"
            return
        }

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

$machineClass = Get-MachineClass -ComputerName $ComputerName
$ignoredSkills = Get-IgnoredSkillNames `
    -Path $IgnoreFile `
    -OverridesPath $MachineOverridesFile `
    -MachineClass $machineClass
if ($ignoredSkills.Count -gt 0) {
    $scope = if ($machineClass) { "$machineClass machines plus local overrides" } else { 'local overrides' }
    Write-Host "Ignoring skills for $scope"
}
elseif (-not $machineClass) {
    Write-Warning "Machine class not recognized for $ComputerName; only local skill exclusions can apply."
}

Write-Host "--- Copilot CLI ($CopilotTarget) ---"
Install-SkillJunctions -SkillsRepo $SkillsRepo -Target $CopilotTarget -IgnoredSkills $ignoredSkills

foreach ($extra in $ExtraSkillRepos) {
    if (Test-Path -LiteralPath $extra) {
        Write-Host "`n--- Extra skills ($extra) ---"
        Install-SkillJunctions -SkillsRepo $extra -Target $CopilotTarget -IgnoredSkills $ignoredSkills
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
    & $SettingsSync -Mode Apply -IfMissing -NoGit
    & $SettingsSync -Mode Status
}

Write-Host "`nDone."
