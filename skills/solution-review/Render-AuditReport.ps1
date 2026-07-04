#requires -Version 7.0
<#
.SYNOPSIS
  Render a self-contained, light/dark HTML report for a solution-audit run
  (robustness / performance / reliability / duplication) and open it.

.DESCRIPTION
  Consumes a findings JSON payload (produced by the solution-audit skill after
  merging the two parallel model agents' results) and emits a single themed HTML
  file (@jimb's house style: indigo->violet accent, light + dark with a toggle
  that respects the system preference, squared corners, Lucide-style stroke SVG
  icons, no emoji).

  Input JSON schema:
  {
    "target":      "C:\\path\\to\\solution",
    "generatedAt": "2026-07-04T12:00:00-07:00",   // optional; defaults to now
    "models":      ["Gemini 3.1 Pro", "MAI-Code-1-Flash"],
    "summary":     "one or two sentence executive summary",
    "findings": [
      {
        "id":             "R1",
        "category":       "Reliability",           // Reliability|Performance|Robustness|Duplication
        "severity":       "Critical",              // Critical|High|Medium|Low
        "title":          "short finding title",
        "location":       "backend/src/x.ts:74-95", // optional
        "impact":         "what breaks / why it matters",
        "recommendation": "concrete fix",
        "foundBy":        ["Gemini 3.1 Pro"]        // optional; which model(s) surfaced it
      }
    ]
  }

.PARAMETER InputJson
  Path to the findings JSON file. If omitted, JSON is read from stdin.

.PARAMETER OutDir
  Output directory (default %TEMP%\solution-audit).

.PARAMETER NoOpen
  Do not open the report in the browser (still writes it, prints the path).
#>
[CmdletBinding()]
param(
  [string]$InputJson,
  [string]$OutDir = (Join-Path $env:TEMP 'solution-audit'),
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

# ---- Load payload ----------------------------------------------------------
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
$findings    = @($data.findings)

function HtmlEncode([string]$s) {
  if ($null -eq $s) { return '' }
  [System.Net.WebUtility]::HtmlEncode($s)
}

# ---- Severity + category metadata -----------------------------------------
$sevOrder = @{ 'Critical' = 0; 'High' = 1; 'Medium' = 2; 'Low' = 3 }
$sevClass = @{ 'Critical' = 'sev-crit'; 'High' = 'sev-high'; 'Medium' = 'sev-med'; 'Low' = 'sev-low' }

$sorted = $findings | Sort-Object `
  @{ Expression = { if ($sevOrder.ContainsKey([string]$_.severity)) { $sevOrder[[string]$_.severity] } else { 9 } } }, `
  @{ Expression = { [string]$_.category } }

# ---- Counts ----------------------------------------------------------------
$counts = [ordered]@{ Critical = 0; High = 0; Medium = 0; Low = 0 }
foreach ($f in $findings) { $sev = [string]$f.severity; if ($counts.Contains($sev)) { $counts[$sev]++ } }

# ---- Build finding cards ---------------------------------------------------
$sb = [System.Text.StringBuilder]::new()
foreach ($f in $sorted) {
  $sev  = [string]$f.severity
  $cls  = if ($sevClass.ContainsKey($sev)) { $sevClass[$sev] } else { 'sev-low' }
  $cat  = HtmlEncode ([string]$f.category)
  $id   = HtmlEncode ([string]$f.id)
  $ttl  = HtmlEncode ([string]$f.title)
  $loc  = HtmlEncode ([string]$f.location)
  $imp  = HtmlEncode ([string]$f.impact)
  $rec  = HtmlEncode ([string]$f.recommendation)
  $by   = @($f.foundBy) | Where-Object { $_ } | ForEach-Object { HtmlEncode ([string]$_) }

  [void]$sb.Append("<article class='card' data-cat='$cat' data-sev='$sev'>")
  [void]$sb.Append("<div class='card-head'>")
  [void]$sb.Append("<span class='pill $cls'>$(HtmlEncode $sev)</span>")
  [void]$sb.Append("<span class='pill cat'>$cat</span>")
  if ($id) { [void]$sb.Append("<span class='fid'>$id</span>") }
  [void]$sb.Append("<h3>$ttl</h3>")
  [void]$sb.Append("</div>")
  if ($loc) { [void]$sb.Append("<div class='loc'><code>$loc</code></div>") }
  if ($imp) { [void]$sb.Append("<p class='impact'><span class='lbl'>Impact</span>$imp</p>") }
  if ($rec) { [void]$sb.Append("<p class='rec'><span class='lbl'>Fix</span>$rec</p>") }
  if ($by.Count) { [void]$sb.Append("<div class='by'>Surfaced by: " + ($by -join ', ') + "</div>") }
  [void]$sb.Append("</article>")
}
if (-not $sorted.Count) {
  [void]$sb.Append("<div class='empty'>No findings were reported. The solution looks clean for the audited dimensions.</div>")
}
$cards = $sb.ToString()

$modelsHtml = ($models | ForEach-Object { "<span class='chip'>$(HtmlEncode $_)</span>" }) -join ''

# ---- Assemble HTML ---------------------------------------------------------
$style = @'
<style>
  :root{
    --bg:#f6f7fb; --panel:#ffffff; --panel-2:#f0f1f7; --text:#1a1c25; --muted:#5b5f70;
    --border:#e2e4ee; --accent:#4f46e5; --accent-2:#7c3aed; --shadow:0 1px 3px rgba(20,20,40,.08);
    --crit:#dc2626; --high:#ea580c; --med:#ca8a04; --low:#2563eb;
  }
  [data-theme="dark"]{
    --bg:#0d0f17; --panel:#151824; --panel-2:#1c2030; --text:#e8eaf2; --muted:#9aa0b5;
    --border:#272c3d; --accent:#818cf8; --accent-2:#a78bfa; --shadow:0 1px 3px rgba(0,0,0,.4);
    --crit:#f87171; --high:#fb923c; --med:#facc15; --low:#60a5fa;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
  a{color:var(--accent)}
  .bar{position:sticky;top:0;z-index:10;display:flex;align-items:center;gap:16px;padding:14px 24px;
    background:color-mix(in srgb,var(--panel) 80%,transparent);backdrop-filter:blur(10px);
    border-bottom:1px solid var(--border)}
  .bar h1{font-size:17px;margin:0;font-weight:650;letter-spacing:.2px}
  .bar .grad{background:linear-gradient(90deg,var(--accent),var(--accent-2));-webkit-background-clip:text;background-clip:text;color:transparent}
  .spacer{flex:1}
  .toggle{display:inline-flex;align-items:center;justify-content:center;width:36px;height:36px;cursor:pointer;
    background:var(--panel-2);border:1px solid var(--border);color:var(--text)}
  .toggle svg{width:18px;height:18px}
  .wrap{max-width:1080px;margin:0 auto;padding:24px}
  .meta{display:flex;flex-wrap:wrap;gap:10px 22px;color:var(--muted);font-size:13px;margin-bottom:14px}
  .meta code{background:var(--panel-2);padding:2px 6px;border:1px solid var(--border)}
  .chip{display:inline-block;background:var(--panel-2);border:1px solid var(--border);padding:2px 9px;font-size:12px;margin-left:6px}
  .summary{background:var(--panel);border:1px solid var(--border);border-left:3px solid var(--accent);
    padding:14px 16px;margin:14px 0 22px;box-shadow:var(--shadow)}
  .kpis{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:22px}
  .kpi{flex:1;min-width:120px;background:var(--panel);border:1px solid var(--border);padding:14px 16px;box-shadow:var(--shadow)}
  .kpi .n{font-size:26px;font-weight:700;line-height:1}
  .kpi .l{font-size:12px;color:var(--muted);margin-top:4px;text-transform:uppercase;letter-spacing:.5px}
  .kpi.crit .n{color:var(--crit)} .kpi.high .n{color:var(--high)} .kpi.med .n{color:var(--med)} .kpi.low .n{color:var(--low)}
  .filters{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:18px}
  .filters button{background:var(--panel-2);border:1px solid var(--border);color:var(--text);padding:6px 12px;cursor:pointer;font-size:13px}
  .filters button.active{background:var(--accent);color:#fff;border-color:var(--accent)}
  .card{background:var(--panel);border:1px solid var(--border);border-left:3px solid var(--border);padding:16px 18px;margin-bottom:14px;box-shadow:var(--shadow)}
  .card[data-sev="Critical"]{border-left-color:var(--crit)}
  .card[data-sev="High"]{border-left-color:var(--high)}
  .card[data-sev="Medium"]{border-left-color:var(--med)}
  .card[data-sev="Low"]{border-left-color:var(--low)}
  .card-head{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
  .card-head h3{margin:6px 0 0;font-size:16px;flex-basis:100%;font-weight:620}
  .pill{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;padding:3px 8px;color:#fff}
  .pill.sev-crit{background:var(--crit)} .pill.sev-high{background:var(--high)}
  .pill.sev-med{background:var(--med)} .pill.sev-low{background:var(--low)}
  .pill.cat{background:var(--panel-2);color:var(--muted);border:1px solid var(--border)}
  .fid{font-size:12px;color:var(--muted);font-family:ui-monospace,Consolas,monospace}
  .loc{margin:8px 0 6px}
  .loc code{background:var(--panel-2);border:1px solid var(--border);padding:2px 8px;font-size:12.5px}
  .impact,.rec{margin:8px 0}
  .lbl{display:inline-block;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:var(--accent-2);margin-right:8px}
  .by{margin-top:10px;font-size:12px;color:var(--muted)}
  .empty{background:var(--panel);border:1px solid var(--border);padding:28px;text-align:center;color:var(--muted)}
  footer{max-width:1080px;margin:10px auto 40px;padding:0 24px;color:var(--muted);font-size:12px}
</style>
'@

$script = @'
<script>
  (function(){
    var mq = window.matchMedia('(prefers-color-scheme: dark)');
    var saved = localStorage.getItem('sa-theme');
    function apply(t){ document.documentElement.setAttribute('data-theme', t);
      document.getElementById('ic-sun').style.display = t==='dark'?'none':'block';
      document.getElementById('ic-moon').style.display = t==='dark'?'block':'none'; }
    apply(saved || (mq.matches?'dark':'light'));
    document.getElementById('themeToggle').addEventListener('click', function(){
      var cur = document.documentElement.getAttribute('data-theme');
      var next = cur==='dark'?'light':'dark'; localStorage.setItem('sa-theme', next); apply(next);
    });
    var cards = Array.prototype.slice.call(document.querySelectorAll('.card'));
    document.querySelectorAll('.filters button').forEach(function(b){
      b.addEventListener('click', function(){
        document.querySelectorAll('.filters button').forEach(function(x){x.classList.remove('active')});
        b.classList.add('active');
        var f = b.getAttribute('data-filter');
        cards.forEach(function(c){
          c.style.display = (f==='all' || c.getAttribute('data-cat')===f || c.getAttribute('data-sev')===f) ? '' : 'none';
        });
      });
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
<title>Solution Audit — $(HtmlEncode (Split-Path $target -Leaf))</title>
$style
</head>
<body>
<div class="bar">
  <h1><span class="grad">Solution Audit</span> &middot; robustness &middot; performance &middot; reliability &middot; duplication</h1>
  <div class="spacer"></div>
  <div id="themeToggle" class="toggle" title="Toggle theme" role="button" tabindex="0">$sunMoon</div>
</div>
<div class="wrap">
  <div class="meta">
    <span>Target: <code>$(HtmlEncode $target)</code></span>
    <span>Generated: $(HtmlEncode $generatedAt)</span>
    <span>Models:$modelsHtml</span>
  </div>
  $(if ($summary) { "<div class='summary'>$(HtmlEncode $summary)</div>" })
  <div class="kpis">
    <div class="kpi crit"><div class="n">$($counts['Critical'])</div><div class="l">Critical</div></div>
    <div class="kpi high"><div class="n">$($counts['High'])</div><div class="l">High</div></div>
    <div class="kpi med"><div class="n">$($counts['Medium'])</div><div class="l">Medium</div></div>
    <div class="kpi low"><div class="n">$($counts['Low'])</div><div class="l">Low</div></div>
  </div>
  <div class="filters">
    <button class="active" data-filter="all">All</button>
    <button data-filter="Reliability">Reliability</button>
    <button data-filter="Performance">Performance</button>
    <button data-filter="Robustness">Robustness</button>
    <button data-filter="Duplication">Duplication</button>
    <button data-filter="Critical">Critical only</button>
  </div>
  $cards
</div>
<footer>Read-only analysis. Findings synthesized from parallel model agents &mdash; verify each against the code before acting.</footer>
$script
</body>
</html>
"@

# ---- Write + open ----------------------------------------------------------
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $OutDir "solution-audit-$stamp.html"
$html | Set-Content -LiteralPath $outFile -Encoding UTF8

Write-Host "Report written: $outFile"
Write-Host ("Findings: {0} Critical, {1} High, {2} Medium, {3} Low" -f $counts['Critical'],$counts['High'],$counts['Medium'],$counts['Low'])

if (-not $NoOpen) { Start-Process $outFile }
