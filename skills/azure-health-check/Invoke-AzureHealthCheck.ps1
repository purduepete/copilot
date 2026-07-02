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
    H5  Advisor             - high-impact Cost + HighAvailability recommendations
                              (low-value HA upsells suppressed by default).
    H6  Scheduled automation- Logic App run history: failed/cancelled runs, and
                              Enabled workflows with zero runs (missed schedule).
                              Catches data-plane failures the Activity Log misses.
    H7  Function Apps       - Function execution failures via Application Insights
                              (classic or workspace-based), per function operation.

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
# H6 - Scheduled automation (Logic App runs: failures + missed schedules)
# ==============================================================================
# The Activity Log (H3) is control-plane only, so a Logic App whose *runs* fail -
# or a scheduled workflow that silently stops firing - never shows up there. This
# check reads each workflow's run history within the window and flags:
#   * any Failed runs, and
#   * an Enabled workflow with ZERO runs in the window (a missed-schedule signal;
#     may be a false positive for genuinely infrequent workflows).
Say "Checking Logic App run history..."
$autoIssues = @(); $autoAll = @(); $autoErr = $null
try {
    $wfList = az resource list --resource-type Microsoft.Logic/workflows -o json 2>$null | ConvertFrom-Json
    foreach ($wf in $wfList) {
        # workflow state (Enabled/Disabled) - a disabled workflow legitimately won't run
        $state = 'Unknown'
        try {
            $wfObj = az rest --method get --uri ("https://management.azure.com" + $wf.id + "?api-version=2016-06-01") 2>$null | ConvertFrom-Json
            if ($wfObj.properties.state) { $state = $wfObj.properties.state }
        } catch {}
        # runs within the window (paged, capped)
        $runsUri = "https://management.azure.com" + $wf.id + "/runs?api-version=2016-06-01&`$top=100&`$filter=startTime ge " + (Fmt-Iso $from)
        $runs = New-Object System.Collections.Generic.List[object]
        $pages = 0
        do {
            $rr = $null
            for ($a=1; $a -le 4; $a++) {
                $rr = az rest --method get --uri $runsUri 2>$null
                if ($rr) { break }
                Start-Sleep -Seconds ([Math]::Min(20, 3*$a))
            }
            if (-not $rr) { break }
            $rp = $rr | ConvertFrom-Json
            foreach ($run in $rp.value) { $runs.Add($run) }
            $runsUri = $rp.nextLink
            $pages++
        } while ($runsUri -and $pages -lt 10)

        $total = $runs.Count
        $failed = @($runs | Where-Object { $_.properties.status -in @('Failed','Cancelled') })
        $lastRun = @($runs | Sort-Object { $_.properties.startTime } -Descending | Select-Object -First 1)
        $lastStatus = if ($lastRun) { $lastRun[0].properties.status } else { '(none)' }
        $lastTime   = if ($lastRun) { ([datetime]$lastRun[0].properties.startTime).ToString('MMM d HH:mm') } else { '' }

        $verdict = 'ok'
        if ($failed.Count -gt 0)                  { $verdict = 'failed' }
        elseif ($total -eq 0 -and $state -eq 'Enabled') { $verdict = 'norun' }

        $row = [pscustomobject]@{
            Name = $wf.name; ResourceGroup = $wf.resourceGroup; State = $state
            Runs = $total; Failed = $failed.Count; LastStatus = $lastStatus; LastRun = $lastTime
            Verdict = $verdict
        }
        $autoAll += $row
        if ($verdict -ne 'ok') { $autoIssues += $row }
    }
} catch { $autoErr = $_.Exception.Message; Say "  logic app run check skipped: $autoErr" 'Yellow' }
$autoAll    = @($autoAll    | Sort-Object @{e={$_.Verdict -eq 'ok'}}, Name)
$autoIssues = @($autoIssues | Sort-Object Name)

# ==============================================================================
# H7 - Function Apps (execution failures via Application Insights)
# ==============================================================================
# Function executions log to Application Insights, not the Activity Log. Each app
# has an AI component that is EITHER classic (query by appId) OR workspace-based
# (ingestionMode=LogAnalytics -> query the Log Analytics workspace, where the
# table is AppRequests instead of requests). We match each function app to its AI
# component by instrumentation key, run the right query, and flag any function
# operation with failed executions in the window.
Say "Checking Function App executions (App Insights)..."
$funcIssues = @(); $funcAll = @(); $funcErr = $null
function Get-Ikey([string]$s){ if ($s -match 'InstrumentationKey=([0-9a-fA-F-]+)') { $Matches[1] } else { $s } }

