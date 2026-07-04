#requires -Version 7.0
<#
.SYNOPSIS
  Render a self-contained, light/dark HTML scorecard for a code-quality run and
  open it.

.DESCRIPTION
  Consumes a quality JSON payload (produced by the code-quality skill after
  merging the two parallel model agents' assessments) and emits a single themed
  HTML file (@jimb's house style: indigo->violet accent, light + dark toggle that
  respects the system preference, squared corners, Lucide-style stroke SVG icons,
  no emoji).

  Input JSON schema:
  {
    "target":       "C:\\path\\to\\solution",
    "generatedAt":  "2026-07-04T12:00:00-07:00",   // optional
    "models":       ["Gemini 3.1 Pro", "MAI-Code-1-Flash"],
    "overallScore": 78,                            // 0-100
    "summary":      "one or two sentence executive summary",
    "dimensions": [
      {
        "name":     "Test coverage & quality",
        "score":    62,                            // 0-100
        "notes":    "what's good / what's weak",
        "topIssues":["concrete issue 1","concrete issue 2"]
      }
    ],
    "improvements": [
      { "title":"...", "dimension":"Testing", "effort":"Low", "impact":"High", "detail":"..." }
    ]
  }

  Dimension and overall grades are derived from the numeric score:
    >=90 A | >=80 B | >=70 C | >=60 D | else F

.PARAMETER InputJson
  Path to the quality JSON file. If omitted, JSON is read from stdin.

.PARAMETER OutDir
  Output directory (default %TEMP%\code-quality).

.PARAMETER NoOpen
  Do not open the report in the browser.
#>
[CmdletBinding()]
param(
  [string]$InputJson,
  [string]$OutDir = (Join-Path $env:TEMP 'code-quality'),
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

if ($InputJson) {
  if (-not (Test-Path -LiteralPath $InputJson)) { throw "InputJson not found: $InputJson" }
  $raw = Get-Content -LiteralPath $InputJson -Raw
} else {
  $raw = $input | Out-String
  if ([string]::IsNullOrWhiteSpace($raw)) { throw 'No JSON provided (pass -InputJson <file> or pipe JSON in).' }
}
$data = $raw | ConvertFrom-Json

$target      = if ($data.target)  { [string]$data.target }  else { '(unspecified)' }
$generatedAt = if ($data.generatedAt) { [string]$data.generatedAt } else { (Get-Date).ToString('yyyy-MM-dd HH:mm') }
$models      = @($data.models)
$summary     = if ($data.summary) { [string]$data.summary } else { '' }
$overall     = [int]($data.overallScore)
$dimensions  = @($data.dimensions)
$improvements = @($data.improvements)

function HtmlEncode([string]$s) {
  if ($null -eq $s) { return '' }
  [System.Net.WebUtility]::HtmlEncode($s)
}
function Grade([int]$n) {
  if ($n -ge 90) { 'A' } elseif ($n -ge 80) { 'B' } elseif ($n -ge 70) { 'C' } elseif ($n -ge 60) { 'D' } else { 'F' }
}
function GradeClass([int]$n) {
  if ($n -ge 80) { 'g-good' } elseif ($n -ge 60) { 'g-ok' } else { 'g-bad' }
}

$overallGrade = Grade $overall
$overallCls   = GradeClass $overall

# ---- Dimension cards -------------------------------------------------------
$sb = [System.Text.StringBuilder]::new()
foreach ($d in $dimensions) {
  $name  = HtmlEncode ([string]$d.name)
  $score = [int]($d.score)
  $g     = Grade $score
  $gc    = GradeClass $score
  $notes = HtmlEncode ([string]$d.notes)
  $issues = @($d.topIssues) | Where-Object { $_ } | ForEach-Object { "<li>$(HtmlEncode ([string]$_))</li>" }

  [void]$sb.Append("<article class='dim'>")
  [void]$sb.Append("<div class='dim-head'><h3>$name</h3><span class='grade $gc'>$g</span></div>")
  [void]$sb.Append("<div class='bar-track'><div class='bar-fill $gc' style='width:$score%'></div></div>")
  [void]$sb.Append("<div class='score-line'><span class='num'>$score</span><span class='den'>/100</span></div>")
  if ($notes) { [void]$sb.Append("<p class='notes'>$notes</p>") }
  if ($issues.Count) { [void]$sb.Append("<ul class='issues'>" + ($issues -join '') + "</ul>") }
  [void]$sb.Append("</article>")
}
if (-not $dimensions.Count) {
  [void]$sb.Append("<div class='empty'>No dimensions were scored.</div>")
}
$dimCards = $sb.ToString()

# ---- Improvement rows (sorted by impact desc, effort asc) ------------------
$impactRank = @{ 'High' = 0; 'Medium' = 1; 'Low' = 2 }
$effortRank = @{ 'Low' = 0; 'Medium' = 1; 'High' = 2 }
$impSorted = $improvements | Sort-Object `
  @{ Expression = { $r = $impactRank[[string]$_.impact]; if ($null -ne $r) { $r } else { 9 } } }, `
  @{ Expression = { $r = $effortRank[[string]$_.effort]; if ($null -ne $r) { $r } else { 9 } } }

$rb = [System.Text.StringBuilder]::new()
foreach ($i in $impSorted) {
  $t   = HtmlEncode ([string]$i.title)
  $dim = HtmlEncode ([string]$i.dimension)
  $eff = HtmlEncode ([string]$i.effort)
  $imp = HtmlEncode ([string]$i.impact)
  $det = HtmlEncode ([string]$i.detail)
  [void]$rb.Append("<tr><td class='t'><strong>$t</strong>$(if($det){"<div class='det'>$det</div>"})</td><td>$dim</td><td><span class='tag'>$eff</span></td><td><span class='tag'>$imp</span></td></tr>")
}
if (-not $impSorted.Count) { [void]$rb.Append("<tr><td colspan='4' class='empty'>No improvement levers listed.</td></tr>") }
$impRows = $rb.ToString()

$modelsHtml = ($models | ForEach-Object { "<span class='chip'>$(HtmlEncode $_)</span>" }) -join ''

$style = @'
<style>
  :root{
    --bg:#f6f7fb; --panel:#ffffff; --panel-2:#f0f1f7; --text:#1a1c25; --muted:#5b5f70;
    --border:#e2e4ee; --accent:#4f46e5; --accent-2:#7c3aed; --shadow:0 1px 3px rgba(20,20,40,.08);
    --good:#16a34a; --ok:#ca8a04; --bad:#dc2626;
  }
  [data-theme="dark"]{
    --bg:#0d0f17; --panel:#151824; --panel-2:#1c2030; --text:#e8eaf2; --muted:#9aa0b5;
    --border:#272c3d; --accent:#818cf8; --accent-2:#a78bfa; --shadow:0 1px 3px rgba(0,0,0,.4);
    --good:#4ade80; --ok:#facc15; --bad:#f87171;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
  .bar{position:sticky;top:0;z-index:10;display:flex;align-items:center;gap:16px;padding:14px 24px;
    background:color-mix(in srgb,var(--panel) 80%,transparent);backdrop-filter:blur(10px);border-bottom:1px solid var(--border)}
  .bar h1{font-size:17px;margin:0;font-weight:650}
  .bar .grad{background:linear-gradient(90deg,var(--accent),var(--accent-2));-webkit-background-clip:text;background-clip:text;color:transparent}
  .spacer{flex:1}
  .toggle{display:inline-flex;align-items:center;justify-content:center;width:36px;height:36px;cursor:pointer;background:var(--panel-2);border:1px solid var(--border);color:var(--text)}
  .toggle svg{width:18px;height:18px}
  .wrap{max-width:1080px;margin:0 auto;padding:24px}
  .meta{display:flex;flex-wrap:wrap;gap:10px 22px;color:var(--muted);font-size:13px;margin-bottom:14px}
  .meta code{background:var(--panel-2);padding:2px 6px;border:1px solid var(--border)}
  .chip{display:inline-block;background:var(--panel-2);border:1px solid var(--border);padding:2px 9px;font-size:12px;margin-left:6px}
  .overall{display:flex;align-items:center;gap:22px;background:var(--panel);border:1px solid var(--border);border-left:3px solid var(--accent);padding:20px 24px;margin:14px 0 24px;box-shadow:var(--shadow)}
  .overall .big{font-size:56px;font-weight:800;line-height:1}
  .overall .big.g-good{color:var(--good)} .overall .big.g-ok{color:var(--ok)} .overall .big.g-bad{color:var(--bad)}
  .overall .oscore{font-size:14px;color:var(--muted)}
  .overall .osum{flex:1}
  h2{font-size:15px;text-transform:uppercase;letter-spacing:.6px;color:var(--muted);margin:26px 0 12px;font-weight:700}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:14px}
  .dim{background:var(--panel);border:1px solid var(--border);padding:16px 18px;box-shadow:var(--shadow)}
  .dim-head{display:flex;align-items:center;justify-content:space-between;gap:10px}
  .dim-head h3{margin:0;font-size:15px;font-weight:620}
  .grade{font-size:20px;font-weight:800;width:34px;height:34px;display:flex;align-items:center;justify-content:center;color:#fff}
  .grade.g-good{background:var(--good)} .grade.g-ok{background:var(--ok)} .grade.g-bad{background:var(--bad)}
  .bar-track{height:8px;background:var(--panel-2);border:1px solid var(--border);margin:12px 0 6px}
  .bar-fill{height:100%;}
  .bar-fill.g-good{background:var(--good)} .bar-fill.g-ok{background:var(--ok)} .bar-fill.g-bad{background:var(--bad)}
  .score-line{font-size:12px;color:var(--muted)} .score-line .num{font-size:15px;font-weight:700;color:var(--text)}
  .notes{margin:10px 0 6px;font-size:13.5px}
  .issues{margin:8px 0 0;padding-left:18px;font-size:13px;color:var(--muted)}
  .issues li{margin:3px 0}
  table{width:100%;border-collapse:collapse;background:var(--panel);border:1px solid var(--border);box-shadow:var(--shadow)}
  th,td{text-align:left;padding:10px 14px;border-bottom:1px solid var(--border);font-size:13.5px;vertical-align:top}
  th{font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted)}
  td.t .det{color:var(--muted);font-size:12.5px;margin-top:3px}
  .tag{display:inline-block;background:var(--panel-2);border:1px solid var(--border);padding:2px 9px;font-size:12px}
  .empty{text-align:center;color:var(--muted);padding:24px}
  footer{max-width:1080px;margin:10px auto 40px;padding:0 24px;color:var(--muted);font-size:12px}
</style>
'@

$script = @'
<script>
  (function(){
    var mq = window.matchMedia('(prefers-color-scheme: dark)');
    var saved = localStorage.getItem('cq-theme');
    function apply(t){ document.documentElement.setAttribute('data-theme', t);
      document.getElementById('ic-sun').style.display = t==='dark'?'none':'block';
      document.getElementById('ic-moon').style.display = t==='dark'?'block':'none'; }
    apply(saved || (mq.matches?'dark':'light'));
    document.getElementById('themeToggle').addEventListener('click', function(){
      var cur = document.documentElement.getAttribute('data-theme');
      var next = cur==='dark'?'light':'dark'; localStorage.setItem('cq-theme', next); apply(next);
    });
  })();
</script>
'@

$sunMoon = @'
<svg id="ic-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>
<svg id="ic-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:none"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
'@

$html = @"
<!doctype html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Code Quality — $(HtmlEncode (Split-Path $target -Leaf))</title>
$style
</head>
<body>
<div class="bar">
  <h1><span class="grad">Code Quality</span> &middot; scorecard</h1>
  <div class="spacer"></div>
  <div id="themeToggle" class="toggle" title="Toggle theme" role="button" tabindex="0">$sunMoon</div>
</div>
<div class="wrap">
  <div class="meta">
    <span>Target: <code>$(HtmlEncode $target)</code></span>
    <span>Generated: $(HtmlEncode $generatedAt)</span>
    <span>Models:$modelsHtml</span>
  </div>
  <div class="overall">
    <div class="big $overallCls">$overallGrade</div>
    <div class="osum">
      <div class="oscore">Overall score <strong>$overall / 100</strong></div>
      $(if ($summary) { "<div>$(HtmlEncode $summary)</div>" })
    </div>
  </div>

  <h2>Quality dimensions</h2>
  <div class="grid">
    $dimCards
  </div>

  <h2>Top improvement levers</h2>
  <table>
    <thead><tr><th>Improvement</th><th>Dimension</th><th>Effort</th><th>Impact</th></tr></thead>
    <tbody>$impRows</tbody>
  </table>
</div>
<footer>Read-only assessment. Scores are a synthesis of parallel model judgments &mdash; directional, not absolute.</footer>
$script
</body>
</html>
"@

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $OutDir "code-quality-$stamp.html"
$html | Set-Content -LiteralPath $outFile -Encoding UTF8

Write-Host "Report written: $outFile"
Write-Host ("Overall: {0} ({1}/100) across {2} dimensions" -f $overallGrade,$overall,$dimensions.Count)

if (-not $NoOpen) { Start-Process $outFile }
