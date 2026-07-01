#requires -Version 7.0
<#
.SYNOPSIS
  Strategy-alignment audit for @jimb's webportfolio investment database.

.DESCRIPTION
  Compares how `strategy_id` is assigned across the three strategy-bearing tables
  in the webportfolio Azure SQL database and surfaces discrepancies:

    * transactions          (stock transactions        -> strategy_id)
    * option_transactions   (option trades             -> strategy_id)
    * daily_snapshot        (per-day position holdings  -> strategy_id)
  ...validated against the `strategies` reference table (is_stock_strategy /
  is_option_strategy type flags) and `daily_snapshot.asset_type_id`.

  Checks performed (each scoped to the chosen timeframe):
    HIGH   C1  Snapshot OPTION positions carrying a strategy that is NOT flagged
               is_option_strategy (type-flag mismatch).
    HIGH   C2  Asset-type misclassification: an option-format symbol (-XXX...) not
               typed Option, or a non-option symbol typed Option.
    HIGH   C6  Referential integrity: strategy_id that is orphaned or belongs to a
               different user, in any of the three tables.
    MEDIUM C3  Stock cross-table disagreement: latest transaction strategy vs the
               latest snapshot strategy for the same (account, symbol).
    MEDIUM C5  Option cross-table disagreement: option_transactions strategy vs the
               matching daily_snapshot option row's strategy (matched on
               underlying + expiration + strike).
    MEDIUM C4  transactions assigning MULTIPLE distinct strategies to the same
               (account, symbol).
    INFO   C7  Transactions with NO strategy assigned (gap), by assignment method.

  Renders a self-contained HTML report (light/dark) and opens it by default.

  READ-ONLY. The script issues only SELECTs; it never writes to the database.

.PARAMETER Months
  Size of the look-back window in months. Default 3 ("the last 3 months").
  Ignored if -Since is supplied. Use -AllTime for no lower bound.

.PARAMETER Since
  Explicit window start (any datetime string, e.g. '2026-01-01'). Overrides -Months.

.PARAMETER AllTime
  Audit the full history (no lower date bound).

.PARAMETER EnvFile
  Path to the .env file with DB_SERVER/DB_NAME/DB_USER/DB_PASSWORD. Default is the
  webportfolio repo's .env.development.local.

.PARAMETER OutDir
  Where to write the HTML report. Default %TEMP%\webportfolio-strategy-audit.

.PARAMETER Json
  Emit a machine-readable summary (per-check counts) to stdout; no HTML, no browser.

.PARAMETER NoOpen
  Write the HTML but do not launch the browser.

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Invoke-StrategyAudit.ps1 -Months 3

.EXAMPLE
  pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Invoke-StrategyAudit.ps1 -Since 2026-01-01 -Json
#>
[CmdletBinding()]
param(
    [int]$Months = 3,
    [string]$Since,
    [switch]$AllTime,
    [string]$EnvFile = 'C:\Files\Dev\main\webportfolio\.env.development.local',
    [string]$OutDir  = (Join-Path $env:TEMP 'webportfolio-strategy-audit'),
    [switch]$Json,
    [switch]$NoOpen,
    [switch]$IncludeAccepted
)

$ErrorActionPreference = 'Stop'

# --- accepted (known-good) exceptions ----------------------------------------
# Findings the user has reviewed and deemed acceptable. Each entry is matched
# against a check's result rows by ALL of its column=value pairs (case-insensitive,
# trimmed). Matching rows are suppressed from Findings/Impact and the report
# unless -IncludeAccepted is passed. Keyed by check Id.
$AcceptedExceptions = @{
    C3 = @(
        # BRKB (account 7): transaction strategy vs snapshot strategy disagree on
        # purpose. Reviewed 2026-07-01 and confirmed acceptable.
        @{ Account = '7'; Symbol = 'BRKB' }
    )
}

