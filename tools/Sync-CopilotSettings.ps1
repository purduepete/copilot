<#
.SYNOPSIS
  Keep the Copilot CLI's user settings version-controlled and identical on every machine.

.DESCRIPTION
  Skills and global-instructions reach the CLI as directory junctions (Install-Skills.ps1),
  so they are already shared. The CLI's own preference files are not:

    settings.json            model, theme, colorMode, showReasoning, beeps, timestamps, ...
    permissions-config.json  per-location tool auto-approvals (az, pwsh, ...)

  Those live at %USERPROFILE%\.copilot and were previously machine-local. This script
  keeps a canonical copy in the repo (copilot\settings\) and moves it in either
  direction, doing the git side for you so each direction is one command.

  Copying rather than linking is deliberate: a single-FILE symlink on Windows needs admin
  or Developer Mode, and directory junctions can't be used because .copilot also holds
  machine-local state (config.json, session-store.db) that must NOT be shared.

  config.json is intentionally excluded. The CLI manages it and its contents are
  machine-local (firstLaunchAt, recentModelIds, askedSetupTerminals, trustedFolders).

.PARAMETER Mode
  Status  compare repo vs machine and report drift (default, changes nothing, no git)
  Save    this computer is right. Verifies the branch is current, copies machine -> repo,
          then commits and pushes.
  Apply   this computer is behind. Pulls, then copies repo -> machine.

  The modes are deliberately NOT called Pull/Push. Those read backwards here: "push my
  config" means machine -> repo to a human, but repo -> machine by git analogy, and
  guessing wrong overwrites a good config with a stale one. Passing Pull or Push is
  rejected with an error rather than interpreted.

.PARAMETER NoGit
  Run no git commands at all: no fetch, pull, commit or push. Save then only copies into
  the repo and leaves committing to you; Apply copies whatever the repo currently holds.
  This is NOT a read-only flag - Apply -NoGit still overwrites local files. To look
  without changing anything, use -Mode Status.

.PARAMETER IfMissing
  With -Mode Apply, only write files that don't exist on this machine. Used by
  Install-Skills.ps1 so onboarding a new machine never clobbers local preferences.

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1
  pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Save
  pwsh -File C:\Files\Dev\main\copilot\tools\Sync-CopilotSettings.ps1 -Mode Apply
#>
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Save', 'Apply')]
    [string]$Mode = 'Status',

    [switch]$IfMissing,

    [switch]$NoGit,

    [string]$RepoSettings   = (Join-Path (Split-Path $PSScriptRoot -Parent) 'settings'),
    [string]$CopilotHome    = (Join-Path $env:USERPROFILE '.copilot'),
    [string[]]$Files        = @('settings.json', 'permissions-config.json')
)

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $RepoSettings

function Invoke-Git {
    <#
      Runs git and returns a result object. PowerShell does not turn a native command's
      stderr into a terminating error, so every call site must check the exit code
      explicitly or a failure passes silently.
    #>
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $out = & git @Arguments 2>&1
    return [pscustomobject]@{
        Ok     = ($LASTEXITCODE -eq 0)
        Code   = $LASTEXITCODE
        Output = ($out | Out-String).Trim()
    }
}

function Test-RepoUsable {
    <#
      Refuse to touch a repo that is mid-operation or not on a branch. A stray commit
      during a rebase is far worse than a settings change arriving late.
    #>
    foreach ($marker in 'MERGE_HEAD', 'REBASE_HEAD', 'CHERRY_PICK_HEAD') {
        # rev-parse --git-path, not "$repo\.git\$marker": inside a git worktree .git is a
        # FILE, not a directory, and the naive path never exists so the guard never fires.
        $p = Invoke-Git rev-parse --git-path $marker
        if ($p.Ok -and (Test-Path -LiteralPath $p.Output)) {
            Write-Warning "Repo is mid-$marker. Finish or abort that first."
            return $false
        }
    }

    $b = Invoke-Git rev-parse --abbrev-ref HEAD
    if (-not $b.Ok -or $b.Output -eq 'HEAD') {
        Write-Warning "Not on a branch (detached HEAD). Check out a branch first."
        return $false
    }

    $script:Branch = $b.Output
    return $true
}

