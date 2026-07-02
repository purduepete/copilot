#requires -Version 7.0
<#
.SYNOPSIS
  Resolve "lost" strategy AND asset-type assignments on webportfolio current_positions
  from prior-day daily_snapshot data.

.DESCRIPTION
  current_positions holds @jimb's live holdings and is (re)populated from broker CSV
  uploads, which do NOT carry a strategy or asset type. As a result freshly-uploaded
  positions often land with strategy_id / asset_type_id = NULL ("lost"). The historical
  daily_snapshot table is built FROM current_positions by usp_create_daily_snapshot and
  therefore still carries the correct strategy_id and asset_type_id for the same
  (user, account, symbol) on prior days.

  For every current (is_current = 1, tracked-account) position this helper
  resolves against the most recent PRIOR daily_snapshot for the same
  authenticated_user_id + account_id + symbol:

    * STRATEGY  - backfills strategy_id ONLY when it is currently NULL ("lost").
    * ASSET TYPE - backfills asset_type_id when NULL, AND overwrites it when the current
                   value DISAGREES with the prior snapshot (keeps asset type ALIGNED).

  Strategy and asset type are resolved independently (each from the most recent prior
  snapshot that has a non-null value for that field), so a position can be partly
  resolvable. Positions with no usable prior snapshot are reported as "unresolvable".

  DRY-RUN BY DEFAULT: it only reports the proposed changes and writes/opens a
  self-contained HTML report. Pass -Apply to actually UPDATE current_positions inside a
  single transaction. Matching never crosses users (it joins on authenticated_user_id).

.PARAMETER Apply
  Perform the UPDATEs. Without this switch the script is strictly read-only (proposals).

.PARAMETER MaxSnapshotAgeDays
  Only resolve from snapshots taken within this many days of today. 0 (default) = no
  age limit. Use e.g. 14 to refuse resolving from stale data.

.PARAMETER EnvFile
  Path to the .env with DB_SERVER/DB_NAME/DB_USER/DB_PASSWORD. Default is the
  webportfolio repo's .env.development.local.

.PARAMETER OutDir
  Where to write the HTML report. Default %TEMP%\webportfolio-lost-strategies.

.PARAMETER Json
  Emit a machine-readable summary to stdout; no HTML, no browser.

.PARAMETER NoOpen
  Write the HTML but do not launch the browser.

.EXAMPLE
  # Dry-run: report what WOULD be resolved (opens HTML)
  pwsh -File Resolve-LostStrategies.ps1

.EXAMPLE
  # Read the summary yourself, no HTML/browser
  pwsh -File Resolve-LostStrategies.ps1 -Json -NoOpen

.EXAMPLE
  # Actually apply the resolutions
  pwsh -File Resolve-LostStrategies.ps1 -Apply
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [int]$MaxSnapshotAgeDays = 0,
    [string]$EnvFile = 'C:\Files\Dev\main\webportfolio\.env.development.local',
    [string]$OutDir  = (Join-Path $env:TEMP 'webportfolio-lost-strategies'),
    [switch]$Json,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

# --- load DB credentials from the .env ---------------------------------------
if (-not (Test-Path -LiteralPath $EnvFile)) { throw "Env file not found: $EnvFile" }
$envMap = @{}
foreach ($line in Get-Content -LiteralPath $EnvFile) {
    if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$') {
        $v = $Matches[2].Trim()
        if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $envMap[$Matches[1]] = $v
    }
}
$server = ($envMap['DB_SERVER'] -replace '^https?://','')
$dbName = $envMap['DB_NAME']
$dbUser = $envMap['DB_USER']
$dbPass = $envMap['DB_PASSWORD']
foreach ($k in 'DB_SERVER','DB_NAME','DB_USER','DB_PASSWORD') {
    if (-not $envMap[$k]) { throw "Missing $k in $EnvFile" }
}

$connStr = "Server=$server;Database=$dbName;User ID=$dbUser;Password=$dbPass;" +
           "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

# --- connect ------------------------------------------------------------------
$conn = New-Object System.Data.SqlClient.SqlConnection $connStr
$conn.Open()
function Invoke-Q {
    param([string]$Sql)
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = 180
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dt = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    ,$dt
}

