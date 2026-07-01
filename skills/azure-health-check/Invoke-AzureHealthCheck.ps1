<#
.SYNOPSIS
  Read-only health check for an Azure subscription over the last N days.

.DESCRIPTION
  Scans the WHOLE subscription for problems that tend to sneak in unnoticed - the
  kind of thing that quietly raises the bill or breaks scale-to-zero - and renders a
  self-contained HTML report (house style, auto-opens). Everything is read-only.

  Checks:
    H1  Cost anomalies      - daily cost by service and by resource; flags step-ups
                              (a service/resource that recently started costing much
                              more than its baseline earlier in the window).
    H2  Notable changes     - Activity Log create/update/delete/scale writes (who,
                              what, when), correlated to H1 cost jumps on the same
                              resource so "what changed" is obvious.
    H3  Failed operations   - Activity Log entries with status = Failed.
    H4  Scale-to-zero regr. - Container Apps whose minReplicas > 0 (won't scale to
                              zero), cross-referenced with resumed cost.
    H5  Advisor             - high-impact Cost + HighAvailability recommendations.

  Auth: whatever `az account show` is signed into.

.PARAMETER Days          Lookback window in days (default 7).
.PARAMETER Subscription  Subscription id; defaults to the current az account.
.PARAMETER Json          Emit a machine-readable summary instead of HTML.
.PARAMETER NoOpen        Don't open the HTML in a browser.
.PARAMETER OutDir        Where to write the HTML report.
.PARAMETER AdvisorIgnore Extra regex patterns to suppress in H5 (added to the
                         built-in ignore list of low-value HA upsells).
.PARAMETER ShowIgnored   Include the normally-suppressed H5 recommendations.
#>
[CmdletBinding()]
param(
    [int]$Days = 7,
    [string]$Subscription,
    [switch]$Json,
    [switch]$NoOpen,
    [string]$OutDir = (Join-Path $env:TEMP 'azure-health-check'),
    [string[]]$AdvisorIgnore = @(),
    [switch]$ShowIgnored
)

# --- H5 Advisor ignore list ---------------------------------------------------
# Low-value recommendations we deliberately don't surface: they're all "spend
# MORE for enterprise HA" upsells (extra instances, higher tiers, multi-zone
# redundancy) that don't fit a single-region personal subscription and run
# counter to keeping cost down. Anything genuinely actionable (API retirements,
# free health checks, service-health alerts) is NOT in this list.
$AdvisorIgnoreDefault = @(
    'Set minimum instance count for App Service',
    'Use Standard or Premium tier',
    'Use zone-supported App Service Plan',
    'Enable zone redundancy'                       # storage, SQL, managed env, etc.
)
$AdvisorIgnorePatterns = @($AdvisorIgnoreDefault + $AdvisorIgnore)

$ErrorActionPreference = 'Stop'
function Say([string]$m,[string]$c='Cyan'){ if (-not $Json) { Write-Host $m -ForegroundColor $c } }

# --- resolve subscription -----------------------------------------------------
if (-not $Subscription) {
    $Subscription = (az account show --query id -o tsv 2>$null)
    if (-not $Subscription) { throw "Not signed in to Azure. Run 'az login'." }
}
$subName = (az account show --query name -o tsv 2>$null)
$now   = Get-Date
$from  = $now.AddDays(-[Math]::Abs($Days))
function Fmt-Iso([datetime]$d){ $d.ToString('yyyy-MM-ddTHH:mm:ssZ') }

