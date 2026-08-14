<#
.SYNOPSIS
  Keep the Copilot CLI's user settings version-controlled and identical on every machine.

.DESCRIPTION
  Skills and global-instructions reach the CLI as directory junctions (Install-Skills.ps1),
  so they are already shared. The CLI's own preference files are not:

    settings.json            model, theme, colorMode, showReasoning, beeps, timestamps, ...
    permissions-config.json  per-location tool auto-approvals (az, pwsh, ...)

  Those live at %USERPROFILE%\.copilot and were previously machine-local. This script
  keeps a canonical copy in the repo (copilot\settings\) and copies it in either
  direction.

  Copying rather than linking is deliberate: a single-FILE symlink on Windows needs admin
  or Developer Mode, and directory junctions can't be used because .copilot also holds
  machine-local state (config.json, session-store.db) that must NOT be shared.

  config.json is intentionally excluded. The CLI manages it and its contents are
  machine-local (firstLaunchAt, recentModelIds, askedSetupTerminals).

.PARAMETER Mode
  Status  compare repo vs machine and report drift (default, changes nothing)
  Pull    machine -> repo. Run after changing settings via /settings, then commit.
  Push    repo -> machine. Run on another computer after git pull.

.PARAMETER IfMissing
  With -Mode Push, only write files that don't exist on this machine. Used by
  Install-Skills.ps1 so onboarding a new machine never clobbers local preferences.

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1
  pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Pull
  pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Push
#>
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Pull', 'Push')]
    [string]$Mode = 'Status',

    [switch]$IfMissing,

    [string]$RepoSettings   = (Join-Path (Split-Path $PSScriptRoot -Parent) 'settings'),
    [string]$CopilotHome    = (Join-Path $env:USERPROFILE '.copilot'),
    [string[]]$Files        = @('settings.json', 'permissions-config.json')
)

$ErrorActionPreference = 'Stop'

function Get-JsonHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    # Hash the normalized text so a CRLF/LF or trailing-newline difference isn't
    # reported as drift.
    $text = ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n").TrimEnd()
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Assert-ValidJson {
    param([string]$Path, [string]$Label)
    try {
        # The CLI tolerates // comments in these files; strip line comments before parsing.
        $raw = [IO.File]::ReadAllText($Path)
        ($raw -replace '(?m)^\s*//.*$', '') | ConvertFrom-Json -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$Label is not valid JSON: $Path`n$($_.Exception.Message)"
    }
}

function Copy-Setting {
    param([string]$Source, [string]$Dest, [string]$Name)

    Assert-ValidJson -Path $Source -Label $Name

    if (Test-Path -LiteralPath $Dest) {
        $backup = "$Dest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Dest -Destination $backup -Force
        Write-Host "  backup -> $(Split-Path -Leaf $backup)"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Dest) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest -Force
}

New-Item -ItemType Directory -Path $RepoSettings -Force | Out-Null

Write-Host "repo    : $RepoSettings"
Write-Host "machine : $CopilotHome"
Write-Host "mode    : $Mode`n"

$changed = 0

foreach ($name in $Files) {
    $repoFile = Join-Path $RepoSettings $name
    $liveFile = Join-Path $CopilotHome  $name

    $repoHash = Get-JsonHash $repoFile
    $liveHash = Get-JsonHash $liveFile

    switch ($Mode) {
        'Status' {
            if     (-not $repoHash -and -not $liveHash) { Write-Host "? $name missing on both sides" }
            elseif (-not $repoHash)                     { Write-Host "+ $name exists only on this machine - run -Mode Pull" }
            elseif (-not $liveHash)                     { Write-Host "+ $name exists only in the repo - run -Mode Push" }
            elseif ($repoHash -eq $liveHash)            { Write-Host "= $name in sync" }
            else                                        { Write-Host "~ $name DIFFERS (repo vs machine)" }
        }

        'Pull' {
            if (-not $liveHash) { Write-Host "- $name not present on this machine - skipped"; break }
            if ($repoHash -eq $liveHash) { Write-Host "= $name already in sync"; break }
            Copy-Setting -Source $liveFile -Dest $repoFile -Name $name
            Write-Host "^ $name machine -> repo"
            $changed++
        }

        'Push' {
            if (-not $repoHash) { Write-Host "- $name not in the repo - skipped"; break }
            if ($IfMissing -and $liveHash) { Write-Host "= $name already present - left alone (-IfMissing)"; break }
            if ($repoHash -eq $liveHash) { Write-Host "= $name already in sync"; break }
            Copy-Setting -Source $repoFile -Dest $liveFile -Name $name
            Write-Host "v $name repo -> machine"
            $changed++
        }
    }
}

if ($Mode -eq 'Pull' -and $changed -gt 0) {
    Write-Host "`nNext: commit and push the repo, then run -Mode Push on your other computers."
}
elseif ($Mode -eq 'Push' -and $changed -gt 0) {
    Write-Host "`nNext: run /restart in the Copilot CLI to load the new settings."
}
else {
    Write-Host "`nDone."
}