# DST-aware Pacific time formatting for report timestamps.
$ptZone = try { [TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time') }
          catch { try { [TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles') } catch { $null } }
function Format-PT($utcish){
    if (-not $utcish) { return '' }
    try {
        $u = ([datetime]$utcish).ToUniversalTime()
        if ($ptZone) { return ([TimeZoneInfo]::ConvertTimeFromUtc($u, $ptZone)).ToString('MMM d HH:mm') + ' PT' }
        return $u.ToString('MMM d HH:mm') + ' UTC'
    } catch { return [string]$utcish }
}

# Expand one NCRONTAB field ("*", "*/n", "a-b", "a,b", "a-b/n", "a") to a set of ints.
function Expand-CronField([string]$f, [int]$min, [int]$max){
    $vals = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($part in ($f -split ',')) {
        $step = 1; $range = $part
        if ($part -match '^(.*)/(\d+)$') { $range = $Matches[1]; $step = [int]$Matches[2] }
        if     ($range -eq '*')            { $lo = $min; $hi = $max }
        elseif ($range -match '^(\d+)-(\d+)$') { $lo = [int]$Matches[1]; $hi = [int]$Matches[2] }
        elseif ($range -match '^\d+$')      { $lo = [int]$range; $hi = [int]$range }
        else { continue }
        for ($v = $lo; $v -le $hi; $v += $step) { [void]$vals.Add($v) }
    }
    return ,$vals
}

# Estimate how many times a 6-field NCRONTAB schedule fires in [startUtc, endUtc].
# Returns $null when the schedule can't be parsed (so callers don't false-flag).
function Get-CronExpectedRuns([string]$cron, [datetime]$startUtc, [datetime]$endUtc){
    if (-not $cron) { return $null }
    $parts = ($cron -replace '\s+',' ').Trim() -split ' '
    # Azure NCRONTAB is 6-field (with seconds); a 5-field expression omits seconds.
    if     ($parts.Count -eq 5) { $parts = ,'0' + $parts }
    elseif ($parts.Count -ne 6) { return $null }
    $sec  = Expand-CronField $parts[0] 0 59
    $mins = Expand-CronField $parts[1] 0 59
    $hrs  = Expand-CronField $parts[2] 0 23
    $doms = Expand-CronField $parts[3] 1 31
    $mons = Expand-CronField $parts[4] 1 12
    $dows = Expand-CronField $parts[5] 0 6
    if ($dows.Contains(7)) { [void]$dows.Add(0) }
    $secCount = [Math]::Max(1, $sec.Count)
    $count = 0
    $t = $startUtc.AddSeconds(-$startUtc.Second).AddMilliseconds(-$startUtc.Millisecond)
    while ($t -le $endUtc) {
        if ($mins.Contains($t.Minute) -and $hrs.Contains($t.Hour) -and
            $mons.Contains($t.Month) -and $doms.Contains($t.Day) -and
            $dows.Contains([int]$t.DayOfWeek)) { $count += $secCount }
        $t = $t.AddMinutes(1)
    }
    return $count
}
try {
    $faList = az functionapp list -o json 2>$null | ConvertFrom-Json
    $comps  = az monitor app-insights component show -o json 2>$null | ConvertFrom-Json
    foreach ($fa in $faList) {
        $settings = az functionapp config appsettings list -n $fa.name -g $fa.resourceGroup -o json 2>$null | ConvertFrom-Json
        $cs   = ($settings | Where-Object { $_.name -eq 'APPLICATIONINSIGHTS_CONNECTION_STRING' }).value
        $ikey = ($settings | Where-Object { $_.name -eq 'APPINSIGHTS_INSTRUMENTATIONKEY' }).value
        $wantKey = if ($cs) { Get-Ikey $cs } elseif ($ikey) { $ikey } else { $null }
        $comp = $null
        if ($wantKey) {
            $match = $comps | Where-Object { $_.instrumentationKey -eq $wantKey } | Select-Object -First 1
            # the list projection omits workspaceResourceId/ingestionMode - re-show the
            # matched component individually to get reliable workspace + ingestion fields.
            if ($match) {
                $comp = az monitor app-insights component show --app $match.name -g $match.resourceGroup -o json 2>$null | ConvertFrom-Json
            }
        }

        $total = 0; $failed = 0; $lastRun = ''; $badOps = @(); $note = ''
        if (-not $comp) {
            $note = 'no App Insights linked'
        } else {
            $rows = $null
            if ($comp.ingestionMode -eq 'LogAnalytics' -and $comp.workspaceResourceId) {
                $wsGuid = az monitor log-analytics workspace show --ids $comp.workspaceResourceId --query customerId -o tsv 2>$null
                $q = "AppRequests | where TimeGenerated > ago(${Days}d) | summarize total=count(), failed=countif(Success==false), lastRun=max(TimeGenerated) by OperationName | order by failed desc, total desc"
                if ($wsGuid) {
                    $raw = az monitor log-analytics query -w $wsGuid --analytics-query $q -o json 2>$null
                    if ($raw) { $rows = $raw | ConvertFrom-Json }
                }
            } else {
                $q = "requests | where timestamp > ago(${Days}d) | summarize total=count(), failed=countif(success==false), lastRun=max(timestamp) by operation_Name | order by failed desc, total desc"
                $raw = az monitor app-insights query --app $comp.appId --analytics-query $q --query "tables[0].rows" -o json 2>$null
                if ($raw) {
                    $arr = $raw | ConvertFrom-Json
                    $rows = foreach ($r in $arr) { [pscustomobject]@{ OperationName=$r[0]; total=$r[1]; failed=$r[2]; lastRun=$r[3] } }
                }
            }
            if ($rows) {
                foreach ($r in $rows) {
                    $t = [int]$r.total; $f = [int]$r.failed
                    $total += $t; $failed += $f
                    if ($r.lastRun -and ([string]$r.lastRun -gt [string]$lastRun)) { $lastRun = [string]$r.lastRun }
                    if ($f -gt 0) { $badOps += "$($r.OperationName) ($f)" }
                }
            }
        }

        # ---- Timer-trigger schedule health -----------------------------------
        # Enumerate the app's timer functions, cross-reference each against its
        # execution count, and derive expected runs from the CRON schedule so we
        # can catch a DISABLED timer or one that MISSED its schedule entirely -
        # signals a failure-only check can never see.
        $timers = @(); $missingCount = 0; $disabledCount = 0; $underCount = 0
        if ($comp) {
            $opTotals = @{}
            if ($rows) { foreach ($r in $rows) { $opTotals[[string]$r.OperationName] = [int]$r.total } }
            $fnList = az functionapp function list -n $fa.name -g $fa.resourceGroup -o json 2>$null | ConvertFrom-Json
            foreach ($fn in @($fnList)) {
                $bind = @($fn.config.bindings) | Where-Object { $_.type -eq 'timerTrigger' } | Select-Object -First 1
                if (-not $bind) { continue }
                $fname    = $fn.config.name
                $disabled = [bool]$fn.isDisabled
                $actual   = if ($opTotals.ContainsKey($fname)) { [int]$opTotals[$fname] } else { 0 }
                $expected = if ($disabled) { $null } else { Get-CronExpectedRuns $bind.schedule $from.ToUniversalTime() $now.ToUniversalTime() }
                $tstatus  = 'ok'
                if     ($disabled)                                          { $tstatus = 'disabled'; $disabledCount++ }
                elseif ($actual -eq 0 -and $expected -ne $null -and $expected -ge 1) { $tstatus = 'missing';  $missingCount++ }
                elseif ($expected -ne $null -and $expected -ge 4 -and $actual -lt [Math]::Floor($expected * 0.5)) { $tstatus = 'under'; $underCount++ }
                $timers += [pscustomobject]@{ Name = $fname; Schedule = $bind.schedule; Disabled = $disabled; Expected = $expected; Actual = $actual; Status = $tstatus }
            }
        }
        $timerNote = @()
        if ($missingCount)  { $timerNote += "$missingCount timer(s) MISSED schedule" }
        if ($disabledCount) { $timerNote += "$disabledCount timer(s) disabled" }
        if ($underCount)    { $timerNote += "$underCount timer(s) under expected" }

        $lastFmt = Format-PT $lastRun
        $verdict = if     ($failed -gt 0)       { 'failed' }
                   elseif ($missingCount -gt 0) { 'missing' }
                   elseif ($disabledCount -gt 0){ 'disabled' }
                   elseif ($note)               { 'unknown' }
                   else                         { 'ok' }
        $row = [pscustomobject]@{
            Name = $fa.name; ResourceGroup = $fa.resourceGroup
            Executions = $total; Failed = $failed; FailedOps = ($badOps -join ', ')
            LastRun = $lastFmt; Note = $note; Verdict = $verdict
            Timers = @($timers); TimerSummary = ($timerNote -join '; ')
            MissedTimers = @($timers | Where-Object { $_.Status -in @('missing','under') } | ForEach-Object { $_.Name })
            DisabledTimers = @($timers | Where-Object { $_.Status -eq 'disabled' } | ForEach-Object { $_.Name })
        }
        $funcAll += $row
        if ($verdict -in @('failed','missing')) { $funcIssues += $row }
    }
} catch { $funcErr = $_.Exception.Message; Say "  function app check skipped: $funcErr" 'Yellow' }
$funcAll    = @($funcAll    | Sort-Object @{e={$_.Verdict -eq 'ok'}}, Name)
$funcIssues = @($funcIssues | Sort-Object Name)


# ==============================================================================
# Severity roll-up
# ==============================================================================
$issues = @()
if ($svcSteps.Count -or $resSteps.Count) { $issues += 'cost' }
if ($failed.Count)      { $issues += 'failed' }
if ($scaleIssues.Count) { $issues += 'scale' }
if ($advisor.Count)     { $issues += 'advisor' }
if ($autoIssues.Count)  { $issues += 'automation' }
if ($funcIssues.Count)  { $issues += 'functions' }
$issueCount = $svcSteps.Count + $resSteps.Count + $failed.Count + $scaleIssues.Count + $advisor.Count + $autoIssues.Count + $funcIssues.Count

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
        errors       = @{ cost = $costErr; activityLog = $alErr; containerApps = $caErr; advisor = $advErr; automation = $autoErr; functions = $funcErr }
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
        h6_automation    = @($autoAll)
        h7_functions     = @($funcAll)
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

# status glyph: green check, red cross, amber warning
function StatusGlyph([string]$verdict){
    switch ($verdict) {
        'ok'       { "<span class='st ok' title='healthy'>&#10003;</span>" }
        'failed'   { "<span class='st bad' title='failures'>&#10007;</span>" }
        'missing'  { "<span class='st bad' title='missed schedule'>&#10007;</span>" }
        'norun'    { "<span class='st warn' title='no runs'>&#9888;</span>" }
        'disabled' { "<span class='st warn' title='timer disabled'>&#9888;</span>" }
        'under'    { "<span class='st warn' title='under expected'>&#9888;</span>" }
        'unknown'  { "<span class='st warn' title='no telemetry'>&#9888;</span>" }
        default    { "<span class='st warn'>&#9888;</span>" }
    }
}

$autoRows = foreach ($a in $autoAll) {
    $sc = switch ($a.Verdict) { 'failed' { 'up' } 'norun' { 'up' } default { '' } }
    $badge = switch ($a.Verdict) {
        'failed' { "<span class='tag'>$($a.Failed) failed</span>" }
        'norun'  { "<span class='tag'>no runs</span>" }
        default  { '' }
    }
    "<tr><td>$(StatusGlyph $a.Verdict)$(Enc $a.Name) $badge</td><td>$(Enc $a.State)</td><td class='num'>$($a.Runs)</td><td class='num $sc'>$($a.Failed)</td><td>$(Enc $a.LastStatus)</td><td>$(Enc $a.LastRun)</td></tr>"
}
if (-not $autoRows) { $autoRows = "<tr><td colspan='6' class='ok'>&#10003; No Logic App workflows found.</td></tr>" }

$funcRows = foreach ($f in $funcAll) {
    $sc = if ($f.Verdict -in @('failed','missing')) { 'up' } else { '' }
    $detail = if     ($f.Verdict -eq 'failed')  { "<span class='tag'>$(Enc $f.FailedOps)</span>" }
              elseif ($f.Verdict -eq 'missing') { "<span class='tag'>missed: $(Enc (($f.MissedTimers) -join ', '))</span>" }
              elseif ($f.Note)                  { "<span class='tag'>$(Enc $f.Note)</span>" }
              else { '' }
    $tcount = @($f.Timers).Count
    $timerCell = if ($tcount -eq 0) { '<span class="hint">&mdash;</span>' }
                 elseif ($f.TimerSummary) { "$(Enc $f.TimerSummary)" }
                 else { "<span class='ok'>&#10003; $tcount timer$(if($tcount -ne 1){'s'}) ok</span>" }
    "<tr><td>$(StatusGlyph $f.Verdict)$(Enc $f.Name) $detail</td><td>$(Enc $f.ResourceGroup)</td><td class='num'>$($f.Executions)</td><td class='num $sc'>$($f.Failed)</td><td>$timerCell</td><td>$(Enc $f.LastRun)</td></tr>"
}
if (-not $funcRows) { $funcRows = "<tr><td colspan='6' class='ok'>&#10003; No Function Apps found.</td></tr>" }

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
         --up:#c0362c; --upBg:#fdeceb; --down:#1f7a4d; --downBg:#e7f6ee; --ok:#1f7a4d; --warn:#b7791f; }
  @media (prefers-color-scheme:dark){
    :root{ --bg:#14141c; --card:#1d1d28; --ink:#ececf5; --muted:#9a9ab0; --line:#2c2c3a;
           --up:#ff8a80; --upBg:#3a1512; --down:#7fe0ab; --downBg:#10301f; --ok:#7fe0ab; --warn:#e0b341; } }
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
  .st{font-weight:700;margin-right:7px;font-size:14px}
  .st.ok{color:var(--down)} .st.bad{color:var(--up)} .st.warn{color:var(--warn)}
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
    <div class='c'><div class='n'>$($autoIssues.Count)</div><div class='l'>Automation issues</div></div>
    <div class='c'><div class='n'>$($funcIssues.Count)</div><div class='l'>Function issues</div></div>
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
    <h2>H6 &middot; Scheduled automation (Logic Apps)</h2>
    <p class='hint'>Each workflow's run history in the window. <span class='tag'>N failed</span> = failed/cancelled runs; <span class='tag'>no runs</span> = an <em>Enabled</em> workflow that didn't run at all (possible missed schedule &mdash; or simply infrequent). The control-plane Activity Log (H3) does <strong>not</strong> catch these.</p>
    <table><thead><tr><th>Workflow</th><th>State</th><th class='num'>Runs</th><th class='num'>Failed</th><th>Last status</th><th>Last run</th></tr></thead>
    <tbody>$($autoRows -join "`n")</tbody></table>
  </section>

  <section>
    <h2>H7 &middot; Function Apps (execution health)</h2>
    <p class='hint'>Function executions from Application Insights (timer &amp; HTTP), with per-timer schedule health. <span class='st bad'>&#10007;</span> = failed executions <em>or</em> a timer that <strong>missed its schedule</strong> (expected runs derived from each timer's CRON). <span class='st warn'>&#9888;</span> = a disabled timer, under-expected runs, or no App Insights telemetry. None of these appear in the Activity Log.</p>
    <table><thead><tr><th>Function App</th><th>Resource group</th><th class='num'>Executions</th><th class='num'>Failed</th><th>Timers</th><th>Last run</th></tr></thead>
    <tbody>$($funcRows -join "`n")</tbody></table>
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
Write-Host ("  Automation      : {0} issue(s) across {1} Logic App(s)" -f $autoIssues.Count, $autoAll.Count)
Write-Host ("  Function apps   : {0} issue(s) (failed/missed) across {1} app(s)" -f $funcIssues.Count, $funcAll.Count)
Write-Host ("  Advisor (high)  : {0}{1}" -f $advisor.Count, $(if($advIgnored.Count){" ($($advIgnored.Count) HA upsells suppressed)"}))
if ($autoIssues.Count) {
    Write-Host "  Automation problems:" -ForegroundColor Yellow
    foreach ($a in $autoIssues) {
        $msg = if ($a.Verdict -eq 'failed') { "$($a.Failed) failed run(s)" } else { "no runs in window (Enabled)" }
        Write-Host ("    ! {0,-30} {1}" -f $a.Name, $msg) -ForegroundColor Yellow
    }
}
if ($funcIssues.Count) {
    Write-Host "  Function problems:" -ForegroundColor Yellow
    foreach ($f in $funcIssues) {
        if ($f.Verdict -eq 'missing') {
            Write-Host ("    ! {0,-30} missed schedule: {1}" -f $f.Name, (($f.MissedTimers) -join ', ')) -ForegroundColor Yellow
        } else {
            Write-Host ("    ! {0,-30} {1} failed: {2}" -f $f.Name, $f.Failed, $f.FailedOps) -ForegroundColor Yellow
        }
    }
}
$disabledApps = @($funcAll | Where-Object { $_.DisabledTimers.Count })
if ($disabledApps.Count) {
    Write-Host "  Disabled timers:" -ForegroundColor DarkYellow
    foreach ($f in $disabledApps) {
        Write-Host ("    ~ {0,-30} {1}" -f $f.Name, (($f.DisabledTimers) -join ', ')) -ForegroundColor DarkYellow
    }
}
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
