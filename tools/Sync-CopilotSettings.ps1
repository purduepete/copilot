<#
.SYNOPSIS
  Keep the Copilot CLI's user settings version-controlled and identical on every machine,
  except for specific keys that legitimately differ by machine class (work vs home).

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

  PER-MACHINE-CLASS KEYS (e.g. "model")
  --------------------------------------
  A small set of settings.json keys, listed in $PerMachineKeys, are allowed to differ
  by machine class ("work" or "home", classified by $env:COMPUTERNAME - see
  Get-MachineClass). The mapping of class -> key -> value lives in
  copilot\settings\machine-overrides.json, a repo-only file with no machine-local
  counterpart (it is read/written directly in the repo, then committed/pushed like the
  other files - there's nothing to copy onto %USERPROFILE%\.copilot for it).

  Invariant: the repo's settings.json NEVER contains a $PerMachineKeys key. Drift
  comparison for settings.json is structural (parsed JSON with those keys removed from
  the machine side before comparing), not a raw file hash, so a legitimately different
  "model" is never reported as drift and never blocks Save/Apply.

  Save seeds a class's override the first time that class/key is seen (from the live
  machine value) rather than overwriting an existing value, and updates it when the
  live value has changed. Apply overlays the current class's override onto the merged
  settings.json; if the machine's class is unrecognized, or that class has no entry for
  a key, the existing local value for that key is preserved untouched (fail-safe - it
  is never silently replaced by a repo default or another class's value).

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
    # Files with a machine-local counterpart, synced machine <-> repo as whole files
    # (settings.json is handled separately below because of its per-machine keys;
    # it stays in this list only so Publish-Settings knows to stage/commit it).
    [string[]]$Files        = @('settings.json', 'permissions-config.json'),
    # settings.json keys allowed to differ by machine class. Extend this array (and
    # seed machine-overrides.json) to add another overridable key.
    [string[]]$PerMachineKeys = @('model'),
    [string]$MachineOverridesFile = (Join-Path $RepoSettings 'machine-overrides.json')
)

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $RepoSettings