# ==============================================================================
# H1 - Cost anomalies (daily cost by dimension)
# ==============================================================================
# POSTs a Cost Management query at subscription scope, granularity Daily, grouped
# by $Dimension. Returns list of [pscustomobject]{ Date; Key; Cost }.
function Invoke-CostDaily {
    param([datetime]$From,[datetime]$To,[string]$Dimension)
    $uri = "https://management.azure.com/subscriptions/$Subscription/providers/Microsoft.CostManagement/query?api-version=2023-03-01"
    $body = @{
        type       = 'ActualCost'
        timeframe  = 'Custom'
        timePeriod = @{ from = (Fmt-Iso $From); to = (Fmt-Iso $To) }
        dataset    = @{
            granularity = 'Daily'
            aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
            grouping    = @(@{ type = 'Dimension'; name = $Dimension })
        }
    } | ConvertTo-Json -Depth 12

    $rows = New-Object System.Collections.Generic.List[object]
    do {
        $tmp = New-TemporaryFile; $body | Out-File -LiteralPath $tmp -Encoding utf8
        $errFile = New-TemporaryFile; $raw = $null
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            $raw = az rest --method post --uri $uri --body "@$tmp" --headers "Content-Type=application/json" -o json 2>$errFile
            if ($raw) { break }
            $err = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
            if ($err -match '429|Too Many Requests|throttl') { Start-Sleep -Seconds ([Math]::Min(30, 5*$attempt)); continue }
            throw "Cost query failed: $((""$err"").Trim())"
        }
        Remove-Item -LiteralPath $tmp,$errFile -Force -ErrorAction SilentlyContinue
        if (-not $raw) { throw "Cost query kept getting throttled (429) - wait a minute and retry." }
        $resp = $raw | ConvertFrom-Json
        $cols = @($resp.properties.columns.name)
        $ci   = [Array]::IndexOf($cols,'Cost')
        $di   = [Array]::IndexOf($cols,$Dimension)
        $ti   = [Array]::IndexOf($cols,'UsageDate')
        foreach ($r in $resp.properties.rows) {
            $d = if ($ti -ge 0) { [string]$r[$ti] } else { '' }   # yyyymmdd int
            $k = if ($di -ge 0) { [string]$r[$di] } else { '(total)' }
            $rows.Add([pscustomobject]@{ Date = $d; Key = $k; Cost = [double]$r[$ci] })
        }
        $uri = $resp.properties.nextLink
    } while ($uri)
    return $rows
}

# Given a per-key daily series, split the window in half and flag keys whose recent
# half costs materially more than the earlier half (a step-up / regression).
function Find-CostStepUps {
    param($Rows,[double]$MinDeltaPerDay = 0.03,[double]$Ratio = 1.4)
    $dates = @($Rows | Select-Object -ExpandProperty Date -Unique | Sort-Object)
    if ($dates.Count -lt 4) { return @() }
    $mid = $dates[[int][Math]::Floor($dates.Count/2)]
    $out = foreach ($g in ($Rows | Group-Object Key)) {
        $early = @($g.Group | Where-Object { $_.Date -lt $mid })
        $late  = @($g.Group | Where-Object { $_.Date -ge $mid })
        $eDays = @($dates | Where-Object { $_ -lt $mid }).Count
        $lDays = @($dates | Where-Object { $_ -ge $mid }).Count
        if ($eDays -eq 0 -or $lDays -eq 0) { continue }
        $eAvg = (($early | Measure-Object Cost -Sum).Sum) / $eDays
        $lAvg = (($late  | Measure-Object Cost -Sum).Sum) / $lDays
        $delta = $lAvg - $eAvg
        $isStep = ($delta -ge $MinDeltaPerDay) -and (($eAvg -le 0.001) -or ($lAvg -ge $eAvg * $Ratio))
        if ($isStep) {
            [pscustomobject]@{
                Key           = $g.Name
                EarlyAvgPerDay= [Math]::Round($eAvg,3)
                LateAvgPerDay = [Math]::Round($lAvg,3)
                DeltaPerDay   = [Math]::Round($delta,3)
                WindowExtra   = [Math]::Round($delta * $dates.Count,2)   # rough $ impact over window
                Total         = [Math]::Round((($g.Group | Measure-Object Cost -Sum).Sum),2)
            }
        }
    }
    return @($out | Sort-Object DeltaPerDay -Descending)
}