# --- detection + resolution query --------------------------------------------
# For every current position, find the strategy and asset type carried by the most
# recent PRIOR daily_snapshot (each field resolved independently) for the same
# user + account + symbol. Rows are returned when the position is missing a strategy,
# missing an asset type, or its asset type disagrees with the prior snapshot.
$ageFilter = ''
if ($MaxSnapshotAgeDays -gt 0) {
    $ageFilter = "      AND snapshot_date >= DATEADD(day, -$MaxSnapshotAgeDays, CAST(GETDATE() AS date))"
}

$detectSql = @"
;WITH cur AS (
    SELECT cp.id AS position_id, cp.authenticated_user_id, cp.account_id, cp.symbol,
           cp.quantity, cp.strategy_id AS cur_strategy_id, cp.asset_type_id AS cur_asset_type_id
    FROM current_positions cp
    INNER JOIN accounts a ON cp.account_id = a.id
    WHERE cp.is_current = 1
      AND a.is_tracked = 1
), snap_strat AS (
    SELECT authenticated_user_id, account_id, symbol, strategy_id, snapshot_date,
           ROW_NUMBER() OVER (PARTITION BY authenticated_user_id, account_id, symbol
                              ORDER BY snapshot_date DESC, id DESC) AS rn
    FROM daily_snapshot
    WHERE strategy_id IS NOT NULL
      AND snapshot_date < CAST(GETDATE() AS date)
$ageFilter
), snap_asset AS (
    SELECT authenticated_user_id, account_id, symbol, asset_type_id, snapshot_date,
           ROW_NUMBER() OVER (PARTITION BY authenticated_user_id, account_id, symbol
                              ORDER BY snapshot_date DESC, id DESC) AS rn
    FROM daily_snapshot
    WHERE asset_type_id IS NOT NULL
      AND snapshot_date < CAST(GETDATE() AS date)
$ageFilter
)
SELECT cur.position_id                              AS [Position Id],
       cur.authenticated_user_id                    AS [User Id],
       cur.account_id                               AS [Account Id],
       a.account_name                               AS [Account],
       cur.symbol                                   AS [Symbol],
       cur.quantity                                 AS [Quantity],
       cur.cur_strategy_id                          AS [Cur Strategy Id],
       ss.strategy_id                               AS [Prior Strategy Id],
       strat.strategy_name                          AS [Prior Strategy],
       CONVERT(varchar(10), ss.snapshot_date, 23)   AS [Strategy From],
       cur.cur_asset_type_id                        AS [Cur Asset Type Id],
       curat.asset_type_name                        AS [Cur Asset Type],
       sa.asset_type_id                             AS [Prior Asset Type Id],
       priorat.asset_type_name                      AS [Prior Asset Type],
       CONVERT(varchar(10), sa.snapshot_date, 23)   AS [Asset From]
FROM cur
LEFT JOIN (SELECT * FROM snap_strat WHERE rn = 1) ss
       ON ss.authenticated_user_id = cur.authenticated_user_id
      AND ss.account_id            = cur.account_id
      AND ss.symbol                = cur.symbol
LEFT JOIN (SELECT * FROM snap_asset WHERE rn = 1) sa
       ON sa.authenticated_user_id = cur.authenticated_user_id
      AND sa.account_id            = cur.account_id
      AND sa.symbol                = cur.symbol
LEFT JOIN strategies strat ON strat.id = ss.strategy_id
LEFT JOIN asset_types curat  ON curat.id  = cur.cur_asset_type_id AND curat.authenticated_user_id  = cur.authenticated_user_id
LEFT JOIN asset_types priorat ON priorat.id = sa.asset_type_id    AND priorat.authenticated_user_id = cur.authenticated_user_id
LEFT JOIN accounts a ON a.id = cur.account_id
WHERE cur.cur_strategy_id IS NULL
   OR cur.cur_asset_type_id IS NULL
   OR (sa.asset_type_id IS NOT NULL AND cur.cur_asset_type_id <> sa.asset_type_id)
ORDER BY a.account_name, cur.symbol;
"@

$dt = Invoke-Q $detectSql

# --- classify each row --------------------------------------------------------
function IsNull($v){ $v -eq $null -or $v -eq [DBNull]::Value }

