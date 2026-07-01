<#
.SYNOPSIS
  Azure cost analysis + reduction report for the webportfolio app's resource group.

.DESCRIPTION
  Read-only. Uses the Cost Management Query REST API (via `az rest`, no extension
  needed) to pull actual cost for a resource group, then:
    * breaks this cycle's cost (to-date) down by service and by resource,
    * compares each service against last full cycle,
    * projects this cycle's total from the current run-rate, and
    * flags where we're trending OVER last cycle (the whole point: we cut cost last
      cycle but are pacing higher this cycle) with concrete reduction levers.

  The invoice period is a BILLING CYCLE (day 9 -> day 8 by default, -BillingAnchorDay),
  not the calendar month.

  Writes a self-contained HTML report and opens it. -Json prints a machine summary
  for agent consumption; -NoOpen skips the browser.

  Auth: whatever `az account show` is signed into. Everything here is read-only.
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup = 'investmentportfolio',
    [string]$Subscription,                       # defaults to the current az account
    [string]$OutDir = (Join-Path $env:TEMP 'webportfolio-azure-cost'),
    [switch]$Json,
    [switch]$NoOpen,
    [int]$BillingAnchorDay = 9          # invoicing cycle runs day 9 -> day 8 of next month
)

$ErrorActionPreference = 'Stop'

# --- resolve subscription -----------------------------------------------------
if (-not $Subscription) {
    $Subscription = (az account show --query id -o tsv)
    if (-not $Subscription) { throw "Not signed in to Azure. Run 'az login'." }
}

# --- billing-cycle boundaries -------------------------------------------------
# The invoice period is not the calendar month: it runs from day $BillingAnchorDay
# of one month through day ($BillingAnchorDay - 1) of the next (e.g. anchor 9 =>
# the 9th through the 8th). "Current" cycle = the one containing today.
$now = Get-Date
$anchor = [Math]::Max(1, [Math]::Min(28, $BillingAnchorDay))
if ($now.Day -ge $anchor) {
    $curStart = Get-Date -Year $now.Year -Month $now.Month -Day $anchor -Hour 0 -Minute 0 -Second 0
} else {
    $curStart = (Get-Date -Year $now.Year -Month $now.Month -Day $anchor -Hour 0 -Minute 0 -Second 0).AddMonths(-1)
}
$curEnd    = $curStart.AddMonths(1).AddSeconds(-1)   # end of day ($anchor - 1)
$prevStart = $curStart.AddMonths(-1)
$prevEnd   = $curStart.AddSeconds(-1)
$daysInCycle = [Math]::Round(($curEnd - $curStart).TotalDays)
$elapsed   = ($now - $curStart).TotalDays
if ($elapsed -le 0) { $elapsed = 0.5 }
if ($elapsed -gt $daysInCycle) { $elapsed = $daysInCycle }

function Fmt-Iso([datetime]$d){ $d.ToString('yyyy-MM-ddTHH:mm:ssZ') }