Say "Querying Cost Management (daily, last $Days days)..."
$svcDaily = @(); $resDaily = @(); $svcSteps = @(); $resSteps = @(); $dailyTotals = @()
$costErr = $null
try {
    $svcDaily = Invoke-CostDaily -From $from -To $now -Dimension 'ServiceName'
    Start-Sleep -Seconds 2
    $resDaily = Invoke-CostDaily -From $from -To $now -Dimension 'ResourceId'
    $svcSteps = Find-CostStepUps -Rows $svcDaily
    $resSteps = Find-CostStepUps -Rows $resDaily
    $dailyTotals = @($svcDaily | Group-Object Date | ForEach-Object {
        [pscustomobject]@{ Date = $_.Name; Cost = [Math]::Round((($_.Group|Measure-Object Cost -Sum).Sum),2) }
    } | Sort-Object Date)
} catch { $costErr = $_.Exception.Message; Say "  cost check failed: $costErr" 'Yellow' }
# leaf-name helper for resource ids
function Leaf([string]$id){ if ($id) { ($id -split '/')[-1] } else { $id } }
$resSteps = @($resSteps | ForEach-Object { $_ | Add-Member -NotePropertyName Name -NotePropertyValue (Leaf $_.Key) -PassThru })

# ==============================================================================
# H2 / H3 - Activity Log (notable writes + failures)
# ==============================================================================
Say "Reading Activity Log..."
$writes = @(); $failed = @(); $alErr = $null
try {
    $raw = az monitor activity-log list --start-time (Fmt-Iso $from) --max-events 1000 -o json 2>$null | ConvertFrom-Json
    foreach ($e in $raw) {
        $op   = $e.operationName.value
        $opl  = if ($e.operationName.localizedValue) { $e.operationName.localizedValue } else { $op }
        $st   = $e.status.value
        $rid  = $e.resourceId
        $obj  = [pscustomobject]@{
            Time     = ([datetime]$e.eventTimestamp).ToString('MMM d HH:mm')
            TimeRaw  = $e.eventTimestamp
            Caller   = $e.caller
            Operation= $opl
            OpValue  = $op
            Resource = (Leaf $rid)
            ResourceId = $rid
            Status   = $st
        }
        if ($st -eq 'Failed') { $failed += $obj }
        # notable management writes: create/update/delete/action/scale, exclude read/list/noise
        elseif ($op -match '/(write|delete|action)$' -and
                $op -notmatch 'read|list' -and
                $op -notmatch 'Microsoft\.(Insights|Advisor|Security|Resources/deployments|Authorization)/') {
            $writes += $obj
        }
    }
} catch { $alErr = $_.Exception.Message; Say "  activity log failed: $alErr" 'Yellow' }
# de-dupe notable writes to distinct resource+operation+caller (keep most recent)
$writes = @($writes | Sort-Object TimeRaw -Descending |
    Group-Object { "$($_.ResourceId)|$($_.OpValue)|$($_.Caller)" } |
    ForEach-Object { $_.Group[0] } | Sort-Object TimeRaw -Descending)
$failed = @($failed | Sort-Object TimeRaw -Descending |
    Group-Object { "$($_.ResourceId)|$($_.OpValue)|$($_.Caller)" } |
    ForEach-Object { $_.Group[0] } | Sort-Object TimeRaw -Descending)

# correlate: which notable writes touch a resource that also stepped up in cost
$stepResIds = @($resSteps | Select-Object -ExpandProperty Key)
foreach ($w in $writes) {
    $hit = $false
    foreach ($sid in $stepResIds) { if ($sid -and $w.ResourceId -and ($w.ResourceId -eq $sid)) { $hit = $true; break } }
    $w | Add-Member -NotePropertyName CostLinked -NotePropertyValue $hit -Force
}
$writes = @($writes | Sort-Object @{e={$_.CostLinked};d=$true}, @{e={$_.TimeRaw};d=$true})

# ==============================================================================
# H4 - scale-to-zero regressions (Container Apps minReplicas > 0)
# ==============================================================================
Say "Checking Container Apps scale settings..."
$scaleIssues = @(); $caErr = $null
try {
    $cas = az containerapp list -o json 2>$null | ConvertFrom-Json
    foreach ($c in $cas) {
        $min = $c.properties.template.scale.minReplicas
        if ($null -eq $min) { $min = 0 }
        if ([int]$min -gt 0) {
            $scaleIssues += [pscustomobject]@{
                Name = $c.name; ResourceGroup = $c.resourceGroup; MinReplicas = [int]$min
                MaxReplicas = $c.properties.template.scale.maxReplicas
            }
        }
    }
} catch { $caErr = $_.Exception.Message; Say "  container apps check skipped: $caErr" 'Yellow' }

