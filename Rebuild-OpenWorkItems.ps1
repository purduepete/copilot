<#
.SYNOPSIS
  Regenerate the "Open ADO Work Items" HTML dashboard (assigned to @Me).

.DESCRIPTION
  Queries Azure DevOps (org StarlightAgileBI) for work items assigned to the
  current user, excluding Closed/Done/Removed/Resolved, groups them by Area -> Status,
  sorts by ID ascending, and writes open-work-items.html in this folder.

  Auth: reuses the OAuth token cached by Git Credential Manager for
  starlightagilebi.visualstudio.com (no separate login required).

.PARAMETER NoOpen
  Skip launching the HTML in the default browser after generation.

.EXAMPLE
  pwsh -NoProfile -File .\Rebuild-OpenWorkItems.ps1
#>
[CmdletBinding()]
param(
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$org = 'https://dev.azure.com/StarlightAgileBI'
$outFile = Join-Path $PSScriptRoot 'open-work-items.html'

function Get-AdoToken {
  $inp = "protocol=https`nhost=starlightagilebi.visualstudio.com`n`n"
  $pw = ($inp | git credential fill 2>$null | Where-Object { $_ -match '^password=' }) -replace '^password=',''
  if (-not $pw) { throw "No cached ADO credential found. Run a git fetch against the repo first." }
  $pw
}

$tok = Get-AdoToken
$h  = @{ Authorization = "Bearer $tok" }
$hp = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }

# 1) WIQL: open items assigned to me
$wiql = @{ query = "SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed','Done','Removed','Resolved') AND [System.Id] <> 435324 ORDER BY [System.Id]" } | ConvertTo-Json
$res = Invoke-RestMethod -Headers $hp -Method Post -Uri "$org/_apis/wit/wiql?api-version=7.1" -Body $wiql
$ids = @($res.workItems.id)

# 2) Details (chunked)
$fields = 'System.Id,System.WorkItemType,System.State,System.Title,System.AreaPath,System.TeamProject,System.ChangedDate'
$items = @()
for ($i = 0; $i -lt $ids.Count; $i += 200) {
  $chunk = $ids[$i..([Math]::Min($i+199, $ids.Count-1))] -join ','
  $wi = Invoke-RestMethod -Headers $h -Uri "$org/_apis/wit/workitems?ids=$chunk&fields=$fields&api-version=7.1"
  $items += $wi.value
}

function UrlSeg([string]$s) { $s -replace ' ', '%20' }
function HtmlEnc([string]$s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')
}

$rows = $items | ForEach-Object {
  $f = $_.fields
  [pscustomobject]@{
    Id      = [int]$f.'System.Id'
    Project = $f.'System.TeamProject'
    Area    = ($f.'System.AreaPath' -split '\\')[-1]
    Type    = $f.'System.WorkItemType'
    State   = $f.'System.State'
    Title   = $f.'System.Title'
    Changed = ([datetime]$f.'System.ChangedDate').ToString('yyyy-MM-dd')
  }
}

$stateRank = @{ 'Active'=1; 'In Progress'=2; 'Committed'=3; 'New'=4; 'To Do'=5; 'On hold'=6 }
function StateRank([string]$s) { if ($stateRank.ContainsKey($s)) { $stateRank[$s] } else { 99 } }
$stateClass = @{ 'New'='new'; 'Active'='active'; 'Resolved'='resolved'; 'In Progress'='inprogress'; 'To Do'='todo'; 'On hold'='onhold'; 'Committed'='todo' }
function StateClass([string]$s) { if ($stateClass.ContainsKey($s)) { $stateClass[$s] } else { 'todo' } }

$sb = [System.Text.StringBuilder]::new()
$total = $rows.Count
$gen = (Get-Date).ToString('yyyy-MM-dd HH:mm')