function Test-BranchCurrent {
    <#
      Save must not publish stale settings. If this machine hasn't pulled, copying its
      older config into the repo would overwrite a newer canonical copy, and the failure
      would only surface at push time with the bad commit already made.
    #>
    $f = Invoke-Git fetch --quiet
    if (-not $f.Ok) {
        Write-Warning "git fetch failed - can't confirm this branch is current, so nothing was written."
        Write-Warning $f.Output
        return $false
    }

    $up = Invoke-Git rev-parse --abbrev-ref '@{upstream}'
    if (-not $up.Ok) {
        Write-Warning "Branch '$script:Branch' has no upstream. Push it once with: git push -u origin $script:Branch"
        return $false
    }

    $counts = Invoke-Git rev-list --left-right --count 'HEAD...@{upstream}'
    if (-not $counts.Ok) {
        Write-Warning "Couldn't compare with upstream - nothing was written."
        return $false
    }

    $ahead, $behind = $counts.Output -split '\s+'
    if ([int]$behind -gt 0) {
        if ([int]$ahead -gt 0) {
            Write-Warning "Branch has DIVERGED from upstream ($ahead ahead, $behind behind). Nothing was written."
            Write-Warning "Reconcile the repo yourself, then re-run."
        }
        else {
            Write-Warning "Branch is $behind commit(s) BEHIND upstream. Nothing was written."
            Write-Warning "Run -Mode Apply first (or git pull), then re-run -Mode Save."
        }
        return $false
    }

    return $true
}

function Sync-FromRemote {
    <#
      Apply pulls before comparing so it never installs a stale copy. On any failure
      nothing is written at all - a half-applied settings sync is worse than none.
    #>
    $p = Invoke-Git pull --ff-only
    if ($p.Ok) { return $true }

    $detail = $p.Output
    if     ($detail -match 'not possible to fast-forward|diverging')  { Write-Warning "Branch has diverged from upstream - reconcile the repo first." }
    elseif ($detail -match 'local changes .* would be overwritten|commit your changes') { Write-Warning "Working tree is dirty - commit or stash first." }
    elseif ($detail -match 'no tracking information|no upstream')     { Write-Warning "Branch has no upstream. Set one with: git push -u origin $script:Branch" }
    elseif ($detail -match 'could not resolve host|unable to access|Connection|timed out') { Write-Warning "Can't reach the remote (offline?)." }
    elseif ($detail -match 'Authentication|denied|403|401')           { Write-Warning "Git authentication failed." }
    else                                                              { Write-Warning "git pull --ff-only failed." }

    Write-Warning $detail
    Write-Host   "`nNothing was written. Your local settings are untouched."
    return $false
}

function Publish-Settings {
    <#
      Commit and push ONLY the named settings files. Both the add and the commit are
      scoped to that exact list, so anything the user already staged elsewhere cannot
      ride along, and no stray file dropped into settings\ is ever published.
    #>
    $spec = @()
    foreach ($n in $Files) {
        if (Test-Path -LiteralPath (Join-Path $RepoSettings $n)) { $spec += "settings/$n" }
    }
    if (-not $spec) { Write-Warning "No settings files to commit."; return }

    $add = Invoke-Git add -- @spec
    if (-not $add.Ok) {
        Write-Warning "git add failed - settings are copied into the repo but uncommitted."
        Write-Warning $add.Output
        return
    }

    $staged = Invoke-Git diff --cached --name-only -- @spec
    if (-not $staged.Output) {
        Write-Host "`nNothing to commit under settings\."
        return
    }

    Write-Host "`nabout to commit and push:"
    foreach ($f in ($staged.Output -split "`r?`n")) { Write-Host "  $f" }

    $msg = @"
Update Copilot CLI settings from $env:COMPUTERNAME

Captured by tools\Sync-CopilotSettings.ps1 -Mode Save.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
"@

    # --only: commit exactly these paths regardless of what else sits in the index.
    $commit = Invoke-Git commit --only -m $msg -- @spec
    if (-not $commit.Ok) {
        Write-Warning "git commit failed - settings are copied into the repo but uncommitted."
        Write-Warning $commit.Output
        return
    }

    $sha = (Invoke-Git rev-parse --short HEAD).Output
    Write-Host "committed $sha on $script:Branch"

    $push = Invoke-Git push origin $script:Branch
    if ($push.Ok) {
        Write-Host "pushed to origin/$script:Branch"
        Write-Host "`nOn your other computers: -Mode Apply, then /restart."
        return
    }

    # Someone pushed between the preflight and now, or the network dropped. Stop here.
    # Never auto-rebase a settings commit; the user decides how to reconcile.
    Write-Warning "git push was rejected or failed. The commit is local and your backups are intact."
    Write-Warning $push.Output
    Write-Host @"

Recover with:
  cd $script:RepoRoot
  git pull --rebase
  git push origin $script:Branch
"@
}

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
    param([string]$Source, [string]$Dest, [string]$Name, [bool]$MakeBackup = $true)

    Assert-ValidJson -Path $Source -Label $Name

    if ($MakeBackup -and (Test-Path -LiteralPath $Dest)) {
        # Only the machine side gets a .bak- copy. The repo side doesn't need one:
        # git history is the backup, and a stray file in settings\ risks being committed.
        $backupPath = "$Dest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Dest -Destination $backupPath -Force
        Write-Host "  backup -> $(Split-Path -Leaf $backupPath)"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Dest) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest -Force
}