# ==============================================================================
# H5 - Advisor (Cost + HighAvailability, high impact)
# ==============================================================================
Say "Reading Advisor recommendations..."
$advisor = @(); $advIgnored = @(); $advErr = $null
try {
    $recs = az advisor recommendation list -o json 2>$null | ConvertFrom-Json
    foreach ($r in $recs) {
        $cat = $r.category; $imp = $r.impact
        if (($cat -eq 'Cost' -or $cat -eq 'HighAvailability') -and $imp -eq 'High') {
            $prob = $r.shortDescription.problem
            $rec  = [pscustomobject]@{
                Category = $cat; Impact = $imp
                Problem  = $prob
                Resource = (Leaf $r.resourceMetadata.resourceId)
            }
            $ignore = $false
            foreach ($pat in $AdvisorIgnorePatterns) { if ($prob -match $pat) { $ignore = $true; break } }
            if ($ignore -and -not $ShowIgnored) { $advIgnored += $rec } else { $advisor += $rec }
        }
    }
} catch { $advErr = $_.Exception.Message; Say "  advisor check skipped: $advErr" 'Yellow' }
$advisor = @($advisor | Sort-Object Category, Resource)
$advIgnored = @($advIgnored | Sort-Object Category, Resource)

# ==============================================================================
# Severity roll-up
# ==============================================================================
$issues = @()
if ($svcSteps.Count -or $resSteps.Count) { $issues += 'cost' }
if ($failed.Count)      { $issues += 'failed' }
if ($scaleIssues.Count) { $issues += 'scale' }
if ($advisor.Count)     { $issues += 'advisor' }
$issueCount = $svcSteps.Count + $resSteps.Count + $failed.Count + $scaleIssues.Count + $advisor.Count

# ==============================================================================
# JSON output
# ==============================================================================
if ($Json) {
    [pscustomobject]@{
        subscription = $Subscription
        subscriptionName = $subName
        generated    = $now.ToString('s')
        windowDays   = $Days
        window       = @{ from = $from.ToString('yyyy-MM-dd'); to = $now.ToString('yyyy-MM-dd') }
        issueCount   = $issueCount
        errors       = @{ cost = $costErr; activityLog = $alErr; containerApps = $caErr; advisor = $advErr }
        h1_costStepUps = @{
            byService  = @($svcSteps)
            byResource = @($resSteps | Select-Object Name,Key,EarlyAvgPerDay,LateAvgPerDay,DeltaPerDay,WindowExtra,Total)
            dailyTotals= @($dailyTotals)
        }
        h2_notableWrites = @($writes | Select-Object Time,Caller,Operation,Resource,Status,CostLinked)
        h3_failed        = @($failed | Select-Object Time,Caller,Operation,Resource,Status)
        h4_scaleIssues   = @($scaleIssues)
        h5_advisor       = @($advisor)
        h5_advisorSuppressed = @($advIgnored)
    } | ConvertTo-Json -Depth 8
    return
}