# --- accepted unassigned (C7) -------------------------------------------------
# (account, symbol) pairs whose *unassigned-strategy* transactions are known-good
# and should be excluded from the C7 "no strategy assigned" check (e.g. a bond with
# no equity holding to inherit from). Suppressed unless -IncludeAccepted; the count
# of suppressed rows is reported as C7's `accepted`.
$AcceptedUnassigned = @(
    # CUSIP 123990BL6 in account 10: monthly Interest Income, no reference holding
    # to inherit a strategy from. Reviewed 2026-07-01 - intentionally left unassigned.
    @{ Account = '10'; Symbol = '123990BL6' }
)

# SQL predicate that removes the accepted-unassigned rows from C7 (empty when the
# user passes -IncludeAccepted or the list is empty).
$c7ExcludeSql = ''
if (-not $IncludeAccepted -and $AcceptedUnassigned.Count -gt 0) {
    $c7ExcludeSql = ($AcceptedUnassigned | ForEach-Object {
        "  AND NOT (account_id = '$($_.Account)' AND symbol = '$($_.Symbol)')"
    }) -join "`n"
}

# --- resolve the timeframe ----------------------------------------------------
if ($AllTime) {
    $sinceDate  = [datetime]'1900-01-01'
    $windowLabel = 'All time'
} elseif ($Since) {
    $sinceDate  = [datetime]::Parse($Since)
    $windowLabel = "Since $($sinceDate.ToString('yyyy-MM-dd'))"
} else {
    $sinceDate  = (Get-Date).Date.AddMonths(-$Months)
    $windowLabel = "Last $Months month$(if($Months -ne 1){'s'}) (since $($sinceDate.ToString('yyyy-MM-dd')))"
}

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

# --- query helper -------------------------------------------------------------
$conn = New-Object System.Data.SqlClient.SqlConnection $connStr
$conn.Open()
function Invoke-Q {
    param([string]$Sql)
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = 180
    $p = $cmd.Parameters.Add('@since', [System.Data.SqlDbType]::DateTime)
    $p.Value = $sinceDate
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dt = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    ,$dt
}

# --- the checks ---------------------------------------------------------------
# Each: Id, Title, Severity (HIGH/MEDIUM/INFO), Counts (does it count toward the
# discrepancy total?), Desc, Sql.
$checks = [System.Collections.Generic.List[object]]::new()

