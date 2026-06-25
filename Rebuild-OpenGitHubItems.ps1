<#
.SYNOPSIS
  Regenerate the "Open GitHub Items" HTML dashboard from live GitHub data.

.DESCRIPTION
  Uses the GitHub CLI (gh) to list OPEN issues across the user's repositories,
  groups them by repository, sorts by issue number, and writes
  open-github-items.html in this folder. Each row links to the issue on GitHub.

  Auth: reuses the gh CLI login (gh auth status). No separate token handling.

.PARAMETER Owner
  GitHub owner/org whose repos are scanned. Default: purduepete.

.PARAMETER AssignedToMe
  Only include issues assigned to the authenticated user.

.PARAMETER IncludePullRequests
  Also include open pull requests (off by default — issues only).

.PARAMETER NoOpen
  Skip launching the HTML in the default browser after generation.

.EXAMPLE
  pwsh -NoProfile -File .\Rebuild-OpenGitHubItems.ps1
.EXAMPLE
  pwsh -NoProfile -File .\Rebuild-OpenGitHubItems.ps1 -AssignedToMe -NoOpen
#>
[CmdletBinding()]
param(
  [string]$Owner = 'purduepete',
  [switch]$AssignedToMe,
  [switch]$IncludePullRequests,
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$outFile = Join-Path $PSScriptRoot 'open-github-items.html'

function HtmlEnc([string]$s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

# Authenticated login (for the -AssignedToMe filter)
$me = $null
try { $me = (gh api user --jq '.login' 2>$null) } catch { }

# 1) Enumerate repos for the owner
$repos = @(gh repo list $Owner --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>$null)
if (-not $repos) { throw "No repositories found for owner '$Owner' (is gh authenticated?)." }

# 2) Collect open issues (and optionally PRs) per repo
$rows = @()
foreach ($repo in $repos) {
  $json = gh issue list --repo $repo --state open --limit 200 `
    --json number,title,url,assignees,labels,updatedAt,isPinned 2>$null
  if (-not $json) { continue }
  $issues = $json | ConvertFrom-Json
  foreach ($i in $issues) {
    if (-not $IncludePullRequests -and $i.url -match '/pull/') { continue }
    $assignedLogins = @($i.assignees | ForEach-Object { $_.login })
    if ($AssignedToMe -and $me -and ($assignedLogins -notcontains $me)) { continue }
    $rows += [pscustomobject]@{
      Repo      = $repo
      Number    = [int]$i.number
      Title     = $i.title
      Url       = $i.url
      Assignees = ($assignedLogins -join ', ')
      Labels    = @($i.labels | ForEach-Object { $_.name })
      Updated   = ([datetime]$i.updatedAt).ToString('yyyy-MM-dd')
    }
  }
}

$total = $rows.Count
$gen = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$scope = if ($AssignedToMe) { "Assigned to @$me" } else { 'All open issues' }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append("<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>`n")
[void]$sb.Append("<title>Open GitHub Items</title><style>`n")
[void]$sb.Append(":root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#e6edf3;--muted:#8b949e;--accent:#58a6ff;}`n")
[void]$sb.Append("*{box-sizing:border-box;}body{font-family:'Segoe UI',system-ui,sans-serif;margin:0;background:var(--bg);color:var(--text);padding:24px;}`n")
[void]$sb.Append("h1{margin:0 0 4px;font-size:22px;}.meta{color:var(--muted);font-size:13px;margin-bottom:18px;}.controls{margin-bottom:14px;}`n")
[void]$sb.Append("#search{padding:8px 12px;width:340px;max-width:100%;border:1px solid var(--border);border-radius:6px;background:var(--card);color:var(--text);font-size:14px;}`n")
[void]$sb.Append("table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--border);border-radius:8px;overflow:hidden;}`n")
[void]$sb.Append("th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--border);font-size:14px;vertical-align:top;}`n")
[void]$sb.Append("th{background:#1c2128;color:var(--muted);text-transform:uppercase;font-size:11px;letter-spacing:.5px;position:sticky;top:0;}`n")
[void]$sb.Append("tr.group.repo td{background:#1c2128;font-weight:700;color:var(--accent);font-size:14px;}`n")
[void]$sb.Append("tr:hover td{background:#1f262e;}td.id a{color:var(--muted);text-decoration:none;font-variant-numeric:tabular-nums;}`n")
[void]$sb.Append("a{color:var(--accent);text-decoration:none;}a:hover{text-decoration:underline;}`n")
[void]$sb.Append(".badge{padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;display:inline-block;background:#30363d;color:#c9d1d9;margin:1px 2px 1px 0;}`n")
[void]$sb.Append(".empty{color:var(--muted);padding:24px 4px;font-size:15px;}`n")
[void]$sb.Append("</style></head><body>`n")
[void]$sb.Append("<h1>Open GitHub Items</h1>`n")
[void]$sb.Append("<div class='meta'>$scope &bull; Owner: $(HtmlEnc $Owner) &bull; Grouped by repo &bull; Sorted by number &bull; Generated: $gen &bull; Total: $total</div>`n")

if ($total -eq 0) {
  [void]$sb.Append("<div class='empty'>&#127881; No open items. You're all caught up.</div>`n")
}
else {
  [void]$sb.Append("<div class='controls'><input id='search' type='text' placeholder='Filter by text, repo, label, assignee...' onkeyup='filt()'></div>`n")
  [void]$sb.Append("<table id='tbl'><thead><tr><th>Updated</th><th>#</th><th>Title</th><th>Labels</th><th>Assignees</th></tr></thead><tbody>`n")
  foreach ($repoGroup in ($rows | Group-Object Repo | Sort-Object Name)) {
    [void]$sb.Append("<tr class='group repo'><td colspan='5'>$(HtmlEnc $repoGroup.Name) &mdash; $($repoGroup.Count) open</td></tr>`n")
    foreach ($r in ($repoGroup.Group | Sort-Object Number)) {
      $labelHtml = ($r.Labels | ForEach-Object { "<span class='badge'>$(HtmlEnc $_)</span>" }) -join ''
      [void]$sb.Append("<tr><td>$($r.Updated)</td><td class='id'><a href='$($r.Url)' target='_blank'>#$($r.Number)</a></td><td><a href='$($r.Url)' target='_blank'>$(HtmlEnc $r.Title)</a></td><td>$labelHtml</td><td>$(HtmlEnc $r.Assignees)</td></tr>`n")
    }
  }
  [void]$sb.Append("`n</tbody></table>`n")
  [void]$sb.Append("<script>function filt(){var q=document.getElementById('search').value.toLowerCase();document.querySelectorAll('#tbl tbody tr').forEach(function(r){if(r.classList.contains('group')){r.style.display='';return;}r.style.display=r.innerText.toLowerCase().indexOf(q)>-1?'':'none';});}</script>`n")
}

[void]$sb.Append("</body></html>")

[System.IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outFile  (Total=$total, Generated=$gen)"
if (-not $NoOpen) { Start-Process $outFile }