function Get-MachineClass {
    <#
      Classifies $env:COMPUTERNAME into "work" or "home". Returns $null for an
      unrecognized machine - every caller must treat $null as "leave per-machine keys
      alone", never as "fall back to some default".
    #>
    param([string]$ComputerName = $env:COMPUTERNAME)

    if ($ComputerName -like 'XFINJIMB*' -or $ComputerName -like 'CPC-jimb-*') { return 'work' }
    if ($ComputerName -like 'JIMBROWN*') { return 'home' }
    return $null
}

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
    param([string[]]$PublishFiles)

    $spec = @()
    foreach ($n in $PublishFiles) {
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

function Read-JsonObject {
    <#
      Parses a JSON file into an ordered hashtable (so keys can be added/removed/
      compared structurally) or $null if the file doesn't exist. Strips // line
      comments first, same tolerance the CLI itself has.
    #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [IO.File]::ReadAllText($Path)
    $stripped = $raw -replace '(?m)^\s*//.*$', ''
    if (-not $stripped.Trim()) { return [ordered]@{} }
    return $stripped | ConvertFrom-Json -AsHashtable
}

function Copy-WithoutKeys {
    <#
      Returns a new ordered hashtable with the given keys removed. Never mutates the
      input - callers rely on being able to still read the original afterward.
    #>
    param([hashtable]$Object, [string[]]$Keys)
    $result = [ordered]@{}
    if (-not $Object) { return $result }
    foreach ($k in $Object.Keys) {
        if ($Keys -notcontains $k) { $result[$k] = $Object[$k] }
    }
    return $result
}

function ConvertTo-CanonicalJsonText {
    <#
      Serializes a value with object keys sorted, so 2 objects that differ only in key
      order/whitespace/formatting compare as equal. This backs the structural drift
      check for settings.json instead of a raw-text hash.
    #>
    param($Value)

    if ($null -eq $Value) { return 'null' }

    if ($Value -is [System.Collections.IDictionary]) {
        $parts = foreach ($k in ($Value.Keys | Sort-Object)) {
            '{0}:{1}' -f (ConvertTo-Json ([string]$k) -Compress), (ConvertTo-CanonicalJsonText $Value[$k])
        }
        return '{' + ($parts -join ',') + '}'
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $parts = foreach ($item in $Value) { ConvertTo-CanonicalJsonText $item }
        return '[' + ($parts -join ',') + ']'
    }

    return (ConvertTo-Json $Value -Compress)
}

function Get-CanonicalHash {
    param($Object)
    $text = ConvertTo-CanonicalJsonText $Object
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Write-JsonObject {
    <#
      Serializes and writes a hashtable/object as the new content of Path in a single
      write call - callers build the final object in memory first (never write partial
      or pre-strip content), which is how the per-machine-key leak the reviewers
      flagged is avoided.
    #>
    param([string]$Path, $Object, [bool]$MakeBackup = $true)

    if ($MakeBackup -and (Test-Path -LiteralPath $Path)) {
        $backupPath = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        Write-Host "  backup -> $(Split-Path -Leaf $backupPath)"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    ($Object | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
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

function Invoke-SettingsJsonSync {
    <#
      Handles settings.json specially because of its per-machine-class keys
      ($PerMachineKeys). Everything else (permissions-config.json) still goes through
      the generic whole-file loop in the main script body below.

      Returns the number of files changed (0 or 1) so the caller's overall $changed
      counter stays accurate for the "anything to commit / run Apply" messaging.
    #>
    param(
        [string]$RepoFile,
        [string]$LiveFile,
        [string]$MachineOverridesFile,
        [string[]]$PerMachineKeys,
        [string]$Mode,
        [bool]$IfMissing
    )

    $class = Get-MachineClass
    $changed = 0

    switch ($Mode) {
        'Status' {
            $repoObj = Read-JsonObject $RepoFile
            $liveObj = Read-JsonObject $LiveFile

            if (-not $repoObj -and -not $liveObj) { Write-Host "? settings.json missing on both sides"; return 0 }
            if (-not $repoObj) { Write-Host "+ settings.json exists only on this machine - run -Mode Save"; return 0 }
            if (-not $liveObj) { Write-Host "+ settings.json exists only in the repo - run -Mode Apply"; return 0 }

            # Repo copy must never carry per-machine keys (defensive strip even though
            # Save/Apply already enforce this), so drift compare is always apples-to-apples.
            $repoCanon = Copy-WithoutKeys $repoObj $PerMachineKeys
            $liveCanon = Copy-WithoutKeys $liveObj $PerMachineKeys

            if ((Get-CanonicalHash $repoCanon) -eq (Get-CanonicalHash $liveCanon)) {
                Write-Host "= settings.json in sync (ignoring per-machine keys: $($PerMachineKeys -join ', '))"
            }
            else {
                Write-Host "~ settings.json DIFFERS (repo vs machine) [ignoring per-machine keys: $($PerMachineKeys -join ', ')]"
            }

            $repoHasPerMachineKey = $PerMachineKeys | Where-Object { $repoObj.Contains($_) }
            if ($repoHasPerMachineKey) {
                Write-Warning "repo settings.json still contains machine-specific key(s) ($($repoHasPerMachineKey -join ', ')) - will be stripped on next Save"
            }

            $overrides = Read-JsonObject $MachineOverridesFile
            if (-not $class) {
                foreach ($key in $PerMachineKeys) {
                    Write-Host "? $key : machine class not recognized for $env:COMPUTERNAME - per-machine overrides not managed here (add this COMPUTERNAME to Get-MachineClass)"
                }
                return 0
            }

            foreach ($key in $PerMachineKeys) {
                $liveVal = if ($liveObj -and $liveObj.Contains($key)) { $liveObj[$key] } else { $null }
                $hasOverride = $overrides -and $overrides.Contains($class) -and $overrides[$class].Contains($key)
                $overrideVal = if ($hasOverride) { $overrides[$class][$key] } else { $null }

                if (-not $hasOverride) {
                    Write-Host "? $key ($class): no stored override yet - live value '$liveVal' will be adopted on next Save"
                }
                elseif ($liveVal -eq $overrideVal) {
                    Write-Host "= $key ($class): $overrideVal (matches override)"
                }
                else {
                    Write-Host "~ $key ($class): local=$liveVal, override=$overrideVal - run Apply or Save"
                }
            }
            return 0
        }

        'Save' {
            $liveObj = Read-JsonObject $LiveFile
            if (-not $liveObj) { Write-Host "- settings.json not present on this machine - skipped"; return 0 }

            # Build the repo-bound object atomically in memory BEFORE any file write -
            # there is never an intermediate state where the full local object (including
            # per-machine keys) is written to or staged in the repo.
            $repoBoundObj = Copy-WithoutKeys $liveObj $PerMachineKeys
            $repoObj = Read-JsonObject $RepoFile
            $repoObjCanon = if ($repoObj) { Copy-WithoutKeys $repoObj $PerMachineKeys } else { $null }

            # A stale/leftover per-machine key sitting in the repo copy (e.g. from
            # before this mechanism existed) must be stripped even when everything
            # else already matches - the "already in sync" short-circuit cannot be
            # based on the stripped comparison alone, or the invariant silently rots.
            $repoHasPerMachineKey = $repoObj -and ($PerMachineKeys | Where-Object { $repoObj.Contains($_) })

            if (-not $repoHasPerMachineKey -and $repoObjCanon -and (Get-CanonicalHash $repoObjCanon) -eq (Get-CanonicalHash $repoBoundObj)) {
                Write-Host "= settings.json already in sync (ignoring per-machine keys)"
            }
            else {
                Write-JsonObject -Path $RepoFile -Object $repoBoundObj -MakeBackup $false
                Write-Host "^ settings.json machine -> repo (per-machine keys excluded: $($PerMachineKeys -join ', '))"
                $changed++
            }

            # Seed/update this machine class's override from the live (pre-strip) values.
            if (-not $class) {
                Write-Warning "Machine class not recognized for $env:COMPUTERNAME - machine-overrides.json left untouched."
                return $changed
            }

            $overrides = Read-JsonObject $MachineOverridesFile
            if (-not $overrides) { $overrides = [ordered]@{} }
            if (-not $overrides.Contains($class)) { $overrides[$class] = [ordered]@{} }

            $overridesChanged = $false
            foreach ($key in $PerMachineKeys) {
                if (-not $liveObj.Contains($key)) { continue }
                $liveVal = $liveObj[$key]

                if (-not $overrides[$class].Contains($key)) {
                    # First time this class/key combination is seen: seed from the live
                    # machine value instead of silently adopting whatever else might be
                    # around. This is the safe migration path for an existing machine.
                    $overrides[$class][$key] = $liveVal
                    Write-Host "+ machine-overrides.json: seeded $class.$key = $liveVal"
                    $overridesChanged = $true
                }
                elseif ($overrides[$class][$key] -ne $liveVal) {
                    Write-Host "^ machine-overrides.json: updated $class.$key = $liveVal (was $($overrides[$class][$key]))"
                    $overrides[$class][$key] = $liveVal
                    $overridesChanged = $true
                }
            }

            if ($overridesChanged) {
                Write-JsonObject -Path $MachineOverridesFile -Object $overrides -MakeBackup $false
                $changed++
            }

            return $changed
        }

        'Apply' {
            $repoObj = Read-JsonObject $RepoFile
            if (-not $repoObj) { Write-Host "- settings.json not in the repo - skipped"; return 0 }

            if ($IfMissing -and (Test-Path -LiteralPath $LiveFile)) {
                Write-Host "= settings.json already present - left alone (-IfMissing)"
                return 0
            }

            $liveObj = Read-JsonObject $LiveFile
            $overrides = Read-JsonObject $MachineOverridesFile

            # Merge = repo's shared keys (defensively stripped of any per-machine key),
            # plus each per-machine key resolved as: class override if known and
            # present, else the EXISTING local value if any (fail-safe - never silently
            # replaced by a repo default or another class's value), else left absent.
            $merged = Copy-WithoutKeys $repoObj $PerMachineKeys
            foreach ($key in $PerMachineKeys) {
                $hasOverride = $class -and $overrides -and $overrides.Contains($class) -and $overrides[$class].Contains($key)
                if ($hasOverride) {
                    $merged[$key] = $overrides[$class][$key]
                }
                elseif ($liveObj -and $liveObj.Contains($key)) {
                    $merged[$key] = $liveObj[$key]
                }
                # else: no override and no existing local value - nothing safe to
                # default to, key is left absent.
            }

            $liveHash = if ($liveObj) { Get-CanonicalHash $liveObj } else { $null }
            $mergedHash = Get-CanonicalHash $merged

            if ($liveHash -eq $mergedHash) {
                Write-Host "= settings.json already in sync"
                return 0
            }

            Write-JsonObject -Path $LiveFile -Object $merged
            if (-not $class) {
                Write-Warning "Machine class not recognized for $env:COMPUTERNAME - existing local values for $($PerMachineKeys -join ', ') were preserved as-is."
            }
            Write-Host "v settings.json repo -> machine (class override applied: $($PerMachineKeys -join ', '))"
            return 1
        }
    }
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

# settings.json gets its own structural, per-machine-key-aware handling.
$changed += Invoke-SettingsJsonSync `
    -RepoFile $(Join-Path $RepoSettings 'settings.json') `
    -LiveFile $(Join-Path $CopilotHome  'settings.json') `
    -MachineOverridesFile $MachineOverridesFile `
    -PerMachineKeys $PerMachineKeys `
    -Mode $Mode `
    -IfMissing $IfMissing.IsPresent

# Every other file (currently just permissions-config.json) keeps the original
# generic whole-file compare/copy behavior - no per-machine-key concept applies.
foreach ($name in ($Files | Where-Object { $_ -ne 'settings.json' })) {
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
        try { Publish-Settings -PublishFiles ($Files + @('machine-overrides.json')) }
        finally { Pop-Location }
    }
}
elseif ($Mode -eq 'Apply' -and $changed -gt 0) {
    Write-Host "`nNext: run /restart in the Copilot CLI to load the new settings."
}
else {
    Write-Host "`nDone."
}
