<#
.SYNOPSIS
  Show the Copilot CLI sessions on THIS machine that can be resumed, read from the
  local session store (`%USERPROFILE%\.copilot\session-store.db`).

.DESCRIPTION
  A session is "resumable" when the CLI can resolve `copilot --resume=<id>` against a
  row in session-store.db. This script lists those sessions with their turn count,
  checkpoint count, summary, cwd, repo, and last-active time (shown in LOCAL time).

  By default only sessions WITH conversation (turns > 0) are shown, because empty
  0-turn shells have nothing to restore (a common gotcha for folder-only imports that
  never got a DB row). Use -All to include them.

  Output modes:
    (default)  a console table
    -Json      machine-readable JSON (for Copilot to pick from)
    -Html      write a dark/light HTML report and open it in the browser

  This complements Import-CopilotSessions.ps1: Import lists sessions available in the
  OneDrive SHARE (from other machines); this lists what is resumable LOCALLY right now.

.PARAMETER All
  Include empty sessions (0 turns) as well.

.PARAMETER Json
  Emit JSON instead of a table.

.PARAMETER Html
  Write an HTML report to %USERPROFILE%\.copilot\_resumable-sessions.html and open it.

.PARAMETER DbPath
  Override the path to session-store.db (default: %USERPROFILE%\.copilot\session-store.db).

.PARAMETER Top
  Show only the newest N sessions.

.EXAMPLE
  .\Show-ResumableSessions.ps1
  # console table of locally resumable sessions

.EXAMPLE
  .\Show-ResumableSessions.ps1 -Html
  # build + open the dark/light HTML report (with per-row copy of the resume command)
#>
[CmdletBinding()]
param(
    [switch] $All,
    [switch] $Json,
    [switch] $Html,
    [string] $DbPath,
    [int]    $Top
)

$ErrorActionPreference = 'Stop'

if (-not $DbPath) { $DbPath = Join-Path $env:USERPROFILE '.copilot\session-store.db' }
if (-not (Test-Path $DbPath)) { throw "session-store.db not found: $DbPath" }

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) { throw "python is required to read session-store.db but was not found on PATH." }

$outDir  = Join-Path $env:USERPROFILE '.copilot'
$jsonOut = Join-Path $outDir '_resumable-sessions.json'
$htmlOut = Join-Path $outDir '_resumable-sessions.html'

# --- Query the DB (and optionally build the HTML) in one python pass --------------
$script = @'
import sqlite3, os, sys, json, datetime, html

db      = sys.argv[1]
jsonOut = sys.argv[2]
htmlOut = sys.argv[3]
showAll = sys.argv[4] == "1"
doHtml  = sys.argv[5] == "1"
top     = int(sys.argv[6]) if sys.argv[6] else 0

c = sqlite3.connect(db); cur = c.cursor()
rows = cur.execute("""
  select s.id, s.summary, s.cwd, s.repository, s.created_at, s.updated_at,
         (select count(*) from turns t where t.session_id = s.id) as turns,
         (select count(*) from checkpoints k where k.session_id = s.id) as cps
  from sessions s
  order by s.updated_at desc
""").fetchall()

def loc(ts):
    if not ts: return ""
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z","+00:00")).astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts

items = []
for sid, summ, cwd, repo, cr, upd, turns, cps in rows:
    if not showAll and turns == 0:
        continue
    items.append(dict(id=sid, summary=summ or "", cwd=cwd or "", repo=repo or "",
                      created=loc(cr), updated=loc(upd), turns=turns, cps=cps))
if top and top > 0:
    items = items[:top]

json.dump(items, open(jsonOut, "w", encoding="utf-8"))