$checks.Add([pscustomobject]@{ Id='C1'; Severity='HIGH'; Counts=$true
  Title='Snapshot option positions on a non-option strategy'
  Desc='daily_snapshot rows whose symbol is an option (-XXX...) but whose strategy is NOT flagged is_option_strategy. Usually means the strategy''s type flags are wrong, or the wrong strategy was assigned.'
  Sql=@'
SELECT s.strategy_name AS [Strategy], ds.symbol AS [Option Symbol],
       COUNT(*) AS [Snapshot Rows],
       CONVERT(varchar(10), MIN(ds.snapshot_date), 23) AS [First Seen],
       CONVERT(varchar(10), MAX(ds.snapshot_date), 23) AS [Last Seen]
FROM daily_snapshot ds
JOIN strategies s ON s.id = ds.strategy_id
WHERE ds.symbol LIKE '-%' AND ISNULL(s.is_option_strategy,0) = 0
  AND ds.snapshot_date >= @since
GROUP BY s.strategy_name, ds.symbol
ORDER BY COUNT(*) DESC, ds.symbol;
'@ })

$checks.Add([pscustomobject]@{ Id='C2'; Severity='HIGH'; Counts=$true
  Title='Asset-type misclassification (symbol shape vs asset_type_id)'
  Desc='Option-format symbols not typed as Option (asset_type_id 6), or non-option symbols wrongly typed as Option.'
  Sql=@'
SELECT ds.symbol AS [Symbol], ds.asset_type_id AS [Asset Type Id],
       CASE WHEN ds.symbol LIKE '-%' THEN 'Option symbol not typed Option'
            ELSE 'Non-option symbol typed Option' END AS [Issue],
       COUNT(*) AS [Rows]
FROM daily_snapshot ds
WHERE ds.snapshot_date >= @since
  AND ( (ds.symbol LIKE '-%' AND (ds.asset_type_id <> 6 OR ds.asset_type_id IS NULL))
     OR (ds.symbol NOT LIKE '-%' AND ds.asset_type_id = 6) )
GROUP BY ds.symbol, ds.asset_type_id,
         CASE WHEN ds.symbol LIKE '-%' THEN 'Option symbol not typed Option'
              ELSE 'Non-option symbol typed Option' END
ORDER BY COUNT(*) DESC, ds.symbol;
'@ })

$checks.Add([pscustomobject]@{ Id='C6'; Severity='HIGH'; Counts=$true
  Title='Referential integrity (orphaned or cross-user strategy_id)'
  Desc='A strategy_id that does not resolve to a strategy, or resolves to a strategy owned by a different user.'
  Sql=@'
SELECT [Table], [Issue], COUNT(*) AS [Rows] FROM (
  SELECT 'transactions' AS [Table], 'orphaned strategy_id' AS [Issue]
  FROM transactions t WHERE t.strategy_id IS NOT NULL AND t.transaction_date >= @since
    AND NOT EXISTS (SELECT 1 FROM strategies s WHERE s.id = t.strategy_id)
  UNION ALL
  SELECT 'transactions', 'cross-user strategy_id'
  FROM transactions t JOIN strategies s ON s.id = t.strategy_id
  WHERE t.transaction_date >= @since
    AND CONVERT(varchar,s.authenticated_user_id) <> CONVERT(varchar,t.authenticated_user_id)
  UNION ALL
  SELECT 'option_transactions', 'orphaned strategy_id'
  FROM option_transactions o WHERE o.strategy_id IS NOT NULL AND o.transaction_date >= @since
    AND NOT EXISTS (SELECT 1 FROM strategies s WHERE s.id = o.strategy_id)
  UNION ALL
  SELECT 'option_transactions', 'cross-user strategy_id'
  FROM option_transactions o JOIN strategies s ON s.id = o.strategy_id
  WHERE o.transaction_date >= @since
    AND CONVERT(varchar,s.authenticated_user_id) <> CONVERT(varchar,o.authenticated_user_id)
  UNION ALL
  SELECT 'daily_snapshot', 'orphaned strategy_id'
  FROM daily_snapshot ds WHERE ds.strategy_id IS NOT NULL AND ds.snapshot_date >= @since
    AND NOT EXISTS (SELECT 1 FROM strategies s WHERE s.id = ds.strategy_id)
  UNION ALL
  SELECT 'daily_snapshot', 'cross-user strategy_id'
  FROM daily_snapshot ds JOIN strategies s ON s.id = ds.strategy_id
  WHERE ds.snapshot_date >= @since AND ds.authenticated_user_id IS NOT NULL
    AND CONVERT(varchar,s.authenticated_user_id) <> CONVERT(varchar,ds.authenticated_user_id)
) x
GROUP BY [Table], [Issue]
HAVING COUNT(*) > 0
ORDER BY [Table], [Issue];
'@ })

$checks.Add([pscustomobject]@{ Id='C3'; Severity='MEDIUM'; Counts=$true
  Title='Stock strategy disagreement: transaction vs snapshot'
  Desc='For the same (account, symbol), the strategy on the most recent transaction differs from the strategy on the most recent open snapshot position.'
  Sql=@'
;WITH ls AS (
  SELECT account_id, symbol, strategy_id,
         ROW_NUMBER() OVER (PARTITION BY account_id, symbol ORDER BY snapshot_date DESC, id DESC) rn
  FROM daily_snapshot
  WHERE ISNULL(quantity,0) <> 0 AND symbol NOT LIKE '-%' AND strategy_id IS NOT NULL
    AND snapshot_date >= @since
), lt AS (
  SELECT account_id, symbol, strategy_id,
         ROW_NUMBER() OVER (PARTITION BY account_id, symbol ORDER BY transaction_date DESC, id DESC) rn
  FROM transactions
  WHERE symbol IS NOT NULL AND account_id IS NOT NULL AND strategy_id IS NOT NULL
    AND transaction_date >= @since
)
SELECT ls.account_id AS [Account], ls.symbol AS [Symbol],
       st.strategy_name AS [Transaction Strategy],
       ss.strategy_name AS [Snapshot Strategy]
FROM ls
JOIN lt ON lt.account_id = ls.account_id AND lt.symbol = ls.symbol AND lt.rn = 1
JOIN strategies ss ON ss.id = ls.strategy_id
JOIN strategies st ON st.id = lt.strategy_id
WHERE ls.rn = 1 AND ls.strategy_id <> lt.strategy_id
ORDER BY ls.symbol;
'@ })

$checks.Add([pscustomobject]@{ Id='C5'; Severity='MEDIUM'; Counts=$true
  Title='Option strategy disagreement: option trade vs snapshot'
  Desc='option_transactions matched to their daily_snapshot option position (by underlying + expiration + strike) where the two carry different strategies.'
  Sql=@'
;WITH lso AS (
  SELECT account_id, symbol, strategy_id,
         ROW_NUMBER() OVER (PARTITION BY account_id, symbol ORDER BY snapshot_date DESC, id DESC) rn
  FROM daily_snapshot WHERE symbol LIKE '-%' AND snapshot_date >= @since
), otk AS (
  SELECT ot.account_id, ot.symbol AS underlying, ot.strategy_id,
         '-' + ot.symbol + FORMAT(ot.expiration_date,'yyMMdd') + '_'
             + CONVERT(varchar, CAST(ot.strike_price AS float)) AS pat
  FROM option_transactions ot WHERE ot.transaction_date >= @since
)
SELECT otk.account_id AS [Account], otk.underlying AS [Underlying],
       sot.strategy_name AS [Option Txn Strategy],
       s.symbol AS [Snapshot Symbol],
       sos.strategy_name AS [Snapshot Strategy]
FROM otk
JOIN (SELECT * FROM lso WHERE rn = 1) s
     ON s.account_id = otk.account_id AND s.symbol LIKE otk.pat
JOIN strategies sot ON sot.id = otk.strategy_id
JOIN strategies sos ON sos.id = s.strategy_id
WHERE s.strategy_id <> otk.strategy_id
ORDER BY otk.underlying;
'@ })

$checks.Add([pscustomobject]@{ Id='C4'; Severity='MEDIUM'; Counts=$true
  Title='Multiple strategies assigned to the same symbol'
  Desc='A single (account, symbol) carries more than one distinct strategy across its transactions - a source of downstream ambiguity (often a real strategy co-existing with Personal / N/A).'
  Sql=@'
SELECT account_id AS [Account], symbol AS [Symbol],
       COUNT(DISTINCT strategy_id) AS [Distinct Strategies],
       STRING_AGG(CONVERT(varchar, strategy_id), ', ') WITHIN GROUP (ORDER BY strategy_id) AS [Strategy IDs]
FROM (
  SELECT DISTINCT account_id, symbol, strategy_id
  FROM transactions
  WHERE symbol IS NOT NULL AND account_id IS NOT NULL AND strategy_id IS NOT NULL
    AND transaction_date >= @since
) d
GROUP BY account_id, symbol
HAVING COUNT(DISTINCT strategy_id) > 1
ORDER BY COUNT(DISTINCT strategy_id) DESC, symbol;
'@ })

$checks.Add([pscustomobject]@{ Id='C7'; Severity='INFO'; Counts=$false
  Title='Transactions with no strategy assigned'
  Desc='Transactions in the window that have a symbol but no strategy_id, grouped by how strategy assignment was (or was not) attempted.'
  Sql=@"
SELECT ISNULL(strategy_assigned_method,'(none)') AS [Assignment Method],
       COUNT(*) AS [Rows]
FROM transactions
WHERE strategy_id IS NULL AND symbol IS NOT NULL AND transaction_date >= @since
$c7ExcludeSql
GROUP BY strategy_assigned_method
ORDER BY COUNT(*) DESC;
"@ })

# --- run every check ----------------------------------------------------------
foreach ($c in $checks) {
    $dt = Invoke-Q $c.Sql
    # Suppress accepted (known-good) findings unless the user asks to include them.
    $acceptedCount = 0
    if (-not $IncludeAccepted -and $AcceptedExceptions.ContainsKey($c.Id) -and $dt.Rows.Count -gt 0) {
        $rules = $AcceptedExceptions[$c.Id]
        $toRemove = @()
        foreach ($row in $dt.Rows) {
            foreach ($rule in $rules) {
                $match = $true
                foreach ($col in $rule.Keys) {
                    if (-not $dt.Columns.Contains($col)) { $match = $false; break }
                    if (([string]$row[$col]).Trim() -ne ([string]$rule[$col]).Trim()) { $match = $false; break }
                }
                if ($match) { $toRemove += $row; break }
            }
        }
        foreach ($row in $toRemove) { $dt.Rows.Remove($row) }
        $acceptedCount = @($toRemove).Count
    }
    # C7 uses an accepted-unassigned allowlist applied in-SQL; count what it suppressed.
    if ($c.Id -eq 'C7' -and -not $IncludeAccepted -and $AcceptedUnassigned.Count -gt 0) {
        $pred = ($AcceptedUnassigned | ForEach-Object {
            "(account_id = '$($_.Account)' AND symbol = '$($_.Symbol)')" }) -join ' OR '
        $cntDt = Invoke-Q "SELECT COUNT(*) AS n FROM transactions WHERE strategy_id IS NULL AND symbol IS NOT NULL AND transaction_date >= @since AND ($pred)"
        $acceptedCount = [int]$cntDt.Rows[0]['n']
    }
    Add-Member -InputObject $c -NotePropertyName Data -NotePropertyValue $dt -Force
    Add-Member -InputObject $c -NotePropertyName Accepted -NotePropertyValue $acceptedCount -Force
    $rowsAffected = ($dt | Measure-Object).Count
    # For grouped checks the "impact" is the sum of a Rows column when present.
    $impact = $rowsAffected
    if ($dt.Columns.Contains('Rows')) {
        $impact = ($dt.Rows | ForEach-Object { [int]$_['Rows'] } | Measure-Object -Sum).Sum
        if (-not $impact) { $impact = 0 }
    }
    Add-Member -InputObject $c -NotePropertyName Findings -NotePropertyValue $rowsAffected -Force
    Add-Member -InputObject $c -NotePropertyName Impact   -NotePropertyValue $impact -Force
}
$conn.Close()

$discrepancyChecks = $checks | Where-Object { $_.Counts }
$totalFindings = ($discrepancyChecks | Where-Object { $_.Findings -gt 0 } | Measure-Object).Count
$highCount   = ($checks | Where-Object { $_.Severity -eq 'HIGH'   -and $_.Findings -gt 0 } | Measure-Object).Count
$medCount    = ($checks | Where-Object { $_.Severity -eq 'MEDIUM' -and $_.Findings -gt 0 } | Measure-Object).Count

# --- JSON shortcut ------------------------------------------------------------
if ($Json) {
    [pscustomobject]@{
        window        = $windowLabel
        since         = $sinceDate.ToString('yyyy-MM-dd')
        generated     = (Get-Date).ToString('s')
        checksWithFindings = $totalFindings
        high          = $highCount
        medium        = $medCount
        checks        = @($checks | ForEach-Object {
            [pscustomobject]@{ id=$_.Id; title=$_.Title; severity=$_.Severity
                counts=$_.Counts; findings=$_.Findings; impact=$_.Impact; accepted=$_.Accepted }
        })
    } | ConvertTo-Json -Depth 5
    return
}

# --- HTML rendering -----------------------------------------------------------
function Enc([object]$s){ [System.Net.WebUtility]::HtmlEncode([string]$s) }
function SevClass([string]$s){ switch($s){'HIGH'{'sev-high'}'MEDIUM'{'sev-med'}default{'sev-info'}} }

function Render-Table {
    param([System.Data.DataTable]$Dt)
    if ($Dt.Rows.Count -eq 0) {
        return "<p class='ok'>&#10003; No findings in this window.</p>"
    }
    $cols = @($Dt.Columns | ForEach-Object { $_.ColumnName })
    $th = ($cols | ForEach-Object { "<th>$(Enc $_)</th>" }) -join ''
    $body = foreach ($r in $Dt.Rows) {
        $tds = foreach ($col in $cols) {
            $val = $r[$col]
            if ($val -is [datetime]) { $val = $val.ToString('yyyy-MM-dd') }
            $numeric = ($col -in 'Rows','Snapshot Rows','Distinct Strategies','Asset Type Id')
            "<td class='$(if($numeric){'num'})'>$(Enc $val)</td>"
        }
        "<tr>$($tds -join '')</tr>"
    }
    "<table><thead><tr>$th</tr></thead><tbody>$($body -join "`n")</tbody></table>"
}

$gen = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$sections = foreach ($c in $checks) {
    $badge = if ($c.Findings -gt 0) { "<span class='pill $(SevClass $c.Severity)'>$($c.Severity)</span>" }
             else { "<span class='pill sev-ok'>CLEAN</span>" }
    $impactNote = if ($c.Findings -gt 0 -and $c.Impact -ne $c.Findings) {
        " &middot; $($c.Impact) row(s) affected" } else { '' }
    $acceptedNote = if ($c.Accepted -gt 0) {
        " <span class='pill sev-ok'>$($c.Accepted) accepted</span>" } else { '' }
    @"
  <section class='$(if($c.Findings -eq 0){'clean'})'>
    <h2><span class='cid'>$($c.Id)</span> $(Enc $c.Title) $badge$acceptedNote
      <span class='cnt'>$($c.Findings) finding$(if($c.Findings -ne 1){'s'})$impactNote</span></h2>
    <p class='desc'>$(Enc $c.Desc)</p>
    $(Render-Table $c.Data)
  </section>
"@
}

$html = @"
<!doctype html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>WebPortfolio - Strategy Alignment Audit</title>
<style>
  :root{ --bg:#f5f5fb; --card:#fff; --ink:#1a1a2e; --muted:#6b6b80; --line:#e3e3ee;
         --accent:#5b5bd6; --accent2:#8b5cf6;
         --high:#c0362c; --highBg:#fdeceb; --med:#b4530a; --medBg:#fff1e6;
         --info:#3457b8; --infoBg:#e9eefb; --ok:#1f7a4d; --okBg:#e7f6ee; }
  @media (prefers-color-scheme:dark){
    :root{ --bg:#14141c; --card:#1d1d28; --ink:#ececf5; --muted:#9a9ab0; --line:#2c2c3a;
           --high:#ff8a80; --highBg:#3a1512; --med:#ffb277; --medBg:#3a2410;
           --info:#9db4f5; --infoBg:#171f38; --ok:#7fe0ab; --okBg:#10301f; } }
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);
    font:15px/1.55 'Segoe UI',system-ui,sans-serif;padding:28px 32px}
  h1{font-size:23px;margin:0 0 2px} .sub{color:var(--muted);margin:0 0 20px;font-size:13px}
  .cards{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:26px}
  .c{background:var(--card);border:1px solid var(--line);padding:14px 18px;min-width:140px}
  .c .n{font-size:28px;font-weight:700;line-height:1} .c .l{color:var(--muted);font-size:12px;
    text-transform:uppercase;letter-spacing:.04em;margin-top:4px}
  .c.accent{border-top:3px solid var(--accent)}
  .c.high{border-top:3px solid var(--high)} .c.med{border-top:3px solid var(--med)}
  section{background:var(--card);border:1px solid var(--line);padding:16px 20px;margin-bottom:16px}
  section.clean{opacity:.72}
  h2{font-size:16px;margin:0 0 6px;display:flex;align-items:center;gap:10px;flex-wrap:wrap}
  .cid{font:600 12px/1 ui-monospace,monospace;color:var(--muted);border:1px solid var(--line);
    padding:3px 6px}
  .cnt{margin-left:auto;color:var(--muted);font-size:12.5px;font-weight:400}
  .desc{color:var(--muted);font-size:13px;margin:0 0 12px;max-width:900px}
  table{width:100%;border-collapse:collapse;border:1px solid var(--line);font-size:13.5px}
  th,td{padding:8px 12px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
  th{font-size:11.5px;text-transform:uppercase;letter-spacing:.03em;color:var(--muted)}
  td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
  tbody tr:hover{background:rgba(127,127,150,.06)}
  .pill{display:inline-block;padding:2px 9px;font-size:11px;font-weight:700;letter-spacing:.03em}
  .pill.sev-high{background:var(--highBg);color:var(--high)}
  .pill.sev-med{background:var(--medBg);color:var(--med)}
  .pill.sev-info{background:var(--infoBg);color:var(--info)}
  .pill.sev-ok{background:var(--okBg);color:var(--ok)}
  .ok{color:var(--ok);font-size:13px;margin:6px 0 0}
  .note{margin-top:20px;color:var(--muted);font-size:12.5px;max-width:960px}
  code{background:rgba(127,127,150,.14);padding:1px 6px;font-size:12.5px}
</style></head><body>
  <h1>WebPortfolio &mdash; Strategy Alignment Audit</h1>
  <p class='sub'>Timeframe: <strong>$(Enc $windowLabel)</strong> &middot; generated $gen &middot;
     tables compared: <code>transactions</code>, <code>option_transactions</code>, <code>daily_snapshot</code></p>
  <div class='cards'>
    <div class='c accent'><div class='n'>$totalFindings</div><div class='l'>Checks with findings</div></div>
    <div class='c high'><div class='n'>$highCount</div><div class='l'>High severity</div></div>
    <div class='c med'><div class='n'>$medCount</div><div class='l'>Medium severity</div></div>
  </div>
$($sections -join "`n")
  <p class='note'><strong>How to read:</strong> each section is one alignment check across the three
  strategy-bearing tables, scoped to the timeframe above. <strong>HIGH</strong> = data-integrity issues
  (wrong strategy type flags, mis-typed assets, orphaned references). <strong>MEDIUM</strong> = the same
  symbol carrying different strategies across tables. <strong>INFO</strong> = coverage gaps, not
  necessarily errors. Options are matched between <code>option_transactions</code> and
  <code>daily_snapshot</code> on underlying&nbsp;+&nbsp;expiration&nbsp;+&nbsp;strike (the put/call leg lives
  only in the snapshot OCC symbol). This report is read-only &mdash; nothing in the database was changed.</p>
</body></html>
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp    = (Get-Date).ToString('yyyyMMdd-HHmmss')
$htmlPath = Join-Path $OutDir "strategy-audit-$stamp.html"
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

Write-Host "Strategy audit ($windowLabel):" -ForegroundColor Cyan
Write-Host ("  {0} check(s) with findings  ({1} high, {2} medium)" -f $totalFindings, $highCount, $medCount)
foreach ($c in $checks) {
    $mark = if ($c.Findings -gt 0) { '!' } else { ' ' }
    $acc  = if ($c.Accepted -gt 0) { " ($($c.Accepted) accepted)" } else { '' }
    Write-Host ("  [{0}] {1} {2,-52} {3} finding(s){4}" -f $mark, $c.Id, $c.Title, $c.Findings, $acc)
}
Write-Host "Wrote $htmlPath" -ForegroundColor Green
if (-not $NoOpen) { Start-Process $htmlPath }