# --- cost query helper --------------------------------------------------------
# POSTs a Cost Management query for the RG over [from,to], grouped by $dimension,
# and returns a hashtable of key -> cost (rounded later). Follows nextLink paging.
function Invoke-CostQuery {
    param([datetime]$From, [datetime]$To, [string]$Dimension)
    $uri = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$ResourceGroup/providers/Microsoft.CostManagement/query?api-version=2023-03-01"
    $body = @{
        type      = 'ActualCost'
        timeframe = 'Custom'
        timePeriod= @{ from = (Fmt-Iso $From); to = (Fmt-Iso $To) }
        dataset   = @{
            granularity = 'None'
            aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
            grouping    = @(@{ type = 'Dimension'; name = $Dimension })
        }
    } | ConvertTo-Json -Depth 12

    $result = @{}
    do {
        $tmp = New-TemporaryFile
        $body | Out-File -LiteralPath $tmp -Encoding utf8
        $errFile = New-TemporaryFile
        $raw = $null
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            $raw = az rest --method post --uri $uri --body "@$tmp" --headers "Content-Type=application/json" -o json 2>$errFile
            if ($raw) { break }
            # az writes the error to stderr and returns empty stdout; the common
            # cause is Cost Management throttling (429) - back off and retry.
            $err = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
            if ($err -match '429|Too Many Requests|throttl') {
                Start-Sleep -Seconds ([Math]::Min(30, 5 * $attempt))
                continue
            }
            throw "Cost query failed: $((""$err"").Trim())"
        }
        Remove-Item -LiteralPath $tmp, $errFile -Force -ErrorAction SilentlyContinue
        if (-not $raw) { throw "Cost query kept getting throttled (429) - wait a minute and retry." }
        $resp = $raw | ConvertFrom-Json
        $cols = @($resp.properties.columns.name)
        $ci   = [Math]::Max(0, [Array]::IndexOf($cols, 'Cost'))
        $di   = [Array]::IndexOf($cols, $Dimension)
        foreach ($row in $resp.properties.rows) {
            $key  = if ($di -ge 0) { [string]$row[$di] } else { '(total)' }
            $cost = [double]$row[$ci]
            if ($result.ContainsKey($key)) { $result[$key] += $cost } else { $result[$key] = $cost }
        }
        $uri = $resp.properties.nextLink
    } while ($uri)
    return $result
}

if (-not $Json) { Write-Host "Querying Cost Management for '$ResourceGroup'..." -ForegroundColor Cyan }
$curByService  = Invoke-CostQuery -From $curStart  -To $now     -Dimension 'ServiceName'
$prevByService = Invoke-CostQuery -From $prevStart -To $prevEnd -Dimension 'ServiceName'
$curByResource = Invoke-CostQuery -From $curStart  -To $now     -Dimension 'ResourceId'

# --- assemble the per-service comparison --------------------------------------
$allServices = @($curByService.Keys + $prevByService.Keys | Sort-Object -Unique)
$services = foreach ($s in $allServices) {
    $mtd  = [double]($curByService[$s]);  if (-not $curByService.ContainsKey($s))  { $mtd = 0 }
    $prev = [double]($prevByService[$s]); if (-not $prevByService.ContainsKey($s)) { $prev = 0 }
    $proj = [Math]::Round($mtd / $elapsed * $daysInCycle, 2)
    [pscustomobject]@{
        Service    = $s
        LastMonth  = [Math]::Round($prev, 2)
        MTD        = [Math]::Round($mtd, 2)
        Projected  = $proj
        Delta      = [Math]::Round($proj - $prev, 2)   # projected vs last month
    }
}
$services = $services | Sort-Object Projected -Descending

$totalPrev = [Math]::Round((($prevByService.Values | Measure-Object -Sum).Sum), 2)
$totalMtd  = [Math]::Round((($curByService.Values  | Measure-Object -Sum).Sum), 2)
$totalProj = [Math]::Round($totalMtd / $elapsed * $daysInCycle, 2)
$totalDelta= [Math]::Round($totalProj - $totalPrev, 2)

# --- per-resource breakdown (leaf name) ---------------------------------------
$resources = foreach ($k in $curByResource.Keys) {
    $leaf = ($k -split '/')[-1]
    [pscustomobject]@{ Resource = $leaf; ResourceId = $k; MTD = [Math]::Round([double]$curByResource[$k], 2) }
}
$resources = $resources | Where-Object { $_.MTD -gt 0 } | Sort-Object MTD -Descending

