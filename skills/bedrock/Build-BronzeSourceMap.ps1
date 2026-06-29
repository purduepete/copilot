#requires -Version 7.0
<#
.SYNOPSIS
  Consolidated BRONZE source map / provisioning checklist for FDE_Revenue_Bedrock.

.DESCRIPTION
  Reads every analysed solution's repo_inventory_io.csv under
  docs/exploratory/data-estate-analysis/solution/* and distils the genuine
  UPSTREAM EXTERNAL inputs (type=input, external_internal=external) into a single
  bronze provisioning picture:

    * one row per upstream SOURCE SYSTEM (the io `upstream` column)
    * which solutions consume it (arr / wcs / mwdetail / ...)
    * reference weight (sum of the io `dependency` counts)
    * the real STORAGE ACCOUNT(s) resolved from any abfss:// path aliases
    * a provisioning method flag: 'shortcut' (zero-copy, default) vs
      'data copy (PME/elevated)' for tenants where shortcuts aren't permitted,
      with 'review' where it can't be determined automatically

  Emits a consolidated CSV (path grain) + a visual self-contained HTML checklist,
  and (by default) opens the HTML. Nothing is written into the bedrock repo.

  PME / elevated classification is a HEURISTIC (account name contains pme/spme, or
  is an elevated tenant such as msit-onelake) and is marked for human confirmation.

.PARAMETER RepoPath
  bedrock repo clone. Default C:\Files\Dev\msft\FDE_Revenue_Bedrock.

.PARAMETER OutDir
  Where to write bronze-source-map.html / .csv. Default: this session's working
  area under the user's temp (never the confidential repo).

.PARAMETER Json
  Emit the consolidated system list as JSON to stdout (no files, no browser).

.PARAMETER NoOpen
  Write the files but don't launch the browser.

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\bedrock\Build-BronzeSourceMap.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoPath = 'C:\Files\Dev\msft\FDE_Revenue_Bedrock',
    [string]$OutDir   = (Join-Path $env:TEMP 'bedrock-bronze-source-map'),
    [switch]$Json,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

$solDir = Join-Path $RepoPath 'docs\exploratory\data-estate-analysis\solution'
if (-not (Test-Path -LiteralPath $solDir)) { throw "Solution analyses not found: $solDir" }

$ioFiles = Get-ChildItem -LiteralPath $solDir -Recurse -Filter 'repo_inventory_io.csv'
if (-not $ioFiles) { throw "No repo_inventory_io.csv files under $solDir" }

# --- classify a storage account / system into a provisioning method -----------
function Get-Method {
    param([string[]]$Accounts, [string]$System)
    $blob = (($Accounts -join ' ') + ' ' + $System).ToLower()
    if ($blob -match 'pme|spme')              { return 'data copy (PME/elevated)' }
    if ($blob -match 'msit-onelake|\bmsit\b') { return 'data copy (PME/elevated)' }
    if ($blob -match 'cseoedl|cseo')          { return 'review (cross-tenant?)' }
    if ($Accounts.Count -eq 0)                { return 'review (no path resolved)' }
    return 'shortcut'
}

# --- gather external upstream inputs -----------------------------------------
$pathRows = [System.Collections.Generic.List[object]]::new()
foreach ($f in $ioFiles) {
    $solution = $f.Directory.Name
    foreach ($row in (Import-Csv -LiteralPath $f.FullName)) {
        if ($row.type -ne 'input' -or $row.external_internal -ne 'external') { continue }
        $aliases = @()
        if ($row.path_aliases) { $aliases = ($row.path_aliases -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
        if (-not $aliases) { $aliases = @($row.name) }
        foreach ($p in $aliases) {
            $acct = $null
            $acctHost = $null
            if ($p -match 'abfss://[^@/]+@([^/]+)') { $acctHost = $Matches[1] }   # container@account
            elseif ($p -match 'abfss://([^/]+)')    { $acctHost = $Matches[1] }   # account-only
            if ($acctHost) {
                $acctHost = $acctHost -replace '\.dfs\.core\.windows\.net.*$',''  # strip ADLS suffix
                # config tokens ($var, {var}, redacted, region placeholders) are not resolved accounts
                if ($acctHost -notmatch '[\${}]' -and $acctHost -notmatch 'redacted' -and $acctHost) { $acct = $acctHost }
            }
            $dep = 0; [int]::TryParse($row.dependency, [ref]$dep) | Out-Null
            $pathRows.Add([pscustomobject]@{
                solution = $solution
                system   = $row.upstream
                name     = $row.name
                path     = $p
                account  = $acct
                refs     = $dep
            })
        }
    }
}

# --- roll up to one row per source SYSTEM ------------------------------------
$systems = foreach ($g in ($pathRows | Group-Object system | Sort-Object Name)) {
    $accts = @($g.Group | Where-Object { $_.account } | Select-Object -ExpandProperty account -Unique | Sort-Object)
    $sols  = @($g.Group | Select-Object -ExpandProperty solution -Unique | Sort-Object)
    $refs  = ($g.Group | Measure-Object refs -Sum).Sum
    [pscustomobject]@{
        system    = $g.Name
        solutions = $sols
        refs      = [int]$refs
        accounts  = $accts
        method    = (Get-Method -Accounts $accts -System $g.Name)
    }
}
$systems = $systems | Sort-Object @{e={ switch -regex ($_.method) {'^data copy'{0}'^review'{1}default{2}} }}, @{e='refs';Descending=$true}

# --- JSON shortcut ------------------------------------------------------------
if ($Json) {
    $systems | Select-Object system, @{n='solutions';e={$_.solutions -join ','}}, refs,
        @{n='accounts';e={$_.accounts -join ','}}, method | ConvertTo-Json -Depth 4
    return
}

# --- write outputs ------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$csvPath  = Join-Path $OutDir 'bronze-source-map.csv'
$htmlPath = Join-Path $OutDir 'bronze-source-map.html'

$pathRows | Sort-Object system, solution, path |
    Select-Object system, solution, name, account, refs, path |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation

$gen = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$nSys  = @($systems).Count
$nCopy = @($systems | Where-Object { $_.method -like 'data copy*' }).Count
$nShort= @($systems | Where-Object { $_.method -eq 'shortcut' }).Count
$nRev  = @($systems | Where-Object { $_.method -like 'review*' }).Count
$nSol  = @($pathRows | Select-Object -ExpandProperty solution -Unique).Count

function Enc([string]$s){ [System.Net.WebUtility]::HtmlEncode($s) }
function MethodClass([string]$m){ if($m -like 'data copy*'){'m-copy'}elseif($m -like 'review*'){'m-review'}else{'m-short'} }

$rows = foreach ($s in $systems) {
    $solBadges = ($s.solutions | ForEach-Object { "<span class='badge'>$(Enc $_)</span>" }) -join ' '
    $acctList  = if ($s.accounts) { ($s.accounts | ForEach-Object { "<code>$(Enc $_)</code>" }) -join '<br>' } else { "<span class='muted'>token only — not resolved</span>" }
    @"
        <tr class='$(MethodClass $s.method)'>
          <td class='sys'>$(Enc $s.system)</td>
          <td>$solBadges</td>
          <td class='num'>$($s.refs)</td>
          <td>$acctList</td>
          <td><span class='pill $(MethodClass $s.method)'>$(Enc $s.method)</span></td>
        </tr>
"@
}

$html = @"
<!doctype html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Bedrock — Bronze Source Map</title>
<style>
  :root{ --bg:#f7f7fb; --card:#fff; --ink:#1a1a2e; --muted:#6b6b80; --line:#e3e3ee;
         --accent:#5b5bd6; --accent2:#8b5cf6; --copy:#b4530a; --copyBg:#fff1e6;
         --short:#1f7a4d; --shortBg:#e7f6ee; --review:#8a6d00; --reviewBg:#fbf4d9; }
  @media (prefers-color-scheme:dark){
    :root{ --bg:#14141c; --card:#1d1d28; --ink:#ececf5; --muted:#9a9ab0; --line:#2c2c3a;
           --copy:#ffb277; --copyBg:#3a2410; --short:#7fe0ab; --shortBg:#10301f;
           --review:#f0d469; --reviewBg:#332b0a; } }
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);
    font:15px/1.5 'Segoe UI',system-ui,sans-serif;padding:28px}
  h1{font-size:22px;margin:0 0 2px} .sub{color:var(--muted);margin:0 0 20px;font-size:13px}
  .cards{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:22px}
  .c{background:var(--card);border:1px solid var(--line);padding:14px 18px;min-width:130px}
  .c .n{font-size:26px;font-weight:700} .c .l{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}
  .c.accent{border-top:3px solid var(--accent)}
  table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line)}
  th,td{padding:10px 14px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
  th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);background:transparent}
  td.num,th.num{text-align:right} td.sys{font-weight:600}
  code{background:rgba(127,127,150,.14);padding:1px 6px;font-size:12.5px}
  .badge{display:inline-block;background:rgba(91,91,214,.14);color:var(--accent);
    padding:1px 8px;font-size:12px;margin:1px 0}
  .muted{color:var(--muted);font-size:12px}
  .pill{display:inline-block;padding:3px 10px;font-size:12px;font-weight:600;white-space:nowrap}
  .pill.m-copy{background:var(--copyBg);color:var(--copy)}
  .pill.m-short{background:var(--shortBg);color:var(--short)}
  .pill.m-review{background:var(--reviewBg);color:var(--review)}
  tr.m-copy td.sys{border-left:3px solid var(--copy)}
  tr.m-short td.sys{border-left:3px solid var(--short)}
  tr.m-review td.sys{border-left:3px solid var(--review)}
  .note{margin-top:18px;color:var(--muted);font-size:12.5px;max-width:900px}
</style></head><body>
  <h1>Bedrock — Bronze Source Map &amp; Provisioning Checklist</h1>
  <p class='sub'>Distilled from $nSol analysed solution(s) · generated $gen · upstream EXTERNAL inputs only</p>
  <div class='cards'>
    <div class='c accent'><div class='n'>$nSys</div><div class='l'>Source systems</div></div>
    <div class='c'><div class='n'>$nShort</div><div class='l'>Shortcut-able</div></div>
    <div class='c'><div class='n'>$nCopy</div><div class='l'>PME / elevated copy</div></div>
    <div class='c'><div class='n'>$nRev</div><div class='l'>Needs review</div></div>
  </div>
  <table>
    <thead><tr><th>Source system</th><th>Used by</th><th class='num'>Refs</th>
      <th>Storage account(s)</th><th>Bronze method</th></tr></thead>
    <tbody>
$($rows -join "`n")
    </tbody>
  </table>
  <p class='note'><strong>How to read:</strong> each row is an upstream source that
  Bronze must land (one OneLake <em>shortcut</em> per source by default; a scheduled
  <em>data copy</em> where shortcuts aren't permitted). <strong>Refs</strong> = how
  heavily it's used across the analysed solutions (a sizing hint for what to onboard
  first). <strong>PME/elevated</strong> flags are a heuristic (account contains
  pme/spme or is an elevated tenant like msit-onelake) and must be confirmed.
  &lsquo;token only&rsquo; means the analysis recorded a config alias, not a physical
  abfss path — resolve it in the source repo before provisioning. Full path-grain
  detail is in <code>bronze-source-map.csv</code>.</p>
</body></html>
"@

Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

Write-Host "Wrote $htmlPath" -ForegroundColor Green
Write-Host "Wrote $csvPath  ($($pathRows.Count) path rows, $nSys systems)" -ForegroundColor Green
if (-not $NoOpen) { Start-Process $htmlPath }

