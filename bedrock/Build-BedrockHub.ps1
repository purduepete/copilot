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
  @{ Name = 'Reference'; Icon = 'glossary'; Blurb = 'Quick lookups for the alphabet soup.'; Items = @(
      @{ Title = 'Glossary (acronyms & TLAs)'; Path = (Asset 'glossary.html'); Desc = 'Searchable list of the projects acronyms, systems and jargon - what each one means.'; Icon = 'glossary' }
  )}
  @{ Name = 'My bronze analysis'; Icon = 'database'; Blurb = 'What I built this session to make the source layer concrete.'; Items = @(
      @{ Title = 'Bronze source map';         Path = (Asset 'bronze-source-map.html'); Desc = 'Every upstream source, resolved to storage account + tenant, flagged shortcut vs data-copy.'; Icon = 'sitemap' }
      @{ Title = 'Bronze source map (data)';  Path = (Asset 'bronze-source-map.csv');  Desc = 'Path-grain detail behind the map (763 rows, 17 systems).'; Icon = 'table' }
      @{ Title = 'Notebook lineage explorer'; Path = (Asset 'notebook-lineage.html');  Desc = 'Pick any notebook -> see the bronze sources it reads (inputs) and the tables it writes (outputs).'; Icon = 'sitemap' }
      @{ Title = 'Repository analysis';        Path = (Asset 'repo-analysis.html');     Desc = 'Per-solution repo, stack & 6-label file classification (ARR, WCS, MWDetail) - extracted from the proposal data model.'; Icon = 'database' }
  )}
  @{ Name = 'External'; Icon = 'external'; Blurb = 'Live tools and portals outside this repo.'; Items = @(
      @{ Title = 'Mira - Revenue Projects'; Url = 'https://mira.microsoft.com/revenueProjects/'; Desc = 'Revenue projects portal on Mira.'; Icon = 'external' }
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
  glossary  = '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/><path d="M8 6.5h7M8 9.5h5"/>'
  search    = '<circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>'
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
# Same SVG but safe to embed inside a double-quoted JS string (single quotes only).
function SvgJs([string]$name, [int]$size = 20) { (Svg $name $size) -replace '"', "'" }
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
 var sun="$(SvgJs 'sun')", moon="$(SvgJs 'moon')", btn=document.getElementById('themeBtn');
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
 var sun="$(SvgJs 'sun')", moon="$(SvgJs 'moon')", btn=document.getElementById('themeBtn');
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

# Build a per-notebook lineage explorer: pick a notebook -> see the source data
# it reads (inputs) and the tables it writes (outputs), parsed from each
# solution's repo_inventory_analyzed.csv. Returns output path (or $null).
function Build-NotebookLineage([hashtable[]]$solutions) {
  $data = New-Object System.Collections.Generic.List[object]
  foreach ($s in $solutions) {
    $csv = Repo $s.Csv
    if (-not (Test-Path $csv)) { continue }
    foreach ($r in (Import-Csv -LiteralPath $csv)) {
      $hasIn  = $r.inputs  -and $r.inputs  -ne '[]'
      $hasOut = $r.outputs -and $r.outputs -ne '[]'
      if (-not ($hasIn -or $hasOut)) { continue }
      $in = @(); $out = @()
      if ($hasIn)  { try { $in  = @($r.inputs  | ConvertFrom-Json) } catch { $in = @() } }
      if ($hasOut) { try { $out = @($r.outputs | ConvertFrom-Json) } catch { $out = @() } }
      $data.Add([pscustomobject]@{
        sol     = $s.Name
        file    = $r.file
        ext     = $r.extension
        purpose = $r.file_purpose
        grain   = $r.column_grain
        inputs  = @($in  | ForEach-Object { [pscustomobject]@{ system=$_.system; name=$_.name; path=$_.path; relevancy=$_.relevancy } })
        outputs = @($out | ForEach-Object { [pscustomobject]@{ system=$_.system; name=$_.name; path=$_.path; relevancy=$_.relevancy } })
      })
    }
  }
  if ($data.Count -eq 0) { return $null }
  $json = $data | ConvertTo-Json -Depth 6 -Compress
  $nbCount = $data.Count
  $outPath = Join-Path $assets 'notebook-lineage.html'
  $page = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="theme-color" content="#0b0e16"/>
<title>Notebook lineage</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script>(function(){try{var t=localStorage.getItem('theme');if(t){document.documentElement.setAttribute('data-theme',t);
 document.querySelector('meta[name=theme-color]').setAttribute('content',t==='light'?'#f5f7fb':'#0b0e16');}}catch(e){}})();</script>
<style>
:root{--radius:0;--bg:#0b0e16;--surface:#141a28;--surface-2:#1d2538;--surface-3:#28324a;--text:#e7ecf5;--muted:#9aa6bd;--border:#28324a;--border-strong:#3a465f;--accent:#6366f1;--accent-2:#8b5cf6;--green:#10b981;--amber:#f59e0b;--glass:rgba(20,26,40,0.72);--shadow:0 1px 2px rgba(0,0,0,.3),0 8px 24px rgba(0,0,0,.28);}
:root[data-theme='light']{--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}
@media (prefers-color-scheme: light){:root:not([data-theme='dark']){--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased;height:100vh;display:flex;flex-direction:column}
.topbar{background:var(--glass);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);box-shadow:var(--shadow);flex:none}
.topbar .in{padding:11px 20px;display:flex;align-items:center;gap:12px}
.back{display:inline-flex;align-items:center;gap:7px;color:var(--text);text-decoration:none;font-size:13px;font-weight:600;padding:7px 11px;border:1px solid var(--border);background:var(--surface);transition:.15s}
.back:hover{border-color:var(--accent);color:var(--accent-2)}
.ttl{font-weight:700;letter-spacing:-.01em}.sub{color:var(--muted);font-size:12.5px}.spacer{flex:1}
.icon-btn{width:36px;height:36px;display:grid;place-items:center;background:var(--surface);border:1px solid var(--border);color:var(--text);cursor:pointer}
.icon-btn:hover{border-color:var(--border-strong);background:var(--surface-2)}
.main{flex:1;display:flex;min-height:0}
.side{width:360px;flex:none;border-right:1px solid var(--border);display:flex;flex-direction:column;background:var(--surface)}
.side .find{margin:12px;background:var(--bg);border:1px solid var(--border);color:var(--text);font:inherit;font-size:13px;padding:8px 11px}
.side .find:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(99,102,241,.2)}
.list{overflow:auto;flex:1;padding:0 8px 16px}
.sol-h{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--accent-2);padding:12px 8px 5px}
.nb{display:flex;align-items:center;gap:8px;padding:8px 9px;cursor:pointer;border:1px solid transparent;font-size:13px}
.nb:hover{background:var(--surface-2)}
.nb.sel{background:var(--surface-2);border-color:var(--accent)}
.nb .nm{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-family:'JetBrains Mono',monospace;font-size:12px}
.ext{font-size:9.5px;font-weight:700;text-transform:uppercase;padding:1px 5px;border:1px solid var(--border-strong);color:var(--muted)}
.ext.py{color:var(--accent-2);border-color:var(--accent-2)}.ext.sql{color:var(--green);border-color:var(--green)}
.detail{flex:1;overflow:auto;padding:24px 28px 60px}
.detail h2{margin:0;font-size:19px;letter-spacing:-.01em;font-family:'JetBrains Mono',monospace}
.detail .purpose{color:var(--muted);font-size:14px;margin:8px 0 4px}
.io{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:22px}
@media (max-width:900px){.io{grid-template-columns:1fr}}
.io h3{display:flex;align-items:center;gap:8px;font-size:13px;text-transform:uppercase;letter-spacing:.05em;margin:0 0 8px}
.io .in h3{color:var(--green)}.io .out h3{color:var(--amber)}
.io table{border-collapse:collapse;width:100%;font-size:12px}
.io th,.io td{border:1px solid var(--border);padding:6px 9px;text-align:left;vertical-align:top}
.io th{background:var(--surface-2);font-weight:600;white-space:nowrap}
.io td.p{font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--muted);overflow-wrap:anywhere}
.io .sys{font-weight:600;color:var(--accent-2);white-space:nowrap}
.empty{color:var(--muted);font-style:italic;padding:8px 0}
.hint{color:var(--muted);display:grid;place-items:center;height:100%;text-align:center;padding:40px}
.badge{font-size:10px;font-weight:700;border:1px solid var(--border-strong);padding:1px 6px;color:var(--muted);margin-left:6px}
</style></head>
<body>
<header class="topbar"><div class="in">
 <a class="back" href="../index.html">$(Svg 'compass' 16) Home Base</a>
 <span class="ttl">Notebook lineage</span><span class="sub">$nbCount notebooks/scripts with traced inputs &amp; outputs</span>
 <span class="spacer"></span>
 <button class="icon-btn" id="themeBtn" title="Toggle theme" aria-label="Toggle theme"></button>
</div></header>
<div class="main">
 <aside class="side">
  <input class="find" id="find" type="search" placeholder="Filter notebooks / source / table..."/>
  <div class="list" id="list"></div>
 </aside>
 <main class="detail" id="detail"><div class="hint">$(Svg 'sitemap' 40)<div style="margin-top:14px">Pick a notebook on the left to see the bronze sources it reads and the tables it writes.</div></div></main>
</div>
<script>
 var sun="$(SvgJs 'sun')", moon="$(SvgJs 'moon')", btn=document.getElementById('themeBtn');
 function cur(){return document.documentElement.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');}
 function paint(){btn.innerHTML=cur()==='light'?moon:sun;} paint();
 btn.onclick=function(){var n=cur()==='light'?'dark':'light';document.documentElement.setAttribute('data-theme',n);
  try{localStorage.setItem('theme',n);}catch(e){}
  document.querySelector('meta[name=theme-color]').setAttribute('content',n==='light'?'#f5f7fb':'#0b0e16');paint();};

 var D=$json;
 D.forEach(function(n,i){n._i=i;n._hay=((n.file||'')+' '+(n.purpose||'')+' '+JSON.stringify(n.inputs||[])+' '+JSON.stringify(n.outputs||[])).toLowerCase();});
 function esc(s){var d=document.createElement('div');d.textContent=(s==null?'':s);return d.innerHTML;}
 function base(f){var p=(f||'').split('/');return p[p.length-1];}
 var listEl=document.getElementById('list'), detailEl=document.getElementById('detail');

 function buildList(q){
  q=(q||'').toLowerCase();
  var shown=D.filter(function(n){return !q||n._hay.indexOf(q)>-1;});
  var bySol={}; shown.forEach(function(n){(bySol[n.sol]=bySol[n.sol]||[]).push(n);});
  var html='';
  Object.keys(bySol).sort().forEach(function(sol){
   html+='<div class="sol-h">'+esc(sol)+' &middot; '+bySol[sol].length+'</div>';
   bySol[sol].sort(function(a,b){return base(a.file).localeCompare(base(b.file));}).forEach(function(n){
    var ex=(n.ext||'').toLowerCase();
    html+='<div class="nb" data-i="'+n._i+'"><span class="ext '+ex+'">'+esc(ex)+'</span><span class="nm" title="'+esc(n.file)+'">'+esc(base(n.file))+'</span></div>';
   });
  });
  listEl.innerHTML=html||'<div class="empty" style="padding:16px">No matches.</div>';
 }
 function ioTable(arr){
  if(!arr||!arr.length) return '<div class="empty">none</div>';
  var h='<table><thead><tr><th>System</th><th>Name</th><th>Path</th><th>Relevancy</th></tr></thead><tbody>';
  arr.forEach(function(o){h+='<tr><td class="sys">'+esc(o.system)+'</td><td>'+esc(o.name)+'</td><td class="p">'+esc(o.path)+'</td><td>'+esc(o.relevancy)+'</td></tr>';});
  return h+'</tbody></table>';
 }
 function show(n){
  [].forEach.call(listEl.querySelectorAll('.nb'),function(e){e.classList.toggle('sel',e.getAttribute('data-i')==n._i);});
  var grain=n.grain?'<span class="badge">grain: '+esc(n.grain)+'</span>':'';
  detailEl.innerHTML='<h2>'+esc(base(n.file))+'<span class="badge">'+esc(n.sol)+'</span>'+grain+'</h2>'
   +'<div class="purpose">'+esc(n.purpose||'(no stated purpose)')+'</div>'
   +'<div style="font-family:JetBrains Mono,monospace;font-size:11px;color:var(--muted)">'+esc(n.file)+'</div>'
   +'<div class="io">'
     +'<div class="in"><h3>&#9660; Inputs &mdash; bronze sources it reads ('+((n.inputs||[]).length)+')</h3>'+ioTable(n.inputs)+'</div>'
     +'<div class="out"><h3>&#9650; Outputs &mdash; tables it writes ('+((n.outputs||[]).length)+')</h3>'+ioTable(n.outputs)+'</div>'
   +'</div>';
 }
 listEl.addEventListener('click',function(e){var el=e.target.closest('.nb');if(!el)return;show(D[+el.getAttribute('data-i')]);});
 document.getElementById('find').addEventListener('input',function(e){buildList(e.target.value);});
 buildList('');
</script>
</body></html>
"@
  Set-Content -LiteralPath $outPath -Value $page -Encoding UTF8
  return $outPath
}

# Build a searchable glossary page (acronyms / TLAs / project terms) under assets\.
# Content is rendered server-side so it shows even if JS is disabled; the search
# box just hides non-matching rows. Returns the output path.
function Build-Glossary {
  # Term | Expansion (blank if not documented) | Category | Definition
  $entries = @(
    @{ T='Bedrock';     F='';                              C='Project'; D='This project / repo (FDE_Revenue_Bedrock): the new finance source-data (bronze) platform on Microsoft Fabric.' }
    @{ T='MVP';         F='Minimum Viable Product';        C='Project'; D='The initial deliverable scope this onboarding targets - MVP + the bronze (source) layer first.' }
    @{ T='TLA';         F='Three-Letter Acronym';          C='Project'; D='...like most of the entries on this page.' }
    @{ T='ADR';         F='Architecture Decision Record';  C='Project'; D='A logged design decision (see the decision log) explaining why the platform is shaped the way it is.' }

    @{ T='ARR';         F='Annual Recurring Revenue';      C='Solutions & domains'; D='Legacy revenue solution (Synapse/T-SQL + Serverless SQL + AS cube). One of the three bronze pilot solutions analyzed this session.' }
    @{ T='WCS';         F='Worldwide Commercial Sales';   C='Solutions & domains'; D='Expiration/renewal reporting solution covering EA + NCE. One of the three pilot solutions; repo FDE_ProcessDataCloud, dual Synapse Serverless + dual TMSR cubes.' }
    @{ T='MWDetail';    F='Modern Work Detail';            C='Solutions & domains'; D='Fabric-native solution (PySpark + TMDL + Direct Lake) for Modern Work (M365) revenue detail - the most modern of the pilot solutions.' }
    @{ T='AHR';         F='';                              C='Solutions & domains'; D='A Silver-layer solution in the FINHUB family (repo FDE_CnAI_Reporting, GPSPartnerData). 14 existing Fabric notebooks; no bronze notebook yet (greenfield).' }
    @{ T='FINHUB';      F='Finance Hub';                   C='Solutions & domains'; D='The solution family that AHR belongs to.' }
    @{ T='RevRec';      F='Revenue Recognition';           C='Solutions & domains'; D='A finance solution/domain (has a current-state architecture diagram in this hub).' }
    @{ T='ADG';         F='';                              C='Solutions & domains'; D='A finance solution/domain (listed alongside AHR and RevRec). Expansion not documented.' }
    @{ T='ACR';         F='Annual Contract Revenue';       C='Solutions & domains'; D='A revenue measure used in the semantic models.' }
    @{ T='EA';          F='Enterprise Agreement';          C='Solutions & domains'; D='A Microsoft commercial licensing motion; one of the two reporting tracks WCS covers.' }
    @{ T='NCE';         F='New Commerce Experience';       C='Solutions & domains'; D="Microsoft's newer commerce/licensing platform; the other WCS reporting track." }

    @{ T='FDE';         F='Finance Data Engineering';      C='Orgs & tenants'; D='The team/tenant owning this Bedrock platform (the FDE_* repo prefix). Shares a tenant with CSEO for shortcut purposes.' }
    @{ T='CSEO';        F='Core Services Engineering & Operations'; C='Orgs & tenants'; D="Microsoft's internal engineering org; owns the OCDM/EDL commerce lakes. Same tenant as FDE -> reachable by shortcut." }
    @{ T='ECADL';       F='';                              C='Orgs & tenants'; D='Cross-org commerce data lake reached via the Synapse linked service ECADL_PROD; an Intake source consumed by data copy (cross-org, not a shortcut).' }
    @{ T='GPSPartnerData'; F='Global Partner Solutions partner data'; C='Orgs & tenants'; D='Data family for AHR / partner-seller solutions.' }

    @{ T='ADLS';        F='Azure Data Lake Storage (Gen2)'; C='Lakes & storage'; D='The underlying data-lake storage behind most upstream sources.' }
    @{ T='OneLake';     F='';                              C='Lakes & storage'; D="Microsoft Fabric's single, tenant-wide data lake - the storage under every Fabric workspace. Bronze tables/shortcuts live here." }
    @{ T='FDL';         F='Financial Data Lake';           C='Lakes & storage'; D='A finance data lake (e.g., the MSSales FDL; fdedatalakeprod01).' }
    @{ T='EDL';         F='Enterprise Data Lake';          C='Lakes & storage'; D="CSEO's enterprise data lake." }
    @{ T='EDLP';        F='EDL (data products)';           C='Lakes & storage'; D='The data-products surface layered over the EDL.' }
    @{ T='OCDM';        F='One Commercial Data Model';     C='Lakes & storage'; D='CSEO commercial data-products model on the EDL; a bronze source (shortcut).' }
    @{ T='SPME / SPMEDLP'; F='Seller & Partner Marketplace Experience EDL'; C='Lakes & storage'; D='CSEO commerce partner-seller experience lake (note: NOT the Microsoft-PME tenant).' }
    @{ T='MSSales';     F='';                              C='Lakes & storage'; D='Microsoft Sales source data, consumed via the MSSales FDL (shortcut).' }
    @{ T='Conformed';   F='';                              C='Lakes & storage'; D='The conformed/prod curated layer (fdedatalakeprod01 / abidata); consumed into bronze via a OneLake shortcut.' }
    @{ T='Intake';      F='';                              C='Lakes & storage'; D='The INTAKE stage of the legacy medallion pipeline; cross-org (via ECADL) so it arrives by data copy, not shortcut.' }
    @{ T='DATAPROD';    F='Data Production (curated)';     C='Lakes & storage'; D='The curated data-prod output layer (e.g., ARRDataProd) that serving views/cubes read from.' }

    @{ T='Fabric';      F='Microsoft Fabric';              C='Platform & tech'; D='The target analytics SaaS platform: OneLake + Lakehouse + notebooks + semantic models.' }
    @{ T='Lakehouse';   F='';                              C='Platform & tech'; D='A Fabric artifact combining Delta tables + a files area - where bronze data lands.' }
    @{ T='Shortcut';    F='';                              C='Platform & tech'; D='A OneLake/Fabric shortcut: a virtual pointer to external storage so data is read in place (no copy). Preferred when same-tenant.' }
    @{ T='Direct Lake'; F='';                              C='Platform & tech'; D='A Fabric semantic-model mode that reads Delta tables straight from OneLake (no import, no DirectQuery).' }
    @{ T='Synapse';     F='Azure Synapse Analytics';       C='Platform & tech'; D="Legacy platform for ARR: Spark notebooks + Serverless SQL." }
    @{ T='ADF';         F='Azure Data Factory';            C='Platform & tech'; D='Pipeline orchestration service.' }
    @{ T='AAS';         F='Azure Analysis Services';       C='Platform & tech'; D='Hosts AS-Tabular cubes (legacy serving layer).' }
    @{ T='TMDL';        F='Tabular Model Definition Language'; C='Platform & tech'; D='Text format for Fabric/Power BI semantic models (tables, columns, measures).' }
    @{ T='TMSR';        F='';                              C='Platform & tech'; D='The AS-Tabular cube/semantic format used by ARR (legacy serving). Expansion not documented.' }
    @{ T='PySpark';     F='';                              C='Platform & tech'; D='The Python Spark API used by the modern (Fabric/Synapse) notebooks.' }
    @{ T='T-SQL';       F='Transact-SQL';                  C='Platform & tech'; D='The SQL dialect used by the legacy Synapse notebooks/stored procs.' }
    @{ T='OPENROWSET';  F='';                              C='Platform & tech'; D='A Synapse Serverless SQL function that queries ADLS files directly as a table.' }
    @{ T='SSDT';        F='SQL Server Data Tools';         C='Platform & tech'; D='.sqlproj projects for the legacy on-prem SQL estate (INTAKE -> STAGING -> DATAPROD).' }
    @{ T='Atlas';       F='';                              C='Platform & tech'; D='The semantic-model (cube) usage-analysis dataset/effort.' }

    @{ T='Medallion';   F='';                              C='Data concepts'; D='The Bronze -> Silver -> Gold layered data architecture.' }
    @{ T='Hub-and-spoke'; F='';                            C='Data concepts'; D='The platform topology: one central hub (the spine) + workstream spokes that consume or diverge, with mandatory publish-back.' }
    @{ T='Spine';       F='';                              C='Data concepts'; D='The hub - the canonical conformed model (shared lakehouses, the Gold uber-grain, the one semantic model, orchestration). Spokes reuse spine facts/dims only by adding lateral columns or slicing rows; a different grain or extra rows earns a carve-out instead. Never mutate the spine (incumbent wins).' }
    @{ T='Spoke';       F='';                              C='Data concepts'; D='A workstream/solution built on the hub. It either consumes the spine (~90%) or diverges with a spoke-local custom dimension that is crosswalked back to the spine.' }
    @{ T='Crosswalk';   F='';                              C='Data concepts'; D="A map notebook (the custom mapping) linking a spoke's custom dimension to the spine; broadly useful ones get promoted into the spine." }
    @{ T='Carve-out';   F='';                              C='Data concepts'; D='A new fact/dim a spoke earns when it needs a different grain or extra rows, rather than mutating a spine table.' }
    @{ T='Bronze';      F='';                              C='Data concepts'; D="Raw ingested source layer - this project's focus. Mostly shortcut-based; greenfield." }
    @{ T='Silver';      F='';                              C='Data concepts'; D='Cleaned/conformed layer (e.g., AHR builds 14 Silver notebooks).' }
    @{ T='Gold';        F='';                              C='Data concepts'; D='Curated serving layer: facts, dims, cubes/semantic models.' }
    @{ T='DIM';         F='Dimension';                     C='Data concepts'; D='A dimension table - descriptive attributes you slice facts by.' }
    @{ T='FACT';        F='';                              C='Data concepts'; D='A fact table - transactions / measures (the numbers you aggregate).' }
    @{ T='BRIDGE';      F='';                              C='Data concepts'; D='A bridge table resolving a many-to-many relationship between dimensions.' }
    @{ T='ETL';         F='Extract, Transform, Load';      C='Data concepts'; D='The data-movement pattern that fills each medallion layer.' }
    @{ T='nb_';         F='';                              C='Data concepts'; D='Naming-prefix convention for bronze notebooks (per the data-architecture doc).' }
  )

  $order = @('Project','Solutions & domains','Orgs & tenants','Lakes & storage','Platform & tech','Data concepts')
  $rows = New-Object System.Text.StringBuilder
  foreach ($cat in $order) {
    $grp = @($entries | Where-Object { $_.C -eq $cat })
    if ($grp.Count -eq 0) { continue }
    $grp = $grp | Sort-Object { $_.T.ToLower() }
    [void]$rows.Append("<div class='cat' data-cat='$(HtmlEnc $cat)'><h2>$(HtmlEnc $cat) <span class='n'>$($grp.Count)</span></h2>")
    foreach ($e in $grp) {
      $hay = (($e.T + ' ' + $e.F + ' ' + $e.D).ToLower())
      $full = if ($e.F) { "<span class='full'>$(HtmlEnc $e.F)</span>" } else { '' }
      [void]$rows.Append("<div class='term' data-h='$(HtmlEnc $hay)'><div class='t'>$(HtmlEnc $e.T)$full</div><div class='d'>$(HtmlEnc $e.D)</div></div>")
    }
    [void]$rows.Append("</div>")
  }
  $rowsHtml = $rows.ToString()
  $count = $entries.Count
  $outPath = Join-Path $assets 'glossary.html'
  $page = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="theme-color" content="#0b0e16"/>
<title>Glossary - Bedrock</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script>(function(){try{var t=localStorage.getItem('theme');if(t){document.documentElement.setAttribute('data-theme',t);
 document.querySelector('meta[name=theme-color]').setAttribute('content',t==='light'?'#f5f7fb':'#0b0e16');}}catch(e){}})();</script>
<style>
:root{--radius:0;--bg:#0b0e16;--surface:#141a28;--surface-2:#1d2538;--surface-3:#28324a;--text:#e7ecf5;--muted:#9aa6bd;--border:#28324a;--border-strong:#3a465f;--accent:#6366f1;--accent-2:#8b5cf6;--glass:rgba(20,26,40,0.72);--shadow:0 1px 2px rgba(0,0,0,.3),0 8px 24px rgba(0,0,0,.28);}
:root[data-theme='light']{--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}
@media (prefers-color-scheme: light){:root:not([data-theme='dark']){--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
.topbar{position:sticky;top:0;z-index:5;background:var(--glass);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);box-shadow:var(--shadow)}
.topbar .in{padding:11px 20px;display:flex;align-items:center;gap:12px;max-width:1100px;margin:0 auto}
.back{display:inline-flex;align-items:center;gap:7px;color:var(--text);text-decoration:none;font-size:13px;font-weight:600;padding:7px 11px;border:1px solid var(--border);background:var(--surface);transition:.15s}
.back:hover{border-color:var(--accent);color:var(--accent-2)}
.ttl{font-weight:700;letter-spacing:-.01em}.sub{color:var(--muted);font-size:12.5px}.spacer{flex:1}
.icon-btn{width:36px;height:36px;display:grid;place-items:center;background:var(--surface);border:1px solid var(--border);color:var(--text);cursor:pointer}
.icon-btn:hover{border-color:var(--border-strong);background:var(--surface-2)}
.wrap{max-width:1100px;margin:0 auto;padding:22px 20px 70px}
.searchbox{position:relative;margin:0 0 22px}
.searchbox .si{position:absolute;left:12px;top:50%;transform:translateY(-50%);color:var(--muted);pointer-events:none}
.find{width:100%;background:var(--surface);border:1px solid var(--border);color:var(--text);font:inherit;font-size:14px;padding:11px 13px 11px 40px}
.find:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(99,102,241,.2)}
.cat{margin:0 0 26px}
.cat h2{font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:var(--accent-2);margin:0 0 11px;padding-bottom:7px;border-bottom:1px solid var(--border)}
.cat h2 .n{color:var(--muted);font-weight:600;margin-left:6px}
.grid{}
.term{display:grid;grid-template-columns:220px 1fr;gap:16px;padding:11px 12px;border:1px solid transparent;border-bottom:1px solid var(--border)}
.term:hover{background:var(--surface-2);border-color:var(--border)}
.term .t{font-family:'JetBrains Mono',monospace;font-weight:600;font-size:14px;color:var(--text);display:flex;flex-direction:column;gap:3px}
.term .full{font-family:Inter,sans-serif;font-weight:500;font-size:12px;color:var(--accent-2)}
.term .d{color:var(--muted);font-size:13.5px;line-height:1.5}
.nohit{display:none;color:var(--muted);font-style:italic;padding:30px 4px}
@media (max-width:640px){.term{grid-template-columns:1fr;gap:4px}}
</style></head>
<body>
<header class="topbar"><div class="in">
 <a class="back" href="../index.html">$(Svg 'compass' 16) Home Base</a>
 <span class="ttl">Glossary</span><span class="sub">$count terms - acronyms, TLAs &amp; project jargon</span>
 <span class="spacer"></span>
 <button class="icon-btn" id="themeBtn" title="Toggle theme" aria-label="Toggle theme"></button>
</div></header>
<div class="wrap">
 <div class="searchbox"><span class="si">$(Svg 'search' 18)</span>
  <input class="find" id="find" type="search" placeholder="Filter terms, expansions or meanings... (e.g. shortcut, lake, ARR)" autofocus/></div>
 <div id="glist">$rowsHtml</div>
 <div class="nohit" id="nohit">No terms match your filter.</div>
</div>
<script>
 var sun="$(SvgJs 'sun')", moon="$(SvgJs 'moon')", btn=document.getElementById('themeBtn');
 function cur(){return document.documentElement.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');}
 function paint(){btn.innerHTML=cur()==='light'?moon:sun;} paint();
 btn.onclick=function(){var n=cur()==='light'?'dark':'light';document.documentElement.setAttribute('data-theme',n);
  try{localStorage.setItem('theme',n);}catch(e){}
  document.querySelector('meta[name=theme-color]').setAttribute('content',n==='light'?'#f5f7fb':'#0b0e16');paint();};
 var find=document.getElementById('find'), nohit=document.getElementById('nohit');
 find.addEventListener('input',function(){
  var q=find.value.trim().toLowerCase(), any=false;
  var cats=document.querySelectorAll('.cat');
  for(var i=0;i<cats.length;i++){
   var terms=cats[i].querySelectorAll('.term'), shown=0;
   for(var j=0;j<terms.length;j++){
    var hit=!q||terms[j].getAttribute('data-h').indexOf(q)>-1;
    terms[j].style.display=hit?'':'none'; if(hit){shown++;any=true;}
   }
   cats[i].style.display=shown?'':'none';
  }
  nohit.style.display=any?'none':'block';
 });
</script>
</body></html>
"@
  [IO.File]::WriteAllText($outPath, $page, (New-Object Text.UTF8Encoding $false))
  return $outPath
}
$null = Build-Glossary

# Parse the legacy "Common Data Model - Proposal" page and extract, per solution,
# the Repository-analysis block (repo/path/files/stack/description + the 6-label
# file classification). Emits a comparison page under assets\. Returns path|null.
function Build-RepoAnalysis {
  $src = Repo 'docs\exploratory\data-estate-analysis\solution\legacy\proposal_data_model.html'
  if (-not (Test-Path $src)) { return $null }
  $h = [IO.File]::ReadAllText($src)
  function _clean([string]$s) { ([System.Web.HttpUtility]::HtmlDecode(($s -replace '<[^>]+>', ''))).Trim() -replace '\s+', ' ' }
  $catColor = {
    param($n)
    switch -Regex ($n) { 'bronze' { '#c2772f' } 'silver' { '#9aa6bd' } 'gold' { '#f5b301' } 'semantic' { '#8b5cf6' } default { '#6366f1' } }
  }
  $cards = New-Object System.Text.StringBuilder
  $found = 0
  foreach ($sol in @(
      @{ id = 'arr';      name = 'ARR' },
      @{ id = 'wcs';      name = 'WCS (EA + NCE)' },
      @{ id = 'mwdetail'; name = 'MWDetail' })) {
    $blk = [regex]::Match($h, "(?is)data-sol=`"$($sol.id)`">(.*?)(?=<div class=`"sol-block`"|`$)").Groups[1].Value
    if (-not $blk) { continue }
    $ra = [regex]::Match($blk, '(?is)<summary>Repository analysis</summary>(.*?)</details>').Groups[1].Value
    if (-not $ra) { continue }
    $kv = @([regex]::Matches($ra, '(?is)<div class="kv"[^>]*>(.*?)</div>') | ForEach-Object { _clean $_.Groups[1].Value })
    $repo   = ([regex]::Match(($kv -join ' '), '(?i)Repo:\s*([^\s\u00B7]+)').Groups[1].Value.Trim())
    $branch = ([regex]::Match(($kv -join ' '), '(?i)Branch:\s*([^\s\u00B7]+)').Groups[1].Value.Trim())
    $path   = ([regex]::Match(($kv -join ' '), '(?i)Path:\s*([^\u00B7]+?)(?:\s+Files:|$)').Groups[1].Value.Trim())
    $files  = ([regex]::Match(($kv -join ' '), '(?i)Files:\s*([^\u00B7]+)').Groups[1].Value.Trim())
    $stack  = ([regex]::Match(($kv -join ' '), '(?i)Stack:\s*(.+?)(?:\s{2,}|$)').Groups[1].Value.Trim())
    $desc   = if ($kv.Count) { $kv[$kv.Count - 1] } else { '' }
    $rows = @([regex]::Matches($ra, '(?is)<div class="row"><div class="nm">(.*?)</div>.*?<div class="vv">(.*?)</div>') |
        ForEach-Object { [pscustomobject]@{ nm = (_clean $_.Groups[1].Value); v = [int](_clean $_.Groups[2].Value) } })
    $max = ($rows | Measure-Object v -Maximum).Maximum; if (-not $max) { $max = 1 }
    $bronze = ($rows | Where-Object { $_.nm -eq 'data-bronze' } | Select-Object -First 1).v
    $bars = New-Object System.Text.StringBuilder
    foreach ($r in $rows) {
      $pct = [Math]::Max(2, [Math]::Round($r.v / $max * 100))
      $col = & $catColor $r.nm
      [void]$bars.Append("<div class='cbar'><div class='cnm'>$(HtmlEnc $r.nm)</div><div class='cbw'><div class='cfill' style='width:$pct%;background:$col'></div></div><div class='cvv'>$($r.v)</div></div>")
    }
    # Bronze-layer notebooks: pull the per-file medallion classification and deep-link
    # each bronze file to its file view in Azure DevOps (org AgBI, repo from the proposal).
    $adoOrg = 'https://starlightagilebi.visualstudio.com/AgBI/_git'
    $medCsv = Repo "docs\exploratory\data-estate-analysis\solution\$($sol.id)\repo_inventory_medallion.csv"
    $bzList = New-Object System.Text.StringBuilder
    $bzCount = 0
    if (Test-Path $medCsv) {
      $bz = @(Import-Csv -LiteralPath $medCsv | Where-Object { $_.medallion -match '(?i)bronze' } | Sort-Object file)
      $bzCount = $bz.Count
      foreach ($b in $bz) {
        $full = (($path.TrimEnd('/') + '/' + $b.file) -replace ' ', '%20')
        $url = '{0}/{1}?path={2}&version=GB{3}' -f $adoOrg, $repo, $full, ($branch -replace ' ', '')
        $ext = [IO.Path]::GetExtension($b.file).TrimStart('.').ToLower()
        $nm  = (Split-Path $b.file -Leaf)
        $dir = (Split-Path $b.file -Parent) -replace '\\', '/'
        [void]$bzList.Append("<a class='bz-row' href='$([System.Web.HttpUtility]::HtmlAttributeEncode($url))' target='_blank' rel='noopener'><span class='bz-ext $ext'>$(HtmlEnc $ext)</span><span class='bz-nm'><b>$(HtmlEnc $nm)</b><span class='bz-dir'>$(HtmlEnc $dir)</span></span>$(Svg 'external' 13)</a>")
      }
    }
    $bzBlock = if ($bzCount) { "<details class='bzwrap'><summary>$(Svg 'database' 13) Bronze layer - $bzCount file$(if($bzCount -ne 1){'s'}) <span class='bz-hint'>open in Azure DevOps</span></summary><div class='bzlist'>$($bzList.ToString())</div></details>" } else { '' }
    [void]$cards.Append(@"
<div class="sol">
 <div class="sol-h"><span class="sname">$(HtmlEnc $sol.name)</span><span class="srepo">$(Svg 'database' 14) $(HtmlEnc $repo)</span></div>
 <div class="meta">
  <div><span class="ml">Path</span><code>$(HtmlEnc $path)</code></div>
  <div><span class="ml">Branch</span><code>$(HtmlEnc $branch)</code></div>
  <div><span class="ml">Files</span><b>$(HtmlEnc $files)</b></div>
  <div><span class="ml">Bronze</span><b class="bz">$bronze</b></div>
 </div>
 <div class="stack">$(HtmlEnc $stack)</div>
 <p class="desc">$(HtmlEnc $desc)</p>
 <div class="cl-h">File classification (6-label)</div>
 <div class="cls">$($bars.ToString())</div>
 $bzBlock
</div>
"@)
    $found++
  }
  if ($found -eq 0) { return $null }
  $outPath = Join-Path $assets 'repo-analysis.html'
  $page = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="theme-color" content="#0b0e16"/>
<title>Repository analysis - Bedrock</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script>(function(){try{var t=localStorage.getItem('theme');if(t){document.documentElement.setAttribute('data-theme',t);
 document.querySelector('meta[name=theme-color]').setAttribute('content',t==='light'?'#f5f7fb':'#0b0e16');}}catch(e){}})();</script>
<style>
:root{--radius:0;--bg:#0b0e16;--surface:#141a28;--surface-2:#1d2538;--surface-3:#28324a;--text:#e7ecf5;--muted:#9aa6bd;--border:#28324a;--border-strong:#3a465f;--accent:#6366f1;--accent-2:#8b5cf6;--glass:rgba(20,26,40,0.72);--shadow:0 1px 2px rgba(0,0,0,.3),0 8px 24px rgba(0,0,0,.28);}
:root[data-theme='light']{--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}
@media (prefers-color-scheme: light){:root:not([data-theme='dark']){--bg:#f5f7fb;--surface:#fff;--surface-2:#f1f3f9;--surface-3:#e5e9f2;--text:#1a2233;--muted:#5b6678;--border:#e5e9f2;--border-strong:#cdd5e4;--glass:rgba(255,255,255,0.72);}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
.topbar{position:sticky;top:0;z-index:5;background:var(--glass);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);box-shadow:var(--shadow)}
.topbar .in{padding:11px 20px;display:flex;align-items:center;gap:12px;max-width:1240px;margin:0 auto}
.back{display:inline-flex;align-items:center;gap:7px;color:var(--text);text-decoration:none;font-size:13px;font-weight:600;padding:7px 11px;border:1px solid var(--border);background:var(--surface);transition:.15s}
.back:hover{border-color:var(--accent);color:var(--accent-2)}
.ttl{font-weight:700;letter-spacing:-.01em}.sub{color:var(--muted);font-size:12.5px}.spacer{flex:1}
.icon-btn{width:36px;height:36px;display:grid;place-items:center;background:var(--surface);border:1px solid var(--border);color:var(--text);cursor:pointer}
.icon-btn:hover{border-color:var(--border-strong);background:var(--surface-2)}
.wrap{max-width:1240px;margin:0 auto;padding:22px 20px 70px}
.src{color:var(--muted);font-size:12.5px;margin:0 0 18px}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
@media (max-width:980px){.grid{grid-template-columns:1fr}}
.sol{background:var(--surface);border:1px solid var(--border);box-shadow:var(--shadow);display:flex;flex-direction:column}
.sol-h{padding:14px 16px;border-bottom:1px solid var(--border);background:var(--surface-2)}
.sname{display:block;font-weight:700;font-size:16px;letter-spacing:-.01em}
.srepo{display:inline-flex;align-items:center;gap:6px;color:var(--accent-2);font-size:12px;font-family:'JetBrains Mono',monospace;margin-top:4px}
.meta{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--border)}
.meta>div{background:var(--surface);padding:9px 14px;display:flex;flex-direction:column;gap:3px}
.ml{font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);font-weight:700}
.meta code{font-family:'JetBrains Mono',monospace;font-size:11.5px;color:var(--text);overflow-wrap:anywhere}
.meta b{font-size:14px}.bz{color:#c2772f}
.stack{padding:10px 14px;font-size:12px;color:var(--muted);border-top:1px solid var(--border)}
.desc{padding:0 14px;font-size:13px;color:var(--text);line-height:1.5;margin:6px 0 12px}
.cl-h{padding:0 14px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--accent-2)}
.cls{padding:8px 14px 16px;display:flex;flex-direction:column;gap:6px}
.cbar{display:grid;grid-template-columns:96px 1fr 44px;align-items:center;gap:9px}
.cnm{font-size:11.5px;color:var(--muted);font-family:'JetBrains Mono',monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cbw{height:9px;background:var(--surface-3);overflow:hidden}
.cfill{height:100%}
.cvv{font-size:12px;font-weight:600;text-align:right;font-variant-numeric:tabular-nums}
.bzwrap{margin:0 14px 16px;border:1px solid var(--border)}
.bzwrap summary{cursor:pointer;list-style:none;padding:9px 12px;font-size:12px;font-weight:700;color:#c2772f;display:flex;align-items:center;gap:7px;background:var(--surface-2);user-select:none}
.bzwrap summary::-webkit-details-marker{display:none}
.bzwrap[open] summary{border-bottom:1px solid var(--border)}
.bz-hint{margin-left:auto;font-weight:500;font-size:11px;color:var(--muted);text-transform:none;letter-spacing:0}
.bzlist{max-height:280px;overflow:auto}
.bz-row{display:flex;align-items:center;gap:9px;padding:7px 12px;border-bottom:1px solid var(--border);color:var(--text);text-decoration:none;transition:background .15s}
.bz-row:last-child{border-bottom:none}
.bz-row:hover{background:var(--surface-2)}
.bz-ext{flex:none;font-size:9px;font-weight:700;text-transform:uppercase;padding:2px 5px;border:1px solid var(--border-strong);color:var(--muted);min-width:34px;text-align:center}
.bz-ext.py{color:var(--accent-2);border-color:var(--accent-2)}.bz-ext.sql{color:#10b981;border-color:#10b981}.bz-ext.json{color:#f59e0b;border-color:#f59e0b}
.bz-nm{flex:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.bz-nm b{font-family:'JetBrains Mono',monospace;font-size:12px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bz-dir{font-size:10.5px;color:var(--muted);font-family:'JetBrains Mono',monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bz-row .ico{color:var(--muted);flex:none}
</style></head>
<body>
<header class="topbar"><div class="in">
 <a class="back" href="../index.html">$(Svg 'compass' 16) Home Base</a>
 <span class="ttl">Repository analysis</span><span class="sub">per-solution repo, stack &amp; file classification</span>
 <span class="spacer"></span>
 <button class="icon-btn" id="themeBtn" title="Toggle theme" aria-label="Toggle theme"></button>
</div></header>
<div class="wrap">
 <p class="src">Extracted from the legacy <code>proposal_data_model.html</code> (Common Data Model - Proposal v1).</p>
 <div class="grid">$($cards.ToString())</div>
</div>
<script>
 var sun="$(SvgJs 'sun')", moon="$(SvgJs 'moon')", btn=document.getElementById('themeBtn');
 function cur(){return document.documentElement.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');}
 function paint(){btn.innerHTML=cur()==='light'?moon:sun;} paint();
 btn.onclick=function(){var n=cur()==='light'?'dark':'light';document.documentElement.setAttribute('data-theme',n);
  try{localStorage.setItem('theme',n);}catch(e){}
  document.querySelector('meta[name=theme-color]').setAttribute('content',n==='light'?'#f5f7fb':'#0b0e16');paint();};
</script>
</body></html>
"@
  [IO.File]::WriteAllText($outPath, $page, (New-Object Text.UTF8Encoding $false))
  return $outPath
}
$null = Build-RepoAnalysis

# Pre-build the lineage explorer so the hub card resolves.
$null = Build-NotebookLineage @(
  @{ Name='ARR';      Csv='docs\exploratory\data-estate-analysis\solution\arr\repo_inventory_analyzed.csv' }
  @{ Name='WCS';      Csv='docs\exploratory\data-estate-analysis\solution\wcs\repo_inventory_analyzed.csv' }
  @{ Name='MWDetail'; Csv='docs\exploratory\data-estate-analysis\solution\mwdetail\repo_inventory_analyzed.csv' }
)

$sb = New-Object System.Text.StringBuilder
foreach ($sec in $sections) {
  [void]$sb.Append("<section class='grp'><div class='grp-head'>$(Svg $sec.Icon 18)<h2>$(HtmlEnc $sec.Name)</h2></div>")
  if ($sec.Blurb) { [void]$sb.Append("<p class='blurb'>$(HtmlEnc $sec.Blurb)</p>") }
  [void]$sb.Append("<div class='cards'>")
  foreach ($it in $sec.Items) {
    $total++
    if ($it.Url) {
      $present++
      [void]$sb.Append("<a class='card' href='$([System.Web.HttpUtility]::HtmlAttributeEncode($it.Url))' target='_blank' rel='noopener'><div class='card-ico'>$(Svg $it.Icon 22)</div><div class='card-body'><div class='card-title'>$(HtmlEnc $it.Title) <span class='pill link'>link</span></div><div class='card-desc'>$(HtmlEnc $it.Desc)</div></div><div class='card-go'>$(Svg 'external' 16)</div></a>")
      continue
    }
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
 var sun="$(SvgJs 'sun')", moon="$(SvgJs 'moon')";
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