$rows = foreach ($r in $dt.Rows) {
    $curStrat  = if (IsNull $r['Cur Strategy Id'])   { $null } else { [int]$r['Cur Strategy Id'] }
    $priStratId= if (IsNull $r['Prior Strategy Id']) { $null } else { [int]$r['Prior Strategy Id'] }
    $curAsset  = if (IsNull $r['Cur Asset Type Id']) { $null } else { [int]$r['Cur Asset Type Id'] }
    $priAssetId= if (IsNull $r['Prior Asset Type Id']){ $null } else { [int]$r['Prior Asset Type Id'] }

    # STRATEGY: backfill only (position lost its strategy).
    $setStrategy = ($null -eq $curStrat) -and ($null -ne $priStratId)
    $needStrategyUnmet = ($null -eq $curStrat) -and ($null -eq $priStratId)

    # ASSET TYPE: backfill NULLs AND overwrite disagreements to keep it aligned.
    $assetNeedsChange = ($null -eq $curAsset) -or (($null -ne $curAsset) -and ($null -ne $priAssetId) -and ($curAsset -ne $priAssetId))
    $setAsset = $assetNeedsChange -and ($null -ne $priAssetId)
    $needAssetUnmet = ($null -eq $curAsset) -and ($null -eq $priAssetId)

    [pscustomobject]@{
        Row               = $r
        PositionId        = [long]$r['Position Id']
        Account           = [string]$r['Account']
        Symbol            = [string]$r['Symbol']
        Quantity          = if (IsNull $r['Quantity']) { $null } else { [double]$r['Quantity'] }
        CurStrategy       = if (IsNull $r['Prior Strategy'] -and $null -eq $curStrat) { $null } else { $curStrat }
        SetStrategy       = $setStrategy
        PriorStrategyId   = $priStratId
        PriorStrategy     = if (IsNull $r['Prior Strategy']) { $null } else { [string]$r['Prior Strategy'] }
        StrategyFrom      = if (IsNull $r['Strategy From']) { $null } else { [string]$r['Strategy From'] }
        NeedStrategyUnmet = $needStrategyUnmet
        SetAsset          = $setAsset
        CurAssetId        = $curAsset
        CurAsset          = if (IsNull $r['Cur Asset Type']) { $null } else { [string]$r['Cur Asset Type'] }
        PriorAssetId      = $priAssetId
        PriorAsset        = if (IsNull $r['Prior Asset Type']) { $null } else { [string]$r['Prior Asset Type'] }
        AssetFrom         = if (IsNull $r['Asset From']) { $null } else { [string]$r['Asset From'] }
        NeedAssetUnmet    = $needAssetUnmet
        AssetOverwrite    = $setAsset -and ($null -ne $curAsset)
    }
}
$rows = @($rows)

$actionable   = @($rows | Where-Object { $_.SetStrategy -or $_.SetAsset })
$unresolvable = @($rows | Where-Object { -not ($_.SetStrategy -or $_.SetAsset) })

$totalInScope     = $rows.Count
$strategyBackfills= @($rows | Where-Object { $_.SetStrategy }).Count
$assetBackfills   = @($rows | Where-Object { $_.SetAsset -and -not $_.AssetOverwrite }).Count
$assetOverwrites  = @($rows | Where-Object { $_.AssetOverwrite }).Count
$appliedCount     = 0

# --- apply (optional) ---------------------------------------------------------
if ($Apply -and $actionable.Count -gt 0) {
    $tx = $conn.BeginTransaction()
    try {
        foreach ($x in $actionable) {
            $sets = @()
            $cmd = $conn.CreateCommand()
            $cmd.Transaction = $tx
            if ($x.SetStrategy) {
                $sets += 'strategy_id = @sid'
                $ps = $cmd.Parameters.Add('@sid', [System.Data.SqlDbType]::Int); $ps.Value = [int]$x.PriorStrategyId
            }
            if ($x.SetAsset) {
                $sets += 'asset_type_id = @aid'
                $pa = $cmd.Parameters.Add('@aid', [System.Data.SqlDbType]::Int); $pa.Value = [int]$x.PriorAssetId
            }
            $sets += 'date_updated = GETUTCDATE()'
            # Guard: only backfill strategy where still NULL; asset may be overwritten.
            $strategyGuard = if ($x.SetStrategy) { ' AND strategy_id IS NULL' } else { '' }
            $cmd.CommandText = "UPDATE current_positions SET $($sets -join ', ') WHERE id = @pid AND is_current = 1$strategyGuard;"
            $pp = $cmd.Parameters.Add('@pid', [System.Data.SqlDbType]::BigInt); $pp.Value = [long]$x.PositionId
            $appliedCount += $cmd.ExecuteNonQuery()
        }
        $tx.Commit()
    } catch {
        $tx.Rollback(); $conn.Close(); throw
    }
}
$conn.Close()

