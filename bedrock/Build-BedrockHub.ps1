<#
.SYNOPSIS
  Builds a single visual "home base" (index.html) that links every Bedrock
  understanding asset under one umbrella -- my own analysis (bronze source map,
  onboarding plan) plus the key reports & docs that live in the confidential
  FDE_Revenue_Bedrock repo.

.DESCRIPTION
  The hub LINKS to the repo's files in place (file:/// URIs) -- it never copies
  confidential content into this (synced) copilot repo. Only assets I generated
  myself live under .\assets\. Re-run any time more analysis lands; missing files
  are shown greyed-out so the map stays honest.

.PARAMETER RepoPath
  Path to the FDE_Revenue_Bedrock clone. Default: C:\Files\Dev\msft\FDE_Revenue_Bedrock

.PARAMETER NoOpen
  Don't launch the browser after generating.
#>
[CmdletBinding()]
param(
  [string]$RepoPath = "C:\Files\Dev\msft\FDE_Revenue_Bedrock",
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$assets = Join-Path $here 'assets'

function Enc([string]$p) { ([uri]$p).AbsoluteUri }      # path -> file:/// URI
function Repo([string]$rel) { Join-Path $RepoPath $rel }   # repo-relative path
function Asset([string]$rel) { Join-Path $assets $rel }     # local asset path

# --- Curated manifest: sections -> items {Title, Path, Desc, Icon} ----------
$sections = @(
  @{ Name = 'Start here'; Icon = 'compass'; Blurb = 'Read these first to frame the whole project.'; Items = @(
      @{ Title = 'My onboarding plan';        Path = (Asset 'bedrock-onboarding-plan.md'); Desc = 'Phased path: MVP + bronze layer first. My working plan.'; Icon = 'map' }
      @{ Title = 'Repo README';               Path = (Repo 'README.md');                  Desc = 'Top-level project orientation.'; Icon = 'book' }
      @{ Title = 'Data architecture (doc)';   Path = (Repo 'docs\architecture\data-platform\data-architecture.md'); Desc = 'Authoritative Sources -> Bronze -> Silver -> Gold design, shortcut mechanics, nb_ naming.'; Icon = 'layers' }
      @{ Title = 'Decision log (ADR)';        Path = (Repo 'docs\adr\data-platform\decision_log.md'); Desc = 'Why the platform is shaped the way it is.'; Icon = 'gavel' }
  )}
  @{ Name = 'My bronze analysis'; Icon = 'database'; Blurb = 'What I built this session to make the source layer concrete.'; Items = @(
      @{ Title = 'Bronze source map';         Path = (Asset 'bronze-source-map.html'); Desc = 'Every upstream source, resolved to storage account + tenant, flagged shortcut vs data-copy.'; Icon = 'sitemap' }
      @{ Title = 'Bronze source map (data)';  Path = (Asset 'bronze-source-map.csv');  Desc = 'Path-grain detail behind the map (763 rows, 17 systems).'; Icon = 'table' }
  )}
  @{ Name = 'Architecture reports'; Icon = 'layers'; Blurb = 'Rendered, browsable architecture views.'; Items = @(
      @{ Title = 'Data architecture v1';      Path = (Repo 'docs\architecture\data-platform\reports\data-architecture-v1.html'); Desc = 'Latest rendered architecture report.'; Icon = 'file' }
      @{ Title = 'Data architecture v0';      Path = (Repo 'docs\architecture\data-platform\reports\data-architecture-v0.html'); Desc = 'Earlier iteration, for context.'; Icon = 'file' }
  )}
  @{ Name = 'Current-state diagrams'; Icon = 'diagram'; Blurb = 'How the legacy solutions are wired today.'; Items = @(
      @{ Title = 'RevRec data architecture';      Path = (Repo 'docs\architecture\data-platform\current-state-examples\RevRec_Data_Architecture.html'); Desc = 'Revenue Recognition current state.'; Icon = 'diagram' }
      @{ Title = 'GitHub data architecture';      Path = (Repo 'docs\architecture\data-platform\current-state-examples\GitHub_Data_Architecture.html'); Desc = 'GitHub source current state.'; Icon = 'diagram' }
      @{ Title = 'Azure Health Report';           Path = (Repo 'docs\architecture\data-platform\current-state-examples\AzureHealthReport_Data_Architecture.html'); Desc = 'Azure Health Report current state.'; Icon = 'diagram' }
      @{ Title = 'Azure Date Grain (Sangam)';     Path = (Repo 'docs\architecture\data-platform\current-state-examples\AzureDateGrain_Sangam.drawio.html'); Desc = 'Sangam date-grain diagram (Sangam is out of MVP scope).'; Icon = 'diagram' }
  )}
  @{ Name = 'Exploratory & telemetry'; Icon = 'telescope'; Blurb = 'Usage signals and estate exploration that shaped scope.'; Items = @(
      @{ Title = 'Portfolio usage';           Path = (Repo 'docs\exploratory\cube-telemetry-analysis\output\report\portfolio_usage.html'); Desc = 'Cube telemetry: what is actually used.'; Icon = 'chart' }
      @{ Title = 'Solution comparison';       Path = (Repo 'docs\exploratory\cube-telemetry-analysis\output\report\solution_comparison.html'); Desc = 'Side-by-side of the solutions.'; Icon = 'chart' }
      @{ Title = 'Intent telescope';          Path = (Repo 'docs\exploratory\data-estate-analysis\atlas-intent-telescope\intent_telescope.html'); Desc = 'Estate intent overview.'; Icon = 'telescope' }
      @{ Title = 'Intent telescope (deep)';   Path = (Repo 'docs\exploratory\data-estate-analysis\personas\intent_telescope_deep.html'); Desc = 'Persona-level deep dive.'; Icon = 'telescope' }
      @{ Title = 'Proposed data model';       Path = (Repo 'docs\exploratory\data-estate-analysis\solution\legacy\proposal_data_model.html'); Desc = 'Legacy solution proposed model.'; Icon = 'sitemap' }
      @{ Title = 'Unified lakehouse dashboard'; Path = (Repo 'docs\exploratory\data-estate-analysis\unified_lakehouse\2nd Iteration\Unified_Lakehouse_Dashboard.html'); Desc = 'Target unified lakehouse view.'; Icon = 'database' }
      @{ Title = 'Weekly leadership report';  Path = (Repo 'docs\exploratory\project-board\weekly-leadership-report\index_v2.html'); Desc = 'Latest leadership status.'; Icon = 'chart' }
  )}
  @{ Name = 'Source inputs (bronze)'; Icon = 'table'; Blurb = 'The per-solution I/O analyses that feed the source map.'; Items = @(
      @{ Title = 'ARR I/O analysis';          Path = (Repo 'docs\exploratory\data-estate-analysis\solution\arr\repo_inventory_io.csv'); Desc = 'Annuity/Revenue Run-rate source-to-sink edges.'; Icon = 'table' }
      @{ Title = 'WCS I/O analysis';          Path = (Repo 'docs\exploratory\data-estate-analysis\solution\wcs\repo_inventory_io.csv'); Desc = 'WCS source-to-sink edges.'; Icon = 'table' }
      @{ Title = 'MWDetail I/O analysis';     Path = (Repo 'docs\exploratory\data-estate-analysis\solution\mwdetail\repo_inventory_io.csv'); Desc = 'Modern Work Detail source-to-sink edges.'; Icon = 'table' }
  )}
  @{ Name = 'Solution -> notebook mapping'; Icon = 'sitemap'; Blurb = 'How existing solution artefacts (incl. AHR) map to Fabric notebooks / unified objects.'; Items = @(
      @{ Title = 'Unified lakehouse From->To mapping'; Path = (Repo 'docs\exploratory\data-estate-analysis\unified_lakehouse\2nd Iteration\Unified_Lakehouse_FromTo_Mapping.csv'); Desc = 'Existing artefact -> unified path. Filter Solution/ArtefactType (e.g. AHR has 14 Silver Fabric notebooks).'; Icon = 'table' }
      @{ Title = 'Cross-repo to-be mapping';          Path = (Repo 'docs\exploratory\data-estate-analysis\per-repo-analysis\1st Iteration\crossrepo_tobe_mapping.csv'); Desc = 'Proposed source object -> target unified object (Silver), object-level not notebook.'; Icon = 'table' }
  )}
)

# --- Lucide-style stroke icon paths (24x24) ---------------------------------
$ICON = @{
  compass   = '<circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"/>'
  map       = '<polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/>'
  book      = '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
  layers    = '<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>'
  gavel     = '<path d="m14 13-7.5 7.5a2.12 2.12 0 0 1-3-3L11 10"/><path d="m16 16 6-6"/><path d="m8 8 6-6"/><path d="m9 7 8 8"/><path d="m21 11-8-8"/>'
  database  = '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>'
  sitemap   = '<rect x="9" y="2" width="6" height="6"/><rect x="2" y="16" width="6" height="6"/><rect x="16" y="16" width="6" height="6"/><path d="M12 8v4M5 16v-2h14v2M12 12v2"/>'
  table     = '<rect x="3" y="3" width="18" height="18"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="3" x2="9" y2="21"/>'
  file      = '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/>'
  diagram   = '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><path d="M10 6.5h6a1.5 1.5 0 0 1 1.5 1.5v6"/>'
  telescope = '<path d="m10.065 12.493-6.18 1.318a.934.934 0 0 1-1.108-.702l-.537-2.15a1.07 1.07 0 0 1 .691-1.265l13.504-4.44"/><path d="m13.56 11.747 4.332-.924"/><path d="m16 21-3.105-6.21"/><path d="M16.485 5.94a2 2 0 0 1 1.455-2.425l1.09-.272a1 1 0 0 1 1.212.727l1.515 6.06a1 1 0 0 1-.727 1.213l-1.09.272a2 2 0 0 1-2.425-1.455z"/><path d="m6.158 8.633 1.114 4.456"/><path d="m8 21 3.105-6.21"/><circle cx="12" cy="13" r="2"/>'
  chart     = '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>'
  sun       = '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>'
  moon      = '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'
  external  = '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>'
}
function Svg([string]$name, [int]$size = 20) {
  $p = $ICON[$name]; if (-not $p) { $p = $ICON['file'] }
  "<svg class='ico' width='$size' height='$size' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'>$p</svg>"
}
function HtmlEnc([string]$s) { [System.Web.HttpUtility]::HtmlEncode($s) }
Add-Type -AssemblyName System.Web

# Render a markdown file into a house-styled HTML page (Mermaid + theme) under
# assets\, so it actually renders in the browser. Returns the output path.
function Render-Markdown([string]$srcPath, [string]$title) {
  $raw = Get-Content -LiteralPath $srcPath -Raw
  $bodyHtml = (ConvertFrom-Markdown -InputObject $raw).Html
  $par  = Split-Path (Split-Path $srcPath -Parent) -Leaf
  $safe = ("$par-" + [IO.Path]::GetFileNameWithoutExtension($srcPath)) -replace '[^A-Za-z0-9_\-]','_'
  $outPath = Join-Path $assets "md-$safe.html"
  $page = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="theme-color" content="#0b0e16"/>
<title>$(HtmlEnc $title)</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script>(function(){try{var t=localStorage.getItem('theme');if(t){document.documentElement.setAttribute('data-theme',t);
 document.querySelector('meta[name=theme-color]').setAttribute('content',t==='light'?'#f5f7fb':'#0b0e16');}}catch(e){}})();</script>
<style>
:root{--radius:0;--bg:#0b0e16;--surface:#141a28;--surface-2:#1d2538;--text:#e7ecf5;--muted:#9aa6bd;--border:#28324a;--border-strong:#3a465f;--accent:#6366f1;--accent-2:#8b5cf6;--accent-grad:linear-gradient(135deg,#6366f1,#8b5cf6);--glass:rgba(20,26,40,0.72);--shadow:0 1px 2px rgba(0,0,0,.3),0 8px 24px rgba(0,0,0,.28);--shadow-accent:0 8px 20px rgba(99,102,241,.35);}
:root[data-theme='light']{--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}
@media (prefers-color-scheme: light){:root:not([data-theme='dark']){--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,sans-serif;line-height:1.65;-webkit-font-smoothing:antialiased}
.topbar{position:sticky;top:0;z-index:10;background:var(--glass);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);box-shadow:var(--shadow)}
.topbar .in{max-width:900px;margin:0 auto;padding:12px 22px;display:flex;align-items:center;gap:12px}
.back{display:inline-flex;align-items:center;gap:7px;color:var(--text);text-decoration:none;font-size:13px;font-weight:600;padding:7px 11px;border:1px solid var(--border);background:var(--surface);transition:.15s}
.back:hover{border-color:var(--accent);color:var(--accent-2)}
.ttl{font-weight:700;letter-spacing:-.01em}.spacer{flex:1}
.icon-btn{width:36px;height:36px;display:grid;place-items:center;background:var(--surface);border:1px solid var(--border);color:var(--text);cursor:pointer}
.icon-btn:hover{border-color:var(--border-strong);background:var(--surface-2)}
.doc{max-width:900px;margin:0 auto;padding:30px 26px 80px}
.doc h1{font-size:28px;letter-spacing:-.02em;margin:.2em 0 .5em;padding-bottom:.3em;border-bottom:2px solid var(--border)}
.doc h2{font-size:21px;letter-spacing:-.01em;margin:1.6em 0 .5em;padding-bottom:.25em;border-bottom:1px solid var(--border)}
.doc h3{font-size:17px;margin:1.3em 0 .4em;color:var(--accent-2)}
.doc h4{font-size:15px;margin:1.1em 0 .3em}
.doc p{margin:.7em 0}.doc ul,.doc ol{padding-left:1.4em}.doc li{margin:.25em 0}
.doc a{color:var(--accent-2);text-decoration:none}.doc a:hover{text-decoration:underline}
.doc code{font-family:'JetBrains Mono',monospace;font-size:.86em;background:var(--surface-2);border:1px solid var(--border);padding:.1em .4em}
.doc pre{background:var(--surface);border:1px solid var(--border);box-shadow:var(--shadow);padding:14px 16px;overflow:auto}
.doc pre code{background:none;border:none;padding:0}
.doc pre.mermaid{background:var(--surface);text-align:center;display:flex;justify-content:center}
.doc blockquote{margin:1em 0;padding:.4em 1em;border-left:3px solid var(--accent);background:var(--surface-2);color:var(--muted)}
.doc table{border-collapse:collapse;width:100%;margin:1em 0;font-size:14px}
.doc th,.doc td{border:1px solid var(--border);padding:7px 11px;text-align:left}
.doc th{background:var(--surface-2);font-weight:600}
.doc tr:nth-child(even) td{background:var(--surface)}
.doc hr{border:none;border-top:1px solid var(--border);margin:1.8em 0}
.doc img{max-width:100%}
</style></head>
<body>
<header class="topbar"><div class="in">
 <a class="back" href="../index.html">$(Svg 'compass' 16) Home Base</a>
 <span class="ttl">$(HtmlEnc $title)</span><span class="spacer"></span>
 <button class="icon-btn" id="themeBtn" title="Toggle theme" aria-label="Toggle theme"></button>
</div></header>
<main class="doc">
$bodyHtml
</main>
<script>
 var sun="$(Svg 'sun' 20)", moon="$(Svg 'moon' 20)", btn=document.getElementById('themeBtn');
 function cur(){return document.documentElement.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');}
 function paint(){btn.innerHTML=cur()==='light'?moon:sun;} paint();
 btn.onclick=function(){var n=cur()==='light'?'dark':'light';document.documentElement.setAttribute('data-theme',n);
  try{localStorage.setItem('theme',n);}catch(e){}
  document.querySelector('meta[name=theme-color]').setAttribute('content',n==='light'?'#f5f7fb':'#0b0e16');paint();
  location.reload();};
</script>
<script type="module">
 import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
 document.querySelectorAll('pre>code.language-mermaid').forEach(function(c){
   var d=document.createElement('pre');d.className='mermaid';d.textContent=c.textContent;c.parentElement.replaceWith(d);});
 var dark=(document.documentElement.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark'))!=='light';
 mermaid.initialize({startOnLoad:false,theme:dark?'dark':'neutral',securityLevel:'loose'});
 mermaid.run();
</script>
</body></html>
"@
  Set-Content -LiteralPath $outPath -Value $page -Encoding UTF8
  return $outPath
}

# Render a CSV into a house-styled, filterable HTML table under assets\, so it
# actually renders in the browser instead of downloading. Returns output path.
function Render-Csv([string]$srcPath, [string]$title) {
  $rows = @(Import-Csv -LiteralPath $srcPath)
  $cols = if ($rows.Count) { $rows[0].PSObject.Properties.Name } else { @() }
  $rowCount = $rows.Count
  $thead = ($cols | ForEach-Object { "<th>$(HtmlEnc $_)</th>" }) -join ''
  $tb = New-Object System.Text.StringBuilder
  foreach ($r in $rows) {
    [void]$tb.Append('<tr>')
    foreach ($c in $cols) { [void]$tb.Append("<td>$(HtmlEnc ([string]$r.$c))</td>") }
    [void]$tb.Append('</tr>')
  }
  $tbody = $tb.ToString()
  $par  = Split-Path (Split-Path $srcPath -Parent) -Leaf
  $safe = ("$par-" + [IO.Path]::GetFileNameWithoutExtension($srcPath)) -replace '[^A-Za-z0-9_\-]','_'
  $outPath = Join-Path $assets "csv-$safe.html"
  $page = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="theme-color" content="#0b0e16"/>
<title>$(HtmlEnc $title)</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400&display=swap" rel="stylesheet">
<script>(function(){try{var t=localStorage.getItem('theme');if(t){document.documentElement.setAttribute('data-theme',t);
 document.querySelector('meta[name=theme-color]').setAttribute('content',t==='light'?'#f5f7fb':'#0b0e16');}}catch(e){}})();</script>
<style>
:root{--radius:0;--bg:#0b0e16;--surface:#141a28;--surface-2:#1d2538;--text:#e7ecf5;--muted:#9aa6bd;--border:#28324a;--border-strong:#3a465f;--accent:#6366f1;--accent-2:#8b5cf6;--glass:rgba(20,26,40,0.72);--shadow:0 1px 2px rgba(0,0,0,.3),0 8px 24px rgba(0,0,0,.28);}
:root[data-theme='light']{--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}
@media (prefers-color-scheme: light){:root:not([data-theme='dark']){--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
.topbar{position:sticky;top:0;z-index:10;background:var(--glass);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);box-shadow:var(--shadow)}
.topbar .in{max-width:1300px;margin:0 auto;padding:12px 22px;display:flex;align-items:center;gap:12px}
.back{display:inline-flex;align-items:center;gap:7px;color:var(--text);text-decoration:none;font-size:13px;font-weight:600;padding:7px 11px;border:1px solid var(--border);background:var(--surface);transition:.15s}
.back:hover{border-color:var(--accent);color:var(--accent-2)}
.ttl{font-weight:700;letter-spacing:-.01em}.spacer{flex:1}
.count{color:var(--muted);font-size:12.5px;padding:6px 10px;border:1px solid var(--border);background:var(--surface)}
.find{background:var(--surface);border:1px solid var(--border);color:var(--text);font:inherit;font-size:13px;padding:7px 11px;min-width:220px}
.find:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(99,102,241,.2)}
.icon-btn{width:36px;height:36px;display:grid;place-items:center;background:var(--surface);border:1px solid var(--border);color:var(--text);cursor:pointer}
.icon-btn:hover{border-color:var(--border-strong);background:var(--surface-2)}
.wrap{max-width:100%;margin:0;padding:0;overflow:auto;height:calc(100vh - 61px)}
table{border-collapse:collapse;width:max-content;min-width:100%;font-size:12.5px;font-family:'JetBrains Mono',monospace}
thead th{position:sticky;top:0;background:var(--surface-2);color:var(--text);text-align:left;padding:10px 13px;border:1px solid var(--border-strong);border-bottom:2px solid var(--accent);font-family:Inter,sans-serif;font-size:13px;font-weight:700;letter-spacing:-.01em;cursor:pointer;white-space:nowrap;z-index:2}
thead th:hover{color:var(--accent-2)}
td{border:1px solid var(--border);padding:7px 13px;vertical-align:top;white-space:nowrap}
table.wrapped td{white-space:normal;overflow-wrap:anywhere;max-width:360px}
tbody tr:nth-child(even) td{background:var(--surface)}
tbody tr:hover td{background:var(--surface-2)}
</style></head>
<body>
<header class="topbar"><div class="in">
 <a class="back" href="../index.html">$(Svg 'compass' 16) Home Base</a>
 <span class="ttl">$(HtmlEnc $title)</span>
 <span class="count" id="cnt">$rowCount rows</span><span class="spacer"></span>
 <input class="find" id="find" type="search" placeholder="Filter rows..."/>
 <button class="back" id="wrapBtn" title="Toggle text wrapping">Wrap</button>
 <button class="icon-btn" id="themeBtn" title="Toggle theme" aria-label="Toggle theme"></button>
</div></header>
<div class="wrap"><table id="tbl"><thead><tr>$thead</tr></thead><tbody>
$tbody
</tbody></table></div>
<script>
 var sun="$(Svg 'sun' 20)", moon="$(Svg 'moon' 20)", btn=document.getElementById('themeBtn');
 function cur(){return document.documentElement.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');}
 function paint(){btn.innerHTML=cur()==='light'?moon:sun;} paint();
 btn.onclick=function(){var n=cur()==='light'?'dark':'light';document.documentElement.setAttribute('data-theme',n);
  try{localStorage.setItem('theme',n);}catch(e){}
  document.querySelector('meta[name=theme-color]').setAttribute('content',n==='light'?'#f5f7fb':'#0b0e16');paint();};
 var tb=document.querySelector('#tbl tbody'), all=[].slice.call(tb.rows), cnt=document.getElementById('cnt');
 var wb=document.getElementById('wrapBtn');
 wb.onclick=function(){document.getElementById('tbl').classList.toggle('wrapped');wb.style.borderColor=document.getElementById('tbl').classList.contains('wrapped')?'var(--accent)':'';};
 document.getElementById('find').addEventListener('input',function(e){
  var q=e.target.value.toLowerCase(), n=0;
  all.forEach(function(r){var hit=r.textContent.toLowerCase().indexOf(q)>-1;r.style.display=hit?'':'none';if(hit)n++;});
  cnt.textContent=n+' / '+all.length+' rows';});
 document.querySelectorAll('#tbl thead th').forEach(function(th,i){var asc=true;
  th.addEventListener('click',function(){var rows=all.slice().sort(function(a,b){
   var x=a.cells[i].textContent.trim(), y=b.cells[i].textContent.trim();
   var nx=parseFloat(x), ny=parseFloat(y);
   if(!isNaN(nx)&&!isNaN(ny)){return asc?nx-ny:ny-nx;}
   return asc?x.localeCompare(y):y.localeCompare(x);});
   asc=!asc;rows.forEach(function(r){tb.appendChild(r);});});});
</script>
</body></html>
"@
  Set-Content -LiteralPath $outPath -Value $page -Encoding UTF8
  return $outPath
}

$total = 0; $present = 0
$sb = New-Object System.Text.StringBuilder
foreach ($sec in $sections) {
  [void]$sb.Append("<section class='grp'><div class='grp-head'>$(Svg $sec.Icon 18)<h2>$(HtmlEnc $sec.Name)</h2></div>")
  if ($sec.Blurb) { [void]$sb.Append("<p class='blurb'>$(HtmlEnc $sec.Blurb)</p>") }
  [void]$sb.Append("<div class='cards'>")
  foreach ($it in $sec.Items) {
    $total++
    $exists = Test-Path $it.Path
    if ($exists) { $present++ }
    $ext  = [IO.Path]::GetExtension($it.Path).TrimStart('.').ToLower()
    $link = $it.Path
    if ($exists -and $ext -eq 'md')  { $link = Render-Markdown $it.Path $it.Title }
    if ($exists -and $ext -eq 'csv') { $link = Render-Csv      $it.Path $it.Title }
    $cls = if ($exists) { 'card' } else { 'card missing' }
    $href = if ($exists) { "href='$(Enc $link)' target='_blank' rel='noopener'" } else { "aria-disabled='true'" }
    $tag  = switch ($ext) { 'html' { 'page' } 'csv' { 'table' } 'md' { 'doc' } default { $ext } }
    $badge = if ($exists) { "<span class='pill $tag'>$tag</span>" } else { "<span class='pill gone'>missing</span>" }
    [void]$sb.Append("<a class='$cls' $href><div class='card-ico'>$(Svg $it.Icon 22)</div><div class='card-body'><div class='card-title'>$(HtmlEnc $it.Title) $badge</div><div class='card-desc'>$(HtmlEnc $it.Desc)</div></div><div class='card-go'>$(Svg 'external' 16)</div></a>")
  }
  [void]$sb.Append("</div></section>")
}
$cards = $sb.ToString()
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

# --- Page (jimb house style: squared, indigo->violet, dark default + toggle) -
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="theme-color" content="#0b0e16"/>
<title>Bedrock - Home Base</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<script>
 (function(){try{var t=localStorage.getItem('theme');if(t){document.documentElement.setAttribute('data-theme',t);
 document.querySelector('meta[name=theme-color]').setAttribute('content', t==='light'?'#f5f7fb':'#0b0e16');}}catch(e){}})();
</script>
<style>
:root{--radius:0;--radius-lg:0;
 --bg:#0b0e16;--surface:#141a28;--surface-2:#1d2538;--surface-3:#28324a;
 --text:#e7ecf5;--muted:#9aa6bd;--border:#28324a;--border-strong:#3a465f;
 --accent:#6366f1;--accent-2:#8b5cf6;--accent-grad:linear-gradient(135deg,#6366f1 0%,#8b5cf6 100%);--on-accent:#fff;
 --glass:rgba(20,26,40,0.72);--glass-strong:rgba(20,26,40,0.9);
 --shadow:0 1px 2px rgba(0,0,0,0.3),0 8px 24px rgba(0,0,0,0.28);--shadow-accent:0 8px 20px rgba(99,102,241,0.35);}
:root[data-theme='light']{--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;
 --text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;
 --glass:rgba(255,255,255,0.72);--glass-strong:rgba(255,255,255,0.9);}
@media (prefers-color-scheme: light){:root:not([data-theme='dark']){--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;
 --text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);--glass-strong:rgba(255,255,255,0.9);}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,sans-serif;line-height:1.5;-webkit-font-smoothing:antialiased}
h1,h2{letter-spacing:-0.01em;margin:0}
.topbar{position:sticky;top:0;z-index:10;background:var(--glass);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);box-shadow:var(--shadow)}
.topbar .in{max-width:1100px;margin:0 auto;padding:14px 22px;display:flex;align-items:center;gap:14px}
.brand{display:flex;align-items:center;gap:12px}
.logo{width:38px;height:38px;display:grid;place-items:center;background:var(--accent-grad);color:#fff;box-shadow:var(--shadow-accent)}
.brand h1{font-size:18px;font-weight:700}
.brand .sub{color:var(--muted);font-size:12.5px;font-weight:500}
.spacer{flex:1}
.count{color:var(--muted);font-size:12.5px;font-weight:500;padding:6px 10px;border:1px solid var(--border);background:var(--surface)}
.icon-btn{width:38px;height:38px;display:grid;place-items:center;background:var(--surface);border:1px solid var(--border);color:var(--text);cursor:pointer;transition:.15s}
.icon-btn:hover{border-color:var(--border-strong);background:var(--surface-2)}
.wrap{max-width:1100px;margin:0 auto;padding:26px 22px 70px}
.lede{color:var(--muted);font-size:14.5px;max-width:70ch;margin:2px 0 26px}
.grp{margin:0 0 30px}
.grp-head{display:flex;align-items:center;gap:9px;color:var(--accent-2)}
.grp-head h2{font-size:15px;font-weight:700;color:var(--text);text-transform:uppercase;letter-spacing:.04em}
.blurb{color:var(--muted);font-size:13px;margin:4px 0 12px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:12px}
.card{display:flex;align-items:flex-start;gap:13px;padding:15px;background:var(--surface);border:1px solid var(--border);text-decoration:none;color:inherit;transition:.16s;box-shadow:var(--shadow)}
.card:hover{border-color:var(--accent);transform:translateY(-1px);box-shadow:var(--shadow-accent)}
.card.missing{opacity:.45;pointer-events:none;box-shadow:none}
.card-ico{width:40px;height:40px;flex:none;display:grid;place-items:center;background:var(--surface-2);color:var(--accent-2);border:1px solid var(--border)}
.card-body{flex:1;min-width:0}
.card-title{font-weight:600;font-size:14.5px;display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.card-desc{color:var(--muted);font-size:12.5px;margin-top:3px}
.card-go{color:var(--muted);flex:none;align-self:center}
.card:hover .card-go{color:var(--accent)}
.pill{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;padding:2px 7px;border:1px solid var(--border-strong);color:var(--muted)}
.pill.page{color:var(--accent-2);border-color:var(--accent-2)}
.pill.data{color:#10b981;border-color:#10b981}
.pill.table{color:#10b981;border-color:#10b981}
.pill.doc{color:#f59e0b;border-color:#f59e0b}
.pill.gone{color:#ef4444;border-color:#ef4444}
.foot{color:var(--muted);font-size:12px;border-top:1px solid var(--border);padding-top:16px;margin-top:8px}
.ico{display:block}
</style>
</head>
<body>
<header class="topbar"><div class="in">
 <div class="brand"><div class="logo">$(Svg 'database' 22)</div>
  <div><h1>Bedrock &mdash; Home Base</h1><div class="sub">One umbrella for understanding the project</div></div></div>
 <div class="spacer"></div>
 <div class="count">$present / $total linked</div>
 <button class="icon-btn" id="themeBtn" title="Toggle theme" aria-label="Toggle theme"></button>
</div></header>
<main class="wrap">
 <p class="lede">A visual map of everything that helps make sense of FDE Revenue Bedrock &mdash; start at the top, then dig into the source layer. Links open the files in place; nothing confidential is copied here.</p>
 $cards
 <p class="foot">Generated $stamp by Build-BedrockHub.ps1. Re-run it any time more analysis lands. Missing items are greyed out.</p>
</main>
<script>
 var sun="$(Svg 'sun' 20)", moon="$(Svg 'moon' 20)";
 var btn=document.getElementById('themeBtn');
 function cur(){return document.documentElement.getAttribute('data-theme')|| (matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');}
 function paint(){btn.innerHTML=cur()==='light'?moon:sun;}
 paint();
 btn.onclick=function(){var n=cur()==='light'?'dark':'light';document.documentElement.setAttribute('data-theme',n);
  try{localStorage.setItem('theme',n);}catch(e){}
  document.querySelector('meta[name=theme-color]').setAttribute('content',n==='light'?'#f5f7fb':'#0b0e16');paint();};
</script>
</body>
</html>
"@

$out = Join-Path $here 'index.html'
Set-Content -Path $out -Value $html -Encoding UTF8
Write-Host "Wrote $out  ($present/$total assets present)"
if (-not $NoOpen) { Start-Process $out }
