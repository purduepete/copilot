#requires -Version 7.0
<#
.SYNOPSIS
  Resolve leaked / missing strategy assignments on webportfolio TRANSACTIONS from
  account-grounded snapshot & current-position data (companion to the C8 audit check).

.DESCRIPTION
  The Transaction Performance page used to derive a strategy at query time via
  COALESCE(t.strategy_id, cp.strategy_id, da.strategy_id). The da (desired_allocations)
  leg is keyed on symbol + user only (NO account_id), so a live transaction whose stored
  strategy_id is NULL - and which has no current position - borrowed a strategy from a
  DIFFERENT account. That account-agnostic fallback was removed in the backend
  (issue #470); those transactions now display blank until their strategy_id is stamped
  from an ACCOUNT-GROUNDED source. This script does that stamping.

  For every live (accounts.is_paper = 0) transaction in the window whose strategy_id is
  NULL, it resolves the correct strategy_id from the SAME account + symbol, in priority
  order:

    1. daily_snapshot strategy on-or-before the transaction date (most recent)   -> 'auto-audit-snapshot-prior'
    2. daily_snapshot strategy from ANY date (most recent)                        -> 'auto-audit-snapshot-any'
    3. current_positions strategy (is_current = 1)                                -> 'auto-audit-position'

  It NEVER uses desired_allocations (that was the leak) and NEVER crosses accounts or
  users. Transactions with a NULL account_id, or with no account-grounded strategy
  anywhere, are reported as UNRESOLVABLE. Options are out of scope (they live in
  option_transactions, not the transactions table).

  SAFETY: only rows whose strategy_id IS NULL and whose strategy_assigned_method is NULL
  or 'auto-*' are ever written; a 'manual' assignment is left untouched unless -Force is
  passed. DRY-RUN BY DEFAULT - it only reports proposals and writes/opens a self-contained
  HTML report. Pass -Apply to UPDATE inside a single transaction (guarded so it re-checks
  strategy_id IS NULL at write time).

.PARAMETER Apply
  Perform the UPDATEs. Without this switch the script is strictly read-only (proposals).

.PARAMETER Force
  Also overwrite rows whose strategy_assigned_method = 'manual'. Default: manual is never
  touched. (strategy_id must still be NULL to be a candidate.)

.PARAMETER Months
  How far back to look (by transaction_date). Default 3. Ignored when -Since or -AllTime.

.PARAMETER Since
  Explicit lower bound (yyyy-MM-dd) for transaction_date. Overrides -Months.

.PARAMETER AllTime
  Ignore the date window entirely. Overrides -Months / -Since.

.PARAMETER EnvFile
  Path to the .env with DB_SERVER/DB_NAME/DB_USER/DB_PASSWORD. Default is the
  webportfolio repo's .env.development.local.

.PARAMETER OutDir
  Where to write the HTML report. Default %TEMP%\webportfolio-transaction-strategies.

.PARAMETER Json
  Emit a machine-readable summary to stdout; no HTML, no browser.

.PARAMETER NoOpen
  Write the HTML but do not launch the browser.

.EXAMPLE
  # Dry-run: report what WOULD be stamped, last 3 months (opens HTML)
  pwsh -File Resolve-TransactionStrategies.ps1

.EXAMPLE
  # Read the summary yourself, no HTML/browser, last 6 months
  pwsh -File Resolve-TransactionStrategies.ps1 -Months 6 -Json -NoOpen

.EXAMPLE
  # Actually apply the resolutions
  pwsh -File Resolve-TransactionStrategies.ps1 -Months 6 -Apply
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Force,
    [int]$Months = 3,
    [string]$Since,
    [switch]$AllTime,
    [string]$EnvFile = 'C:\Files\Dev\main\webportfolio\.env.development.local',
    [string]$OutDir  = (Join-Path $env:TEMP 'webportfolio-transaction-strategies'),
    [switch]$Json,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

# --- resolve the date window --------------------------------------------------
if ($AllTime) {
    $sinceDate = '1900-01-01'
} elseif ($Since) {
    try { $sinceDate = ([datetime]$Since).ToString('yyyy-MM-dd') }
    catch { throw "Invalid -Since '$Since' (expected yyyy-MM-dd)." }
} else {
    if ($Months -lt 1) { throw "-Months must be >= 1." }
    $sinceDate = (Get-Date).Date.AddMonths(-$Months).ToString('yyyy-MM-dd')
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

# --- connect ------------------------------------------------------------------
$conn = New-Object System.Data.SqlClient.SqlConnection $connStr
$conn.Open()
function Invoke-Q {
    param([string]$Sql, [hashtable]$Params)
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = 180
    if ($Params) { foreach ($k in $Params.Keys) { [void]$cmd.Parameters.AddWithValue($k, $Params[$k]) } }
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dt = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    ,$dt
}

# --- detection + resolution query --------------------------------------------
# For every live transaction with a NULL strategy_id in the window, find the
# account-grounded strategy (same account + symbol) in priority order:
#   prior snapshot -> any snapshot -> current position. desired_allocations is
# deliberately NOT consulted (that account-agnostic fallback was the leak).
$manualClause = if ($Force) { '' } else {
    "      AND (t.strategy_assigned_method IS NULL OR t.strategy_assigned_method <> 'manual')"
}

$detectSql = @"
;WITH tx AS (
    SELECT t.id, t.account_id, t.symbol, t.transaction_date, t.authenticated_user_id,
           t.action, t.quantity,
           ISNULL(t.strategy_assigned_method, '(none)') AS assigned_method
    FROM transactions t
    JOIN accounts a ON t.account_id = a.id
    WHERE t.symbol IS NOT NULL AND t.quantity IS NOT NULL AND t.quantity <> 0
      AND a.is_paper = 0
      AND t.strategy_id IS NULL
      AND t.transaction_date >= @since
$manualClause
)
SELECT tx.id                                        AS [Transaction Id],
       tx.authenticated_user_id                     AS [User Id],
       tx.account_id                                AS [Account Id],
       a.account_name                               AS [Account],
       tx.symbol                                    AS [Symbol],
       tx.action                                    AS [Action],
       tx.quantity                                  AS [Quantity],
       CONVERT(varchar(10), tx.transaction_date, 23) AS [Txn Date],
       tx.assigned_method                           AS [Method],
       snap_prior.strategy_id                       AS [Prior Snap Sid],
       CONVERT(varchar(10), snap_prior.snapshot_date, 23) AS [Prior Snap Date],
       snap_any.strategy_id                         AS [Any Snap Sid],
       CONVERT(varchar(10), snap_any.snapshot_date, 23)   AS [Any Snap Date],
       cp.strategy_id                               AS [Position Sid],
       COALESCE(snap_prior.strategy_id, snap_any.strategy_id, cp.strategy_id) AS [Resolved Sid],
       rs.strategy_name                             AS [Resolved Strategy],
       CASE WHEN snap_prior.strategy_id IS NOT NULL THEN 'auto-audit-snapshot-prior'
            WHEN snap_any.strategy_id   IS NOT NULL THEN 'auto-audit-snapshot-any'
            WHEN cp.strategy_id         IS NOT NULL THEN 'auto-audit-position'
            ELSE NULL END                           AS [Resolve Source]
FROM tx
LEFT JOIN accounts a ON a.id = tx.account_id
OUTER APPLY (
    SELECT TOP 1 ds.strategy_id, ds.snapshot_date
    FROM daily_snapshot ds
    WHERE ds.account_id = tx.account_id AND ds.symbol = tx.symbol
      AND ds.strategy_id IS NOT NULL
      AND ds.snapshot_date <= tx.transaction_date
    ORDER BY ds.snapshot_date DESC, ds.id DESC
) snap_prior
OUTER APPLY (
    SELECT TOP 1 ds.strategy_id, ds.snapshot_date
    FROM daily_snapshot ds
    WHERE ds.account_id = tx.account_id AND ds.symbol = tx.symbol
      AND ds.strategy_id IS NOT NULL
    ORDER BY ds.snapshot_date DESC, ds.id DESC
) snap_any
OUTER APPLY (
    SELECT TOP 1 cpx.strategy_id
    FROM current_positions cpx
    WHERE cpx.account_id = tx.account_id AND cpx.symbol = tx.symbol
      AND cpx.is_current = 1 AND cpx.strategy_id IS NOT NULL
    ORDER BY cpx.id DESC
) cp
LEFT JOIN strategies rs ON rs.id = COALESCE(snap_prior.strategy_id, snap_any.strategy_id, cp.strategy_id)
ORDER BY a.account_name, tx.symbol, tx.transaction_date;
"@

$dt = Invoke-Q $detectSql @{ '@since' = $sinceDate }

# --- classify each row --------------------------------------------------------
function IsNull($v){ $v -eq $null -or $v -eq [DBNull]::Value }

$rows = foreach ($r in $dt.Rows) {
    $resolvedSid = if (IsNull $r['Resolved Sid']) { $null } else { [int]$r['Resolved Sid'] }
    $acctId      = if (IsNull $r['Account Id'])   { $null } else { [long]$r['Account Id'] }
    $canResolve  = ($null -ne $resolvedSid) -and ($null -ne $acctId)

    [pscustomobject]@{
        TransactionId   = [long]$r['Transaction Id']
        Account         = if (IsNull $r['Account']) { '(no account)' } else { [string]$r['Account'] }
        AccountId       = $acctId
        Symbol          = [string]$r['Symbol']
        Action          = if (IsNull $r['Action']) { $null } else { [string]$r['Action'] }
        Quantity        = if (IsNull $r['Quantity']) { $null } else { [double]$r['Quantity'] }
        TxnDate         = if (IsNull $r['Txn Date']) { $null } else { [string]$r['Txn Date'] }
        Method          = [string]$r['Method']
        ResolvedSid     = $resolvedSid
        ResolvedStrategy= if (IsNull $r['Resolved Strategy']) { $null } else { [string]$r['Resolved Strategy'] }
        ResolveSource   = if (IsNull $r['Resolve Source']) { $null } else { [string]$r['Resolve Source'] }
        FromDate        = if     (-not (IsNull $r['Prior Snap Date'])) { [string]$r['Prior Snap Date'] }
                          elseif (-not (IsNull $r['Any Snap Date']))   { [string]$r['Any Snap Date'] }
                          else { $null }
        CanResolve      = $canResolve
        NoAccount       = ($null -eq $acctId)
    }
}
$rows = @($rows)

$actionable   = @($rows | Where-Object { $_.CanResolve })
$unresolvable = @($rows | Where-Object { -not $_.CanResolve })

$totalInScope = $rows.Count
$bySrc = @{
    'auto-audit-snapshot-prior' = @($rows | Where-Object { $_.ResolveSource -eq 'auto-audit-snapshot-prior' }).Count
    'auto-audit-snapshot-any'   = @($rows | Where-Object { $_.ResolveSource -eq 'auto-audit-snapshot-any' }).Count
    'auto-audit-position'       = @($rows | Where-Object { $_.ResolveSource -eq 'auto-audit-position' }).Count
}
$appliedCount = 0

# --- apply (optional) ---------------------------------------------------------
if ($Apply -and $actionable.Count -gt 0) {
    $tx = $conn.BeginTransaction()
    try {
        foreach ($x in $actionable) {
            $cmd = $conn.CreateCommand()
            $cmd.Transaction = $tx
            # Guard: only stamp where strategy_id is still NULL (re-checked at write time).
            $manualGuard = if ($Force) { '' } else { " AND (strategy_assigned_method IS NULL OR strategy_assigned_method <> 'manual')" }
            $cmd.CommandText = @"
UPDATE transactions
   SET strategy_id = @sid,
       strategy_assigned_method = @method
 WHERE id = @tid AND strategy_id IS NULL$manualGuard;
"@
            $pSid = $cmd.Parameters.Add('@sid', [System.Data.SqlDbType]::Int);          $pSid.Value = [int]$x.ResolvedSid
            $pMet = $cmd.Parameters.Add('@method', [System.Data.SqlDbType]::VarChar, 64); $pMet.Value = [string]$x.ResolveSource
            $pTid = $cmd.Parameters.Add('@tid', [System.Data.SqlDbType]::BigInt);         $pTid.Value = [long]$x.TransactionId
            $appliedCount += $cmd.ExecuteNonQuery()
        }
        $tx.Commit()
    } catch {
        $tx.Rollback(); $conn.Close(); throw
    }
}
$conn.Close()

# --- JSON shortcut ------------------------------------------------------------
if ($Json) {
    $toObj = {
        param($x)
        [pscustomobject]@{
            transactionId   = $x.TransactionId
            account         = $x.Account
            symbol          = $x.Symbol
            action          = $x.Action
            quantity        = $x.Quantity
            txnDate         = $x.TxnDate
            method          = $x.Method
            resolvedStrategy= $x.ResolvedStrategy
            resolveSource   = $x.ResolveSource
            fromDate        = $x.FromDate
            noAccount       = $x.NoAccount
        }
    }
    [pscustomobject]@{
        generated        = (Get-Date).ToString('s')
        applied          = [bool]$Apply
        force            = [bool]$Force
        since            = $sinceDate
        allTime          = [bool]$AllTime
        totalInScope     = $totalInScope
        actionable       = $actionable.Count
        unresolvable     = $unresolvable.Count
        bySource         = $bySrc
        rowsUpdated      = $appliedCount
        actionableRows   = @($actionable   | ForEach-Object { & $toObj $_ })
        unresolvableRows = @($unresolvable | ForEach-Object { & $toObj $_ })
    } | ConvertTo-Json -Depth 5
    return
}

# --- HTML rendering -----------------------------------------------------------
function Enc([object]$s){ [System.Net.WebUtility]::HtmlEncode([string]$s) }

$srcLabels = @{
    'auto-audit-snapshot-prior' = 'prior snapshot'
    'auto-audit-snapshot-any'   = 'recent snapshot'
    'auto-audit-position'       = 'current position'
}

function Render-Actionable {
    param([object[]]$Rows)
    if ($Rows.Count -eq 0) { return "<p class='ok'>&#10003; None.</p>" }
    $body = foreach ($x in $Rows) {
        $srcTag = $srcLabels[$x.ResolveSource]
        $strat  = "<span class='chg'><span class='was none'>unset</span>" +
                  "<span class='arr'>&rarr;</span><span class='now'>$(Enc $x.ResolvedStrategy)</span>" +
                  "<span class='tag'>$(Enc $srcTag)</span></span>"
        "<tr><td>$(Enc $x.Account)</td><td>$(Enc $x.Symbol)</td>" +
        "<td>$(Enc $x.Action)</td><td>$(Enc $x.TxnDate)</td>" +
        "<td>$strat</td><td>$(Enc $x.FromDate)</td>" +
        "<td class='num'>$($x.TransactionId)</td></tr>"
    }
    "<table><thead><tr><th>Account</th><th>Symbol</th><th>Action</th><th>Txn Date</th>" +
    "<th>Strategy</th><th>Source Date</th><th class='num'>Txn Id</th></tr></thead>" +
    "<tbody>$($body -join "`n")</tbody></table>"
}

function Render-Unresolvable {
    param([object[]]$Rows)
    if ($Rows.Count -eq 0) { return "<p class='ok'>&#10003; None.</p>" }
    $body = foreach ($x in $Rows) {
        $why = if ($x.NoAccount) { 'no account_id' } else { 'no account-grounded strategy' }
        "<tr><td>$(Enc $x.Account)</td><td>$(Enc $x.Symbol)</td>" +
        "<td>$(Enc $x.Action)</td><td>$(Enc $x.TxnDate)</td>" +
        "<td>$(Enc $why)</td><td class='num'>$($x.TransactionId)</td></tr>"
    }
    "<table><thead><tr><th>Account</th><th>Symbol</th><th>Action</th><th>Txn Date</th>" +
    "<th>Why unresolvable</th><th class='num'>Txn Id</th></tr></thead>" +
    "<tbody>$($body -join "`n")</tbody></table>"
}

$gen  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$mode = if ($Apply) { "APPLIED &mdash; $appliedCount transaction(s) stamped" } else { 'Dry-run (report only)' }
$modeClass = if ($Apply) { 'sev-applied' } else { 'sev-dry' }
$windowNote = if ($AllTime) { 'all time' } else { "since $sinceDate" }
$forceNote  = if ($Force) { ' &middot; -Force (manual overwrite enabled)' } else { '' }

$html = @"
<!doctype html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>WebPortfolio - Resolve Transaction Strategies</title>
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
  .tag{display:inline-block;padding:0 6px;margin-left:6px;font-size:10.5px;font-weight:700;background:var(--infoBg);color:var(--info)}
  .chg{display:inline-flex;align-items:center;gap:6px;flex-wrap:wrap}
  .was{color:var(--muted)} .was.none{font-style:italic;opacity:.8}
  .arr{color:var(--muted)} .now{font-weight:600;color:var(--ok)}
  .ok{color:var(--ok)} .foot{color:var(--muted);font-size:12px;margin-top:22px}
</style></head><body>
<h1>Resolve Transaction Strategies</h1>
<p class='sub'>$gen &middot; <span class='pill $modeClass'>$mode</span> &middot; $windowNote$forceNote</p>
<div class='cards'>
  <div class='c accent'><div class='n'>$totalInScope</div><div class='l'>In scope</div></div>
  <div class='c ok'><div class='n'>$($actionable.Count)</div><div class='l'>Resolvable</div></div>
  <div class='c med'><div class='n'>$($unresolvable.Count)</div><div class='l'>Unresolvable</div></div>
  <div class='c'><div class='n'>$appliedCount</div><div class='l'>Stamped</div></div>
</div>
<section>
  <h2>Resolvable transactions <span class='cnt'>from prior snapshot: $($bySrc['auto-audit-snapshot-prior']) &middot; recent snapshot: $($bySrc['auto-audit-snapshot-any']) &middot; current position: $($bySrc['auto-audit-position'])</span></h2>
  <p class='desc'>Live transactions with a NULL stored strategy_id whose correct strategy is recovered from the SAME account's snapshot / current position. desired_allocations is never consulted.</p>
  $(Render-Actionable $actionable)
</section>
<section>
  <h2>Unresolvable <span class='cnt'>$($unresolvable.Count)</span></h2>
  <p class='desc'>No account-grounded strategy exists for these (e.g. a NULL account_id, or no snapshot / position ever carried a strategy for this account + symbol). Left untouched.</p>
  $(Render-Unresolvable $unresolvable)
</section>
<p class='foot'>Dry-run by default. Re-run with <code>-Apply</code> to stamp strategy_id (guarded to only write where strategy_id IS NULL). Companion to the C8 audit check in Invoke-StrategyAudit.ps1.</p>
</body></html>
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$htmlPath = Join-Path $OutDir "transaction-strategies-$stamp.html"
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

Write-Host ("{0}: {1} in scope, {2} resolvable, {3} unresolvable, {4} stamped." -f `
    $(if ($Apply) { 'APPLIED' } else { 'DRY-RUN' }), $totalInScope, $actionable.Count, $unresolvable.Count, $appliedCount)
Write-Host "Report: $htmlPath"
if (-not $NoOpen) { Start-Process $htmlPath }