# --- change-description helpers ----------------------------------------------
function ChangeHtml($fromText, $toText, $isNone, $tag) {
    $wasCls = if ($isNone) { 'was none' } else { 'was' }
    "<span class='chg'><span class='$wasCls'>$(Enc $fromText)</span>" +
    "<span class='arr'>&rarr;</span><span class='now'>$(Enc $toText)</span>$tag</span>"
}
function NoPrior() {
    "<span class='chg'><span class='was none'>unset</span>" +
    "<span class='arr'>&rarr;</span><span class='miss'>no prior data</span></span>"
}
function StrategyChange($x) {
    if     ($x.SetStrategy)       { ChangeHtml 'unset' $x.PriorStrategy $true '' }
    elseif ($x.NeedStrategyUnmet) { NoPrior }
    else                          { "<span class='nochg'>&mdash;</span>" }
}
function AssetChange($x) {
    if ($x.SetAsset) {
        $tag    = if ($x.AssetOverwrite) { " <span class='tag'>overwrite</span>" } else { '' }
        $isNone = ($null -eq $x.CurAsset)
        $from   = if ($isNone) { 'unset' } else { $x.CurAsset }
        ChangeHtml $from $x.PriorAsset $isNone $tag
    }
    elseif ($x.NeedAssetUnmet) { NoPrior }
    else                       { "<span class='nochg'>&mdash;</span>" }
}

# --- JSON shortcut ------------------------------------------------------------
if ($Json) {
    $toObj = {
        param($x)
        [pscustomobject]@{
            positionId    = $x.PositionId
            account       = $x.Account
            symbol        = $x.Symbol
            quantity      = $x.Quantity
            setStrategy   = $x.SetStrategy
            priorStrategy = $x.PriorStrategy
            strategyFrom  = $x.StrategyFrom
            setAssetType  = $x.SetAsset
            assetOverwrite= $x.AssetOverwrite
            curAssetType  = $x.CurAsset
            priorAssetType= $x.PriorAsset
            assetFrom     = $x.AssetFrom
        }
    }
    [pscustomobject]@{
        generated         = (Get-Date).ToString('s')
        applied           = [bool]$Apply
        maxSnapshotAgeDays= $MaxSnapshotAgeDays
        totalInScope      = $totalInScope
        actionable        = $actionable.Count
        unresolvable      = $unresolvable.Count
        strategyBackfills = $strategyBackfills
        assetBackfills    = $assetBackfills
        assetOverwrites   = $assetOverwrites
        rowsUpdated       = $appliedCount
        actionableRows    = @($actionable   | ForEach-Object { & $toObj $_ })
        unresolvableRows  = @($unresolvable | ForEach-Object { & $toObj $_ })
    } | ConvertTo-Json -Depth 5
    return
}

# --- HTML rendering -----------------------------------------------------------
function Enc([object]$s){ [System.Net.WebUtility]::HtmlEncode([string]$s) }

