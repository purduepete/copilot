#requires -Version 7.0
<#
.SYNOPSIS
  Inventory / structure report for the FDE_Revenue_Bedrock repository.

.DESCRIPTION
  Profiles the bedrock repo without cloning or calling any remote service:
    * top-level folder layout (file + subfolder counts)
    * file-type breakdown by extension (.git excluded)
    * skills catalog parsed from .github/skills/*/SKILL.md frontmatter
    * agents catalog parsed from .github/agents/*.agent.md frontmatter
    * recent git activity (current branch + last N commits)

  Human-readable by default; pass -Json for a single machine-readable object.

.PARAMETER RepoPath
  Path to the bedrock repo clone. Defaults to C:\Files\Dev\msft\FDE_Revenue_Bedrock.

.PARAMETER Commits
  Number of recent commits to include in the activity section. Default 10.

.PARAMETER Json
  Emit the report as a JSON object instead of formatted text.

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Get-BedrockRepoInventory.ps1

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Get-BedrockRepoInventory.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$RepoPath = 'C:\Files\Dev\msft\FDE_Revenue_Bedrock',
    [int]$Commits = 10,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RepoPath)) {
    throw "Repo path not found: $RepoPath"
}
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

# --- frontmatter helper -----------------------------------------------------
# Extracts the YAML frontmatter block (between the first two '---' fences) into
# an ordered hashtable. Handles simple 'key: value' and folded/literal scalars
# ('>-', '|', or an empty value followed by indented continuation lines).
function Get-Frontmatter {
    param([string]$Path)
    $fm = [ordered]@{}
    $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $lines -or $lines[0].Trim() -ne '---') { return $fm }
    $i = 1
    while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '---') {
        $line = $lines[$i]
        if ($line -match '^([A-Za-z0-9_-]+):\s?(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2]
            if ($val -in @('>-', '>', '|', '|-', '')) {
                # folded/literal or empty: gather indented continuation lines
                $parts = @()
                $i++
                while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '---' -and
                       ($lines[$i] -match '^\s+\S' -or $lines[$i].Trim() -eq '')) {
                    if ($lines[$i].Trim() -ne '') { $parts += $lines[$i].Trim() }
                    $i++
                }
                $fm[$key] = ($parts -join ' ').Trim()
                continue
            }
            $fm[$key] = $val.Trim().Trim('"').Trim("'")
        }
        $i++
    }
    return $fm
}

# Concise purpose = description up to the first WHEN:/Use when: trigger list.
function Get-Purpose {
    param([string]$Description)
    if ([string]::IsNullOrWhiteSpace($Description)) { return '' }
    $cut = [regex]::Split($Description, '\s*(?:WHEN:|Use when:)', 'IgnoreCase')[0]
    return $cut.Trim()
}

# --- folder layout ----------------------------------------------------------
$topFolders = foreach ($d in (Get-ChildItem -LiteralPath $RepoPath -Directory -Force |
                              Where-Object { $_.Name -ne '.git' } | Sort-Object Name)) {
    $files = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\\.git\\' }
    [pscustomobject]@{
        name      = $d.Name
        files     = @($files).Count
        subfolders = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -notmatch '\\\.git\\' }).Count
    }
}

# --- file-type breakdown ----------------------------------------------------
$allFiles = Get-ChildItem -LiteralPath $RepoPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.git\\' }
$fileTypes = $allFiles | Group-Object { if ($_.Extension) { $_.Extension.ToLower() } else { '(none)' } } |
             Sort-Object Count -Descending |
             ForEach-Object { [pscustomobject]@{ ext = $_.Name; count = $_.Count } }

# --- skills catalog ---------------------------------------------------------
$skillsDir = Join-Path $RepoPath '.github\skills'
$skills = @()
if (Test-Path -LiteralPath $skillsDir) {
    $skills = foreach ($s in (Get-ChildItem -LiteralPath $skillsDir -Directory | Sort-Object Name)) {
        $md = Join-Path $s.FullName 'SKILL.md'
        $fm = if (Test-Path -LiteralPath $md) { Get-Frontmatter $md } else { [ordered]@{} }
        [pscustomobject]@{
            name    = if ($fm.name) { $fm.name } else { $s.Name }
            purpose = Get-Purpose $fm.description
        }
    }
}

# --- agents catalog ---------------------------------------------------------
$agentsDir = Join-Path $RepoPath '.github\agents'
$agents = @()
if (Test-Path -LiteralPath $agentsDir) {
    $agents = foreach ($a in (Get-ChildItem -LiteralPath $agentsDir -Filter '*.agent.md' | Sort-Object Name)) {
        $fm = Get-Frontmatter $a.FullName
        [pscustomobject]@{
            name    = if ($fm.name) { $fm.name } else { $a.Name -replace '\.agent\.md$', '' }
            purpose = Get-Purpose $fm.description
        }
    }
}

# --- recent git activity ----------------------------------------------------
$branch = $null
$recent = @()
Push-Location $RepoPath
try {
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    $log = git --no-pager log -n $Commits --pretty=format:'%h%x1f%ad%x1f%an%x1f%s' --date=short 2>$null
    foreach ($l in $log) {
        $p = $l -split "`u{001f}"
        if ($p.Count -ge 4) {
            $recent += [pscustomobject]@{ hash = $p[0]; date = $p[1]; author = $p[2]; subject = $p[3] }
        }
    }
} finally { Pop-Location }

$report = [ordered]@{
    repo        = $RepoPath
    generated   = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    branch      = $branch
    totalFiles  = @($allFiles).Count
    folders     = $topFolders
    fileTypes   = $fileTypes
    skills      = $skills
    agents      = $agents
    recentCommits = $recent
}

if ($Json) {
    $report | ConvertTo-Json -Depth 6
    return
}

# --- formatted text ---------------------------------------------------------
Write-Host ""
Write-Host "FDE_Revenue_Bedrock — repo inventory" -ForegroundColor Cyan
Write-Host ("{0}   branch: {1}   files: {2}   ({3})" -f $RepoPath, $branch, $report.totalFiles, $report.generated) -ForegroundColor DarkGray
Write-Host ""

Write-Host "Folder layout" -ForegroundColor Yellow
$topFolders | Format-Table @{n='folder';e={$_.name}}, files, subfolders -AutoSize | Out-String | Write-Host

Write-Host "File types (top 15)" -ForegroundColor Yellow
$fileTypes | Select-Object -First 15 | Format-Table ext, count -AutoSize | Out-String | Write-Host

Write-Host ("Skills ({0})" -f @($skills).Count) -ForegroundColor Yellow
foreach ($s in $skills) { Write-Host ("  - {0}: {1}" -f $s.name, $s.purpose) }
Write-Host ""

Write-Host ("Agents ({0})" -f @($agents).Count) -ForegroundColor Yellow
foreach ($a in $agents) { Write-Host ("  - {0}: {1}" -f $a.name, $a.purpose) }
Write-Host ""

Write-Host ("Recent commits (last {0})" -f $Commits) -ForegroundColor Yellow
$recent | Format-Table hash, date, author, subject -AutoSize | Out-String | Write-Host