# --- reduction levers (heuristic, keyed by service) ---------------------------
# Concrete, webportfolio-relevant knobs for the top cost-driving services.
$leverMap = @{
    'Azure SQL Database'     = 'Serverless auto-pause + lower min vCores/DTU; drop over-provisioned tier; shorten backup retention; check for an idle secondary/geo-replica.'
    'SQL Database'           = 'Serverless auto-pause + lower min vCores/DTU; drop over-provisioned tier; shorten backup retention.'
    'Azure App Service'      = 'Consolidate/downsize the App Service plan; scale to zero or move low-traffic apps to Consumption/Flex; kill idle slots.'
    'Azure Container Apps'   = 'Set min replicas to 0 (scale-to-zero); trim CPU/memory; confirm the keep-warm timer isn''t pinning it awake unnecessarily.'
    'Container Apps'         = 'Set min replicas to 0 (scale-to-zero); trim CPU/memory; review keep-warm schedule.'
    'Functions'              = 'Use Flex/Consumption not a dedicated plan; ensure timers aren''t over-firing; right-size the always-ready instances.'
    'Azure Monitor'          = 'Lower Log Analytics retention; add a daily ingestion cap; cut verbose diagnostic categories; sample App Insights.'
    'Log Analytics'          = 'Lower retention, add a daily cap, drop noisy tables.'
    'Application Insights'   = 'Enable sampling; reduce retention; disable unused Smart Detection / continuous export.'
    'Azure OpenAI'           = 'Right-size deployed model + TPM; switch to cheaper/mini models where quality allows; batch or cache prompts.'
    'Cognitive Services'     = 'Right-size the tier/TPM; use a cheaper model; cache responses.'
    'Storage'                = 'Move cool/archive data off Hot; add lifecycle rules; purge old exports/snapshots; check redundancy (LRS vs GRS).'
    'Key Vault'              = 'Usually negligible; only revisit if operation counts spike.'
    'Automation'             = 'Trim runbook frequency; disable unused schedules; check for stuck/looping jobs.'
    'Logic Apps'             = 'Reduce trigger frequency (the keep-warm poller); move to Consumption; consolidate workflows.'
    'Bandwidth'              = 'Reduce cross-region egress; co-locate resources; cache responses.'
    'Virtual Network'        = 'Remove unused public IPs / NAT gateways / private endpoints.'
}
function Get-Lever([string]$svc){
    foreach ($k in $leverMap.Keys) { if ($svc -like "*$k*") { return $leverMap[$k] } }
    return 'Review usage/tier; scale down or turn off when idle.'
}

# services trending over last month (the actionable list), biggest overspend first
$overspend = @($services | Where-Object { $_.Delta -gt 0.01 -and $_.Projected -gt 0.05 } | Sort-Object Delta -Descending)

# --- JSON output --------------------------------------------------------------
if ($Json) {
    [pscustomobject]@{
        resourceGroup = $ResourceGroup
        subscription  = $Subscription
        generated     = $now.ToString('s')
        currency      = 'USD'
        window        = @{ anchorDay = $anchor
                            current  = "$($curStart.ToString('yyyy-MM-dd')) to $($curEnd.ToString('yyyy-MM-dd')) (cycle)"
                            currentToDate = "$($curStart.ToString('yyyy-MM-dd')) to $($now.ToString('yyyy-MM-dd'))"
                            previous = "$($prevStart.ToString('yyyy-MM-dd')) to $($prevEnd.ToString('yyyy-MM-dd'))"
                            daysElapsed = [Math]::Round($elapsed,2); daysInCycle = $daysInCycle }
        totals        = @{ lastMonth = $totalPrev; mtd = $totalMtd; projected = $totalProj; delta = $totalDelta }
        services      = @($services)
        resources     = @($resources)
        overspend     = @($overspend | ForEach-Object {
                            [pscustomobject]@{ service = $_.Service; delta = $_.Delta; projected = $_.Projected
                                               lastMonth = $_.LastMonth; lever = (Get-Lever $_.Service) } })
    } | ConvertTo-Json -Depth 8
    return
}