function Render-Actionable {
    param([object[]]$Rows)
    if ($Rows.Count -eq 0) { return "<p class='ok'>&#10003; None.</p>" }
    $body = foreach ($x in $Rows) {
        $from = @($x.StrategyFrom, $x.AssetFrom | Where-Object { $_ } | Select-Object -Unique) -join ', '
        "<tr><td>$(Enc $x.Account)</td><td>$(Enc $x.Symbol)</td>" +
        "<td>$(StrategyChange $x)</td>" +
        "<td>$(AssetChange $x)</td><td>$(Enc $from)</td>" +
        "<td class='num'>$($x.PositionId)</td></tr>"
    }
    "<table><thead><tr><th>Account</th><th>Symbol</th>" +
    "<th>Strategy</th><th>Asset Type</th><th>From Snapshot</th><th class='num'>Position Id</th></tr></thead>" +
    "<tbody>$($body -join "`n")</tbody></table>"
}

function Render-Unresolvable {
    param([object[]]$Rows)
    if ($Rows.Count -eq 0) { return "<p class='ok'>&#10003; None.</p>" }
    $body = foreach ($x in $Rows) {
        $miss = @()
        if ($x.NeedStrategyUnmet) { $miss += 'strategy' }
        if ($x.NeedAssetUnmet)    { $miss += 'asset type' }
        "<tr><td>$(Enc $x.Account)</td><td>$(Enc $x.Symbol)</td>" +
        "<td>$(Enc ($miss -join ', '))</td>" +
        "<td class='num'>$($x.PositionId)</td></tr>"
    }
    "<table><thead><tr><th>Account</th><th>Symbol</th>" +
    "<th>Still missing</th><th class='num'>Position Id</th></tr></thead>" +
    "<tbody>$($body -join "`n")</tbody></table>"
}

$gen  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$mode = if ($Apply) { "APPLIED &mdash; $appliedCount position(s) updated" } else { 'Dry-run (report only)' }
$modeClass = if ($Apply) { 'sev-applied' } else { 'sev-dry' }
$ageNote = if ($MaxSnapshotAgeDays -gt 0) { " &middot; snapshots within $MaxSnapshotAgeDays day(s)" } else { '' }