if doHtml:
    def row(o):
        cls = ' class="empty"' if o["turns"] == 0 else ''
        sid = o["id"]
        summ = html.escape(o["summary"]) or '<span class=dim>(no summary)</span>'
        return (f'<tr{cls}>'
                f'<td><code>{sid[:8]}</code><button class="cp" data-id="{html.escape(sid)}" title="Copy resume command">copy</button></td>'
                f'<td class="num">{o["turns"]}</td><td class="num">{o["cps"]}</td>'
                f'<td>{summ}</td><td>{o["updated"]}</td>'
                f'<td class="path">{html.escape(o["cwd"])}</td>'
                f'<td class="path">{html.escape(o["repo"])}</td></tr>')
    body = "\n".join(row(o) for o in items)
    withturns = sum(1 for o in items if o["turns"] > 0)
    total = len(items)
    doc = """<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Resumable Copilot sessions</title>
<style>
:root{--bg:#fafafa;--fg:#1c1c22;--dim:#6b7280;--card:#fff;--line:#e4e4e8;--accent:#2563eb;--empty:#9ca3af;--hover:#f0f4ff;--code:#eef1f6;}
@media(prefers-color-scheme:dark){:root{--bg:#14151a;--fg:#e6e7eb;--dim:#9aa0ac;--card:#1c1d24;--line:#2c2e38;--accent:#60a5fa;--empty:#565a66;--hover:#232635;--code:#262833;}}
html[data-theme=light]{--bg:#fafafa;--fg:#1c1c22;--dim:#6b7280;--card:#fff;--line:#e4e4e8;--accent:#2563eb;--empty:#9ca3af;--hover:#f0f4ff;--code:#eef1f6;}
html[data-theme=dark]{--bg:#14151a;--fg:#e6e7eb;--dim:#9aa0ac;--card:#1c1d24;--line:#2c2e38;--accent:#60a5fa;--empty:#565a66;--hover:#232635;--code:#262833;}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;padding:24px}
h1{font-size:20px;margin:0 0 4px}.sub{color:var(--dim);margin:0 0 16px}
.bar{display:flex;gap:12px;align-items:center;margin-bottom:16px;flex-wrap:wrap}
input#q{flex:1;min-width:200px;padding:8px 12px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--fg)}
button{cursor:pointer;border:1px solid var(--line);background:var(--card);color:var(--fg);border-radius:7px;padding:6px 12px;font:inherit}
button:hover{border-color:var(--accent);color:var(--accent)}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}
th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--line);vertical-align:top}
th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--dim);cursor:pointer;user-select:none}
tr:last-child td{border-bottom:none}tbody tr:hover{background:var(--hover)}
td.num{text-align:right;font-variant-numeric:tabular-nums}
tr.empty td{color:var(--empty)}
code{background:var(--code);padding:2px 6px;border-radius:5px;font:12px ui-monospace,Consolas,monospace}
.path{font:12px ui-monospace,Consolas,monospace;color:var(--dim);max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.dim{color:var(--dim)}.cp{margin-left:6px;padding:1px 7px;font-size:11px}
.toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:var(--accent);color:#fff;padding:8px 16px;border-radius:8px;opacity:0;transition:.2s;pointer-events:none}
.toast.show{opacity:1}
.legend{color:var(--dim);font-size:12px;margin-top:10px}
</style></head><body>
<h1>Resumable Copilot CLI sessions</h1>
<p class=sub>__WITH__ with conversation &middot; __TOTAL__ shown &middot; times in local time. Resume with <code>mycopilot --resume=&lt;id&gt;</code> (7+ char prefix works).</p>
<div class=bar>
<input id=q placeholder="Filter by summary, id, cwd, repo...">
<label><input type=checkbox id=hideEmpty checked> hide empty (0 turns)</label>
<button id=theme>&#9680; theme</button>
</div>
<table id=t><thead><tr>
<th data-k=0>ID</th><th data-k=1 class=num>Turns</th><th data-k=2 class=num>Chk</th>
<th data-k=3>Summary</th><th data-k=4>Updated</th><th data-k=5>cwd</th><th data-k=6>repo</th>
</tr></thead><tbody>
__ROWS__
</tbody></table>
<p class=legend>Greyed rows = empty sessions (0 turns) &mdash; nothing to restore.</p>
<div class=toast id=toast></div>
<script>
const tb=document.querySelector('#t tbody'), q=document.getElementById('q'), he=document.getElementById('hideEmpty');
function apply(){const s=q.value.toLowerCase();[...tb.rows].forEach(r=>{
 const t=r.innerText.toLowerCase(), emptyRow=r.classList.contains('empty');
 r.style.display=(t.includes(s) && !(he.checked&&emptyRow))?'':'none';});}
q.oninput=apply; he.onchange=apply; apply();
document.querySelectorAll('th[data-k]').forEach(th=>th.onclick=()=>{
 const k=+th.dataset.k, rows=[...tb.rows], num=(th.classList.contains('num'));
 const asc=th._asc=!th._asc;
 rows.sort((a,b)=>{let x=a.cells[k].innerText,y=b.cells[k].innerText;
  if(num){x=+x||0;y=+y||0;} return (x>y?1:x<y?-1:0)*(asc?1:-1);});
 rows.forEach(r=>tb.appendChild(r));});
tb.addEventListener('click',e=>{const b=e.target.closest('.cp');if(!b)return;
 navigator.clipboard.writeText('mycopilot --resume='+b.dataset.id).then(()=>{
 const t=document.getElementById('toast');t.textContent='Copied: mycopilot --resume='+b.dataset.id.slice(0,8)+'...';
 t.classList.add('show');setTimeout(()=>t.classList.remove('show'),1600);});});
const th=document.getElementById('theme');
th.onclick=()=>{const h=document.documentElement,cur=h.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light');
 h.setAttribute('data-theme',cur==='dark'?'light':'dark');};
</script></body></html>"""
    doc = doc.replace("__ROWS__", body).replace("__WITH__", str(withturns)).replace("__TOTAL__", str(total))
    open(htmlOut, "w", encoding="utf-8").write(doc)

print(len(items))
'@

$tmp = New-TemporaryFile
Rename-Item $tmp "$($tmp.FullName).py"
$tmp = "$($tmp.FullName).py"
Set-Content -Path $tmp -Value $script -Encoding UTF8
try {
    $count = & $py.Source $tmp $DbPath $jsonOut $htmlOut ([int]$All.IsPresent) ([int]$Html.IsPresent) "$Top"
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

$items = Get-Content $jsonOut -Raw | ConvertFrom-Json

if ($Json) {
    $items | ConvertTo-Json -Depth 4
    return
}

if ($Html) {
    Start-Process $htmlOut
    Write-Host "Opened resumable-sessions report: $htmlOut" -ForegroundColor Green
    return
}

if (-not $items) {
    Write-Host "No resumable sessions found$(if(-not $All){' with conversation (try -All)'}) in $DbPath"
    return
}

$items |
    Select-Object @{n='id';e={$_.id.Substring(0,8)}},
                  @{n='turns';e={$_.turns}},
                  @{n='chk';e={$_.cps}},
                  @{n='updated';e={$_.updated}},
                  @{n='summary';e={$_.summary}},
                  @{n='cwd';e={$_.cwd}} |
    Format-Table -AutoSize -Wrap

Write-Host "Resume one with:  mycopilot --resume=<id>   (7+ char prefix works)" -ForegroundColor Yellow