# --- HTML report --------------------------------------------------------------
function Enc([object]$s){ [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Money([double]$v){ '$' + $v.ToString('N2') }
function DeltaCell([double]$d){
    if ($d -gt 0.01)      { "<td class='num up'>+$($d.ToString('N2'))</td>" }
    elseif ($d -lt -0.01) { "<td class='num down'>$($d.ToString('N2'))</td>" }
    else                  { "<td class='num'>0.00</td>" }
}

$svcRows = foreach ($s in $services) {
    "<tr><td>$(Enc $s.Service)</td><td class='num'>$(Money $s.LastMonth)</td>" +
    "<td class='num'>$(Money $s.MTD)</td><td class='num'>$(Money $s.Projected)</td>$(DeltaCell $s.Delta)</tr>"
}
$resRows = foreach ($r in ($resources | Select-Object -First 20)) {
    "<tr><td>$(Enc $r.Resource)</td><td class='num'>$(Money $r.MTD)</td></tr>"
}
$overRows = foreach ($o in $overspend) {
    "<tr><td>$(Enc $o.Service)</td><td class='num up'>+$($o.Delta.ToString('N2'))</td>" +
    "<td class='num'>$(Money $o.Projected)</td><td class='lever'>$(Enc (Get-Lever $o.Service))</td></tr>"
}
if (-not $overRows) { $overRows = "<tr><td colspan='4' class='ok'>&#10003; Nothing is projected to exceed last cycle. On track.</td></tr>" }

$trendClass = if ($totalDelta -gt 0.01) { 'up' } elseif ($totalDelta -lt -0.01) { 'down' } else { '' }
$trendWord  = if ($totalDelta -gt 0.01) { 'OVER' } elseif ($totalDelta -lt -0.01) { 'under' } else { 'on par with' }
$gen = $now.ToString('yyyy-MM-dd HH:mm')

$html = @"
<!doctype html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>WebPortfolio - Azure Cost Analysis</title>
<style>
  :root{ --bg:#f5f5fb; --card:#fff; --ink:#1a1a2e; --muted:#6b6b80; --line:#e3e3ee;
         --accent:#5b5bd6; --accent2:#8b5cf6;
         --up:#c0362c; --upBg:#fdeceb; --down:#1f7a4d; --downBg:#e7f6ee; --ok:#1f7a4d; }
  @media (prefers-color-scheme:dark){
    :root{ --bg:#14141c; --card:#1d1d28; --ink:#ececf5; --muted:#9a9ab0; --line:#2c2c3a;
           --up:#ff8a80; --upBg:#3a1512; --down:#7fe0ab; --downBg:#10301f; --ok:#7fe0ab; } }
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);
    font:15px/1.55 'Segoe UI',system-ui,sans-serif;padding:28px 32px}
  h1{font-size:23px;margin:0 0 2px} .sub{color:var(--muted);margin:0 0 20px;font-size:13px}
  .cards{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:26px}
  .c{background:var(--card);border:1px solid var(--line);padding:14px 18px;min-width:150px}
  .c .n{font-size:26px;font-weight:700;line-height:1} .c .l{color:var(--muted);font-size:12px;
    text-transform:uppercase;letter-spacing:.04em;margin-top:4px}
  .c.accent{border-top:3px solid var(--accent)}
  .c.up{border-top:3px solid var(--up)} .c.down{border-top:3px solid var(--down)}
  section{background:var(--card);border:1px solid var(--line);padding:16px 20px;margin-bottom:16px}
  h2{font-size:16px;margin:0 0 12px}
  table{width:100%;border-collapse:collapse;border:1px solid var(--line);font-size:13.5px}
  th,td{padding:8px 12px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
  th{font-size:11.5px;text-transform:uppercase;letter-spacing:.03em;color:var(--muted)}
  td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
  td.up{color:var(--up);font-weight:600} td.down{color:var(--down);font-weight:600}
  td.lever{font-size:12.5px;color:var(--muted)}
  tbody tr:hover{background:rgba(127,127,150,.06)}
  .ok{color:var(--ok)} .big.up{color:var(--up)} .big.down{color:var(--down)}
  .note{margin-top:20px;color:var(--muted);font-size:12.5px;max-width:960px}
  code{background:rgba(127,127,150,.14);padding:1px 6px;font-size:12.5px}
</style></head><body>
  <h1>WebPortfolio &mdash; Azure Cost Analysis</h1>
  <p class='sub'>Resource group <code>$(Enc $ResourceGroup)</code> &middot; generated $gen &middot;
     billing cycle (day $anchor&ndash;$($anchor-1)) <strong>$($curStart.ToString('MMM d'))&ndash;$($curEnd.ToString('MMM d'))</strong>,
     $([Math]::Round($elapsed,1)) of $daysInCycle days elapsed &middot; all figures USD, read-only</p>
  <div class='cards'>
    <div class='c'><div class='n'>$(Money $totalPrev)</div><div class='l'>Last cycle (actual)</div></div>
    <div class='c accent'><div class='n'>$(Money $totalMtd)</div><div class='l'>This cycle to date</div></div>
    <div class='c $trendClass'><div class='n'>$(Money $totalProj)</div><div class='l'>Projected this cycle</div></div>
    <div class='c $trendClass'><div class='n big $trendClass'>$(if($totalDelta -ge 0){'+'})$($totalDelta.ToString('N2'))</div><div class='l'>Projected vs last cycle</div></div>
  </div>

  <section>
    <h2>Where we're trending over last cycle</h2>
    <table><thead><tr><th>Service</th><th class='num'>Projected &Delta;</th><th class='num'>Projected</th><th>Reduction lever</th></tr></thead>
    <tbody>$($overRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>By service &mdash; last cycle vs this cycle (projected)</h2>
    <table><thead><tr><th>Service</th><th class='num'>Last cycle</th><th class='num'>To date</th><th class='num'>Projected</th><th class='num'>&Delta; vs last</th></tr></thead>
    <tbody>$($svcRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>By resource &mdash; this cycle to date (top 20)</h2>
    <table><thead><tr><th>Resource</th><th class='num'>To date</th></tr></thead>
    <tbody>$($resRows -join "`n")</tbody></table>
  </section>

  <p class='note'><strong>How to read:</strong> the invoice <strong>billing cycle</strong> runs
  day $anchor &rarr; day $($anchor-1) of the next month (not the calendar month). <em>Projected</em> =
  this cycle's run-rate (spend so far &divide; days elapsed &times; days in cycle). A positive
  <em>&Delta; vs last</em> means that service is pacing to cost more than last full cycle &mdash;
  those are the rows to attack, with a concrete lever suggested. Projections are noisy in the first
  few days of a cycle. Read-only &mdash; nothing was changed.</p>
</body></html>
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp    = $now.ToString('yyyyMMdd-HHmmss')
$htmlPath = Join-Path $OutDir "azure-cost-$stamp.html"
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

# --- console summary ----------------------------------------------------------
Write-Host ""
Write-Host "Azure cost - $ResourceGroup (USD) - billing cycle day $anchor->$($anchor-1)" -ForegroundColor Cyan
Write-Host ("  Cycle             : {0} -> {1}" -f $curStart.ToString('MMM d'), $curEnd.ToString('MMM d'))
Write-Host ("  Last cycle actual : {0}" -f (Money $totalPrev))
Write-Host ("  This cycle to date: {0}  ({1:N1}/{2} days)" -f (Money $totalMtd), $elapsed, $daysInCycle)
$projColor = if ($totalDelta -gt 0.01) { 'Red' } elseif ($totalDelta -lt -0.01) { 'Green' } else { 'Gray' }
$deltaStr  = if ($totalDelta -ge 0) { "+$($totalDelta.ToString('N2'))" } else { $totalDelta.ToString('N2') }
Write-Host ("  Projected total   : {0}  ({1} vs last cycle, trending {2})" -f (Money $totalProj), $deltaStr, $trendWord) -ForegroundColor $projColor
if ($overspend.Count -gt 0) {
    Write-Host "  Trending over last cycle:"
    foreach ($o in $overspend) {
        Write-Host ("    ! {0,-26} +{1,7:N2}  -> {2}" -f $o.Service, $o.Delta, (Get-Lever $o.Service)) -ForegroundColor Yellow
    }
} else {
    Write-Host "  Nothing projected over last cycle - on track." -ForegroundColor Green
}
Write-Host "Wrote $htmlPath" -ForegroundColor Green
if (-not $NoOpen) { Start-Process $htmlPath }