$html = @"
<!doctype html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>WebPortfolio - Resolve Lost Strategies &amp; Asset Types</title>
<style>
  :root{ --bg:#f5f5fb; --card:#fff; --ink:#1a1a2e; --muted:#6b6b80; --line:#e3e3ee;
         --accent:#5b5bd6; --accent2:#8b5cf6;
         --high:#c0362c; --highBg:#fdeceb; --med:#b4530a; --medBg:#fff1e6;
         --info:#3457b8; --infoBg:#e9eefb; --ok:#1f7a4d; --okBg:#e7f6ee; }
  @media (prefers-color-scheme:dark){
    :root{ --bg:#14141c; --card:#1d1d28; --ink:#ececf5; --muted:#9a9ab0; --line:#2c2c3a;
           --accent:#b3b8ff; --accent2:#c4b5fd;
           --high:#ff8a80; --highBg:#3a1512; --med:#ffb277; --medBg:#3a2410;
           --info:#9db4f5; --infoBg:#171f38; --ok:#7fe0ab; --okBg:#10301f; } }
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);
    font:15px/1.55 'Segoe UI',system-ui,sans-serif;padding:28px 32px}
  h1{font-size:23px;margin:0 0 2px} .sub{color:var(--muted);margin:0 0 20px;font-size:13px}
  .cards{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:26px}
  .c{background:var(--card);border:1px solid var(--line);padding:14px 18px;min-width:130px}
  .c .n{font-size:28px;font-weight:700;line-height:1} .c .l{color:var(--muted);font-size:12px;
    text-transform:uppercase;letter-spacing:.04em;margin-top:4px}
  .c.accent{border-top:3px solid var(--accent)}
  .c.ok{border-top:3px solid var(--ok)} .c.med{border-top:3px solid var(--med)}
  section{background:var(--card);border:1px solid var(--line);padding:16px 20px;margin-bottom:16px}
  h2{font-size:16px;margin:0 0 6px;display:flex;align-items:center;gap:10px;flex-wrap:wrap}
  .cnt{margin-left:auto;color:var(--muted);font-size:12.5px;font-weight:400}
  .desc{color:var(--muted);font-size:13px;margin:0 0 12px;max-width:900px}
  table{width:100%;border-collapse:collapse;border:1px solid var(--line);font-size:13.5px}
  th,td{padding:8px 12px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
  th{font-size:11.5px;text-transform:uppercase;letter-spacing:.03em;color:var(--muted)}
  td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
  tbody tr:hover{background:rgba(127,127,150,.06)}
  .pill{display:inline-block;padding:2px 9px;font-size:11px;font-weight:700;letter-spacing:.03em}
  .pill.sev-applied{background:var(--okBg);color:var(--ok)}
  .pill.sev-dry{background:var(--infoBg);color:var(--info)}
  .tag{display:inline-block;padding:0 6px;font-size:10.5px;font-weight:700;background:var(--medBg);color:var(--med)}
  .chg .was{color:var(--muted)} .chg .none{font-style:italic;opacity:.8}
  .chg .arr{color:var(--muted);padding:0 8px}
  .chg .now{font-weight:600;color:var(--accent)}
  .chg .miss{color:var(--med);font-style:italic}
  .nochg{color:var(--muted)}
  .ok{color:var(--ok);font-size:13px;margin:6px 0 0}
  .note{margin-top:20px;color:var(--muted);font-size:12.5px;max-width:960px}
  code{background:rgba(127,127,150,.14);padding:1px 6px;font-size:12.5px}
</style></head><body>
  <h1>WebPortfolio &mdash; Resolve Lost Strategies &amp; Asset Types</h1>
  <p class='sub'><span class='pill $modeClass'>$mode</span> &middot; generated $gen$ageNote &middot;
     resolving <code>current_positions</code> from prior-day <code>daily_snapshot</code></p>
  <div class='cards'>
    <div class='c accent'><div class='n'>$totalInScope</div><div class='l'>In scope</div></div>
    <div class='c ok'><div class='n'>$($actionable.Count)</div><div class='l'>Actionable</div></div>
    <div class='c ok'><div class='n'>$strategyBackfills</div><div class='l'>Strategy backfills</div></div>
    <div class='c ok'><div class='n'>$assetBackfills</div><div class='l'>Asset backfills</div></div>
    <div class='c med'><div class='n'>$assetOverwrites</div><div class='l'>Asset overwrites</div></div>
    <div class='c med'><div class='n'>$($unresolvable.Count)</div><div class='l'>Unresolvable</div></div>
  </div>
  <section>
    <h2>Actionable resolutions
      <span class='cnt'>$($actionable.Count) position(s)$(if($Apply){" &middot; $appliedCount updated"})</span></h2>
    <p class='desc'>Strategy is backfilled only when currently missing; asset type is backfilled when missing
      <strong>and overwritten when it disagrees</strong> with the prior snapshot (kept aligned).
      $(if($Apply){'These changes have been written to <code>current_positions</code>.'}else{'Re-run with <code>-Apply</code> to write these changes.'})</p>
    $(Render-Actionable -Rows $actionable)
  </section>
  <section>
    <h2>Unresolvable (no prior snapshot) <span class='cnt'>$($unresolvable.Count) position(s)</span></h2>
    <p class='desc'>These positions are missing a strategy and/or asset type but have no prior
      <code>daily_snapshot</code> value to inherit &mdash; assign manually in the app.</p>
    $(Render-Unresolvable -Rows $unresolvable)
  </section>
  <p class='note'><strong>How it works:</strong> <code>daily_snapshot</code> is generated FROM
  <code>current_positions</code> by <code>usp_create_daily_snapshot</code>, so a prior day's snapshot still
  holds the strategy and asset type that a freshly re-uploaded position lost or changed. Strategy and asset
  type are each taken from the most recent prior snapshot that has a non-null value; matching never crosses
  users. $(if($Apply){'This run wrote to the database.'}else{'This run was read-only &mdash; nothing was changed.'})</p>
</body></html>
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp    = (Get-Date).ToString('yyyyMMdd-HHmmss')
$htmlPath = Join-Path $OutDir "lost-strategies-$stamp.html"
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

Write-Host ("Resolve lost strategies & asset types ({0}):" -f $(if($Apply){'APPLY'}else{'dry-run'})) -ForegroundColor Cyan
Write-Host ("  {0} in scope, {1} actionable, {2} unresolvable" -f $totalInScope, $actionable.Count, $unresolvable.Count)
Write-Host ("  strategy backfills: {0}  asset backfills: {1}  asset overwrites: {2}" -f $strategyBackfills, $assetBackfills, $assetOverwrites)
if ($Apply) { Write-Host ("  {0} position(s) updated" -f $appliedCount) -ForegroundColor Green }
Write-Host "Wrote $htmlPath" -ForegroundColor Green
if (-not $NoOpen) { Start-Process $htmlPath }