[void]$sb.Append("<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>`n")
[void]$sb.Append("<title>Open ADO Work Items</title><style>`n")
[void]$sb.Append(":root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#e6edf3;--muted:#8b949e;--accent:#58a6ff;}`n")
[void]$sb.Append("*{box-sizing:border-box;}body{font-family:'Segoe UI',system-ui,sans-serif;margin:0;background:var(--bg);color:var(--text);padding:24px;}`n")
[void]$sb.Append("h1{margin:0 0 4px;font-size:22px;}.meta{color:var(--muted);font-size:13px;margin-bottom:18px;}.controls{margin-bottom:14px;}`n")
[void]$sb.Append("#search{padding:8px 12px;width:340px;max-width:100%;border:1px solid var(--border);border-radius:6px;background:var(--card);color:var(--text);font-size:14px;}`n")
[void]$sb.Append("table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--border);border-radius:8px;overflow:hidden;}`n")
[void]$sb.Append("th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--border);font-size:14px;vertical-align:top;}`n")
[void]$sb.Append("th{background:#1c2128;color:var(--muted);text-transform:uppercase;font-size:11px;letter-spacing:.5px;position:sticky;top:0;}`n")
[void]$sb.Append("tr.group.area td{background:#1c2128;font-weight:700;color:var(--accent);font-size:14px;}`n")
[void]$sb.Append("tr.group.status td{background:#161b22;font-weight:600;font-size:12px;padding-left:24px;}`n")
[void]$sb.Append("tr:hover td{background:#1f262e;}td.id a{color:var(--muted);text-decoration:none;font-variant-numeric:tabular-nums;}`n")
[void]$sb.Append("a{color:var(--accent);text-decoration:none;}a:hover{text-decoration:underline;}`n")
[void]$sb.Append(".badge{padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;display:inline-block;}`n")
[void]$sb.Append(".new{background:#1f6feb33;color:#79c0ff;}.active{background:#23863633;color:#56d364;}`n")
[void]$sb.Append(".resolved{background:#9e6a0333;color:#e3b341;}.inprogress{background:#8957e533;color:#d2a8ff;}`n")
[void]$sb.Append(".todo{background:#30363d;color:#c9d1d9;}.onhold{background:#da363333;color:#ff7b72;}`n")
[void]$sb.Append("</style></head><body>`n")
[void]$sb.Append("<h1>Open Azure DevOps Work Items</h1>`n")
[void]$sb.Append("<div class='meta'>Assigned to @Me &bull; Org: StarlightAgileBI &bull; Excludes: Closed, Done, Removed, Resolved &bull; Grouped by Area &rarr; Status &bull; Sorted by ID (low&rarr;high) &bull; Generated: $gen &bull; Total: $total</div>`n")
[void]$sb.Append("<div class='controls'><input id='search' type='text' placeholder='Filter by text, area, type, state, project...' onkeyup='filt()'></div>`n")
[void]$sb.Append("<table id='tbl'><thead><tr><th>Changed</th><th>Project</th><th>ID</th><th>Type</th><th>Status</th><th>Task</th></tr></thead><tbody>`n")

foreach ($areaGroup in ($rows | Group-Object Area | Sort-Object Name)) {
  [void]$sb.Append("<tr class='group area'><td colspan='6'>$(HtmlEnc $areaGroup.Name) &mdash; $($areaGroup.Count) items</td></tr>`n")
  $byState = $areaGroup.Group | Group-Object State | Sort-Object @{ Expression = { StateRank $_.Name } }, Name
  foreach ($sg in $byState) {
    $cls = StateClass $sg.Name
    [void]$sb.Append("<tr class='group status'><td colspan='6'><span class='badge $cls'>$(HtmlEnc $sg.Name)</span> &mdash; $($sg.Count)</td></tr>`n")
    foreach ($r in ($sg.Group | Sort-Object Id)) {
      $url = "https://dev.azure.com/StarlightAgileBI/$(UrlSeg $r.Project)/_workitems/edit/$($r.Id)"
      $bcls = StateClass $r.State
      [void]$sb.Append("<tr><td>$($r.Changed)</td><td>$(HtmlEnc $r.Project)</td><td class='id'><a href='$url' target='_blank'>$($r.Id)</a></td><td>$(HtmlEnc $r.Type)</td><td><span class='badge $bcls'>$(HtmlEnc $r.State)</span></td><td><a href='$url' target='_blank'>$(HtmlEnc $r.Title)</a></td></tr>`n")
    }
  }
}

[void]$sb.Append("`n</tbody></table>`n")
[void]$sb.Append("<script>function filt(){var q=document.getElementById('search').value.toLowerCase();document.querySelectorAll('#tbl tbody tr').forEach(function(r){if(r.classList.contains('group')){r.style.display='';return;}r.style.display=r.innerText.toLowerCase().indexOf(q)>-1?'':'none';});}</script>`n")
[void]$sb.Append("</body></html>")

[System.IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outFile  (Total=$total, Generated=$gen)"
if (-not $NoOpen) { Start-Process $outFile }