New-Item -ItemType Directory -Path $RepoSettings -Force | Out-Null

Write-Host "repo    : $RepoSettings"
Write-Host "machine : $CopilotHome"
Write-Host "mode    : $Mode$(if ($NoGit) { '  (-NoGit)' })`n"

# --- git preflight, before a single byte is written -------------------------------
if ($Mode -ne 'Status' -and -not $NoGit) {
    Push-Location $script:RepoRoot
    try {
        if (-not (Test-RepoUsable)) { return }

        if ($Mode -eq 'Save'  -and -not (Test-BranchCurrent)) { return }
        if ($Mode -eq 'Apply' -and -not (Sync-FromRemote))    { return }
    }
    finally { Pop-Location }
}

$changed = 0

foreach ($name in $Files) {
    $repoFile = Join-Path $RepoSettings $name
    $liveFile = Join-Path $CopilotHome  $name

    $repoHash = Get-JsonHash $repoFile
    $liveHash = Get-JsonHash $liveFile

    switch ($Mode) {
        'Status' {
            if     (-not $repoHash -and -not $liveHash) { Write-Host "? $name missing on both sides" }
            elseif (-not $repoHash)                     { Write-Host "+ $name exists only on this machine - run -Mode Save" }
            elseif (-not $liveHash)                     { Write-Host "+ $name exists only in the repo - run -Mode Apply" }
            elseif ($repoHash -eq $liveHash)            { Write-Host "= $name in sync" }
            else                                        { Write-Host "~ $name DIFFERS (repo vs machine)" }
        }

        'Save' {
            if (-not $liveHash) { Write-Host "- $name not present on this machine - skipped"; break }
            if ($repoHash -eq $liveHash) { Write-Host "= $name already in sync"; break }
            Copy-Setting -Source $liveFile -Dest $repoFile -Name $name -MakeBackup $false
            Write-Host "^ $name machine -> repo"
            $changed++
        }

        'Apply' {
            if (-not $repoHash) { Write-Host "- $name not in the repo - skipped"; break }
            if ($IfMissing -and $liveHash) { Write-Host "= $name already present - left alone (-IfMissing)"; break }
            if ($repoHash -eq $liveHash) { Write-Host "= $name already in sync"; break }
            Copy-Setting -Source $repoFile -Dest $liveFile -Name $name
            Write-Host "v $name repo -> machine"
            $changed++
        }
    }
}

if ($Mode -eq 'Save' -and $changed -gt 0) {
    if ($NoGit) {
        Write-Host "`n-NoGit: copied into the repo only. Commit and push when you're ready."
    }
    else {
        Push-Location $script:RepoRoot
        try { Publish-Settings }
        finally { Pop-Location }
    }
}
elseif ($Mode -eq 'Apply' -and $changed -gt 0) {
    Write-Host "`nNext: run /restart in the Copilot CLI to load the new settings."
}
else {
    Write-Host "`nDone."
}