# ==============================================================================
# HTML report (house style)
# ==============================================================================
function Enc([object]$s){ [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Money([double]$v){ '$' + $v.ToString('N2') }

$svcStepRows = foreach ($s in $svcSteps) {
    "<tr><td>$(Enc $s.Key)</td><td class='num'>$(Money $s.EarlyAvgPerDay)</td><td class='num'>$(Money $s.LateAvgPerDay)</td><td class='num up'>+$($s.DeltaPerDay.ToString('N3'))</td><td class='num'>$(Money $s.Total)</td></tr>"
}
if (-not $svcStepRows) { $svcStepRows = "<tr><td colspan='5' class='ok'>&#10003; No service-level cost step-ups.</td></tr>" }

$resStepRows = foreach ($s in $resSteps) {
    "<tr><td>$(Enc $s.Name)</td><td class='num'>$(Money $s.EarlyAvgPerDay)</td><td class='num'>$(Money $s.LateAvgPerDay)</td><td class='num up'>+$($s.DeltaPerDay.ToString('N3'))</td><td class='num'>$(Money $s.Total)</td></tr>"
}
if (-not $resStepRows) { $resStepRows = "<tr><td colspan='5' class='ok'>&#10003; No resource-level cost step-ups.</td></tr>" }

$writeRows = foreach ($w in ($writes | Select-Object -First 40)) {
    $flag = if ($w.CostLinked) { "<span class='tag'>cost-linked</span>" } else { '' }
    "<tr><td>$(Enc $w.Time)</td><td>$(Enc $w.Caller)</td><td>$(Enc $w.Operation) $flag</td><td>$(Enc $w.Resource)</td></tr>"
}
if (-not $writeRows) { $writeRows = "<tr><td colspan='4' class='ok'>&#10003; No notable management writes in this window.</td></tr>" }

$failRows = foreach ($f in ($failed | Select-Object -First 40)) {
    "<tr><td>$(Enc $f.Time)</td><td>$(Enc $f.Caller)</td><td>$(Enc $f.Operation)</td><td>$(Enc $f.Resource)</td></tr>"
}
if (-not $failRows) { $failRows = "<tr><td colspan='4' class='ok'>&#10003; No failed operations.</td></tr>" }

$scaleRows = foreach ($s in $scaleIssues) {
    "<tr><td>$(Enc $s.Name)</td><td>$(Enc $s.ResourceGroup)</td><td class='num up'>$($s.MinReplicas)</td><td class='num'>$(Enc $s.MaxReplicas)</td></tr>"
}
if (-not $scaleRows) { $scaleRows = "<tr><td colspan='4' class='ok'>&#10003; All Container Apps scale to zero (minReplicas = 0).</td></tr>" }

$advRows = foreach ($a in $advisor) {
    "<tr><td>$(Enc $a.Category)</td><td>$(Enc $a.Problem)</td><td>$(Enc $a.Resource)</td></tr>"
}
if (-not $advRows) { $advRows = "<tr><td colspan='3' class='ok'>&#10003; No high-impact Cost/HA recommendations.</td></tr>" }

$verdictClass = if ($issueCount -gt 0) { 'up' } else { 'down' }
$verdictWord  = if ($issueCount -gt 0) { "$issueCount finding$(if($issueCount -ne 1){'s'})" } else { 'All clear' }
$gen = $now.ToString('yyyy-MM-dd HH:mm')

$html = @"
<!doctype html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Azure Health Check</title>
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
  h2{font-size:16px;margin:0 0 4px} .hint{color:var(--muted);font-size:12.5px;margin:0 0 12px}
  table{width:100%;border-collapse:collapse;border:1px solid var(--line);font-size:13.5px}
  th,td{padding:8px 12px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
  th{font-size:11.5px;text-transform:uppercase;letter-spacing:.03em;color:var(--muted)}
  td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
  td.up{color:var(--up);font-weight:600} td.down{color:var(--down);font-weight:600}
  tbody tr:hover{background:rgba(127,127,150,.06)}
  .ok{color:var(--ok)} .big.up{color:var(--up)} .big.down{color:var(--down)}
  .tag{background:var(--upBg);color:var(--up);font-size:11px;padding:1px 6px;margin-left:6px;font-weight:600}
  .note{margin-top:20px;color:var(--muted);font-size:12.5px;max-width:960px}
  code{background:rgba(127,127,150,.14);padding:1px 6px;font-size:12.5px}
</style></head><body>
  <h1>Azure Health Check</h1>
  <p class='sub'>Subscription <code>$(Enc $subName)</code> &middot; last <strong>$Days days</strong>
     ($($from.ToString('MMM d')) &ndash; $($now.ToString('MMM d'))) &middot; generated $gen &middot; read-only</p>
  <div class='cards'>
    <div class='c $verdictClass'><div class='n big $verdictClass'>$verdictWord</div><div class='l'>Overall</div></div>
    <div class='c'><div class='n'>$($svcSteps.Count + $resSteps.Count)</div><div class='l'>Cost step-ups</div></div>
    <div class='c'><div class='n'>$($failed.Count)</div><div class='l'>Failed ops</div></div>
    <div class='c'><div class='n'>$($scaleIssues.Count)</div><div class='l'>Scale regressions</div></div>
    <div class='c'><div class='n'>$($advisor.Count)</div><div class='l'>Advisor (high)</div></div>
  </div>

  <section>
    <h2>H1 &middot; Cost step-ups by service</h2>
    <p class='hint'>Services whose recent daily cost is materially above their earlier baseline in this window.</p>
    <table><thead><tr><th>Service</th><th class='num'>Early $/day</th><th class='num'>Recent $/day</th><th class='num'>&Delta;/day</th><th class='num'>Window total</th></tr></thead>
    <tbody>$($svcStepRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>H1 &middot; Cost step-ups by resource</h2>
    <p class='hint'>The specific resources driving any step-up &mdash; the "what" behind the service numbers.</p>
    <table><thead><tr><th>Resource</th><th class='num'>Early $/day</th><th class='num'>Recent $/day</th><th class='num'>&Delta;/day</th><th class='num'>Window total</th></tr></thead>
    <tbody>$($resStepRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>H2 &middot; Notable changes (who changed what)</h2>
    <p class='hint'>Create/update/delete/scale writes from the Activity Log. <span class='tag'>cost-linked</span> marks a change on a resource that also stepped up in cost.</p>
    <table><thead><tr><th>When</th><th>Caller</th><th>Operation</th><th>Resource</th></tr></thead>
    <tbody>$($writeRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>H3 &middot; Failed operations</h2>
    <p class='hint'>Activity Log entries with status = Failed (failed deploys, throttled ops, errors).</p>
    <table><thead><tr><th>When</th><th>Caller</th><th>Operation</th><th>Resource</th></tr></thead>
    <tbody>$($failRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>H4 &middot; Scale-to-zero regressions</h2>
    <p class='hint'>Container Apps with minReplicas &gt; 0 keep at least one replica running (they won't scale to zero).</p>
    <table><thead><tr><th>Container App</th><th>Resource group</th><th class='num'>Min replicas</th><th class='num'>Max replicas</th></tr></thead>
    <tbody>$($scaleRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>H5 &middot; Advisor (high-impact Cost &amp; HA)</h2>
    <p class='hint'>Azure Advisor recommendations filtered to high-impact Cost and HighAvailability.$(if($advIgnored.Count){" <em>$($advIgnored.Count) low-value HA upsell$(if($advIgnored.Count -ne 1){'s'}) suppressed &mdash; re-run with <code>-ShowIgnored</code> to see them.</em>"})</p>
    <table><thead><tr><th>Category</th><th>Recommendation</th><th>Resource</th></tr></thead>
    <tbody>$($advRows -join "`n")</tbody></table>
  </section>

  <p class='note'><strong>How to read:</strong> a <em>cost step-up</em> compares the earlier half of the
  window against the recent half &mdash; a resource that was ~$0/day then jumped is exactly the pattern
  that quietly raises the bill. Cross-check H2 for the change that caused it. Everything here is
  <strong>read-only</strong>; nothing was modified. Activity Log retains ~90 days; Advisor refreshes periodically.</p>
</body></html>
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp    = $now.ToString('yyyyMMdd-HHmmss')
$htmlPath = Join-Path $OutDir "azure-health-$stamp.html"
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

# --- console summary ----------------------------------------------------------
Write-Host ""
Write-Host "Azure health check - $subName (last $Days days)" -ForegroundColor Cyan
Write-Host ("  Cost step-ups   : {0} service, {1} resource" -f $svcSteps.Count, $resSteps.Count)
Write-Host ("  Failed ops      : {0}" -f $failed.Count)
Write-Host ("  Scale regr.     : {0}" -f $scaleIssues.Count)
Write-Host ("  Advisor (high)  : {0}{1}" -f $advisor.Count, $(if($advIgnored.Count){" ($($advIgnored.Count) HA upsells suppressed)"}))
if ($resSteps.Count) {
    Write-Host "  Top cost step-ups:" -ForegroundColor Yellow
    foreach ($s in ($resSteps | Select-Object -First 5)) {
        Write-Host ("    ! {0,-34} {1,6:N3}/day -> {2,6:N3}/day" -f $s.Name, $s.EarlyAvgPerDay, $s.LateAvgPerDay) -ForegroundColor Yellow
    }
}
$col = if ($issueCount -gt 0) { 'Yellow' } else { 'Green' }
Write-Host ("  Overall         : {0}" -f $verdictWord) -ForegroundColor $col
Write-Host "Wrote $htmlPath" -ForegroundColor Green
if (-not $NoOpen) { Start-Process $htmlPath }
