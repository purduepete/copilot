#!/usr/bin/env python3
"""Render a dark/light HTML report of a git change set.

THE canonical "show me the changed files" report. Per @jimb's standing rule this is
generated and reviewed BEFORE a PR is opened -- and it is a script rather than
hand-written HTML each time so the layout is identical on every run.

Usage:
    python New-ChangeReport.py --repo <path> [--range origin/main...HEAD] [--out <file>]
                               [--title "..."] [--note "..."] [--open]

Grouping: files are grouped by their containing `*.Notebook` folder when there is one
(a Fabric notebook is a folder of files, so a flat file list buries the thing that
actually changed), otherwise by path.
"""
import argparse
import collections
import datetime
import html
import os
import subprocess
import sys
import webbrowser

STATUS = {
    "A": ("added", "#2ea043"),
    "M": ("modified", "#d29922"),
    "R": ("renamed", "#8957e5"),
    "D": ("deleted", "#f85149"),
    "C": ("copied", "#58a6ff"),
}
KIND = {"arr": "#58a6ff", "shared": "#3fb950", "other": "#db6d28"}
# Layer sections, rendered in medallion order. Anything unrecognised falls into "other".
LAYER_ORDER = ["bronze", "silver", "gold", "shared", "other"]
LAYER_COLOR = {
    "bronze": "#cd7f32",
    "silver": "#a8b3bd",
    "gold": "#d4af37",
    "shared": "#3fb950",
    "other": "#8b949e",
}


def layer_of(path):
    """The medallion layer a file belongs to, from its position under processing/."""
    parts = path.split("/")
    if "processing" in parts:
        nxt = parts.index("processing") + 1
        if nxt < len(parts) and parts[nxt] in LAYER_ORDER:
            return parts[nxt]
    for candidate in LAYER_ORDER:
        if f"/{candidate}/" in path:
            return candidate
    return "other"


def git(repo, *args):
    r = subprocess.run(["git"] + list(args), cwd=repo, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"git {' '.join(args)} failed:\n{r.stderr.strip()}")
    return r.stdout


def badge(text, color):
    return (f'<span class="badge" style="background:{color}22;color:{color};'
            f'border:1px solid {color}55">{text}</span>')


def status_badge(st):
    label, color = STATUS.get(st[0], (st, "#8b949e"))
    return badge(label, color)


def collect(repo, rng):
    numstat = {}
    for line in git(repo, "diff", "--numstat", "-M", rng).strip().split("\n"):
        if not line:
            continue
        add, dele, path = line.split("\t")
        numstat[path] = (add, dele)

    groups = collections.OrderedDict()
    for line in git(repo, "diff", "--name-status", "-M", rng).strip().split("\n"):
        if not line:
            continue
        parts = line.split("\t")
        st, path = parts[0], parts[-1]
        old = parts[1] if st.startswith(("R", "C")) else None
        segments = path.split("/")
        nb = next((s for s in segments if s.endswith(".Notebook") or s.endswith(".Environment")), None)
        key = nb.rsplit(".", 1)[0] if nb else path
        kind = "shared" if "/shared/" in path else ("arr" if "_arr_" in key or key.endswith("_arr") else "other")
        g = groups.setdefault(key, {"kind": kind, "layer": layer_of(path), "files": []})
        add, dele = numstat.get(path, ("0", "0"))
        g["files"].append({"st": st, "name": segments[-1], "add": add, "del": dele, "old": old})
    return groups, numstat


def render(groups, numstat, meta):
    rows = []
    by_layer = collections.OrderedDict()
    for key, g in groups.items():
        by_layer.setdefault(g["layer"], []).append((key, g))

    for layer in sorted(by_layer, key=lambda l: LAYER_ORDER.index(l) if l in LAYER_ORDER else 99):
        entries = by_layer[layer]
        la = sum(int(f["add"]) for _, g in entries for f in g["files"] if f["add"].isdigit())
        ld = sum(int(f["del"]) for _, g in entries for f in g["files"] if f["del"].isdigit())
        nfiles = sum(len(g["files"]) for _, g in entries)
        color = LAYER_COLOR.get(layer, "#8b949e")
        rows.append(
            f'<tr class="ly"><td colspan="5" style="border-left:4px solid {color}">'
            f'<span style="color:{color}">{html.escape(layer)}</span>'
            f'<span class="ct">{len(entries)} items &middot; {nfiles} files &middot; '
            f'<span class="pos">+{la}</span> / <span class="neg">-{ld}</span></span></td></tr>'
        )
        for key, g in entries:
            ga = sum(int(f["add"]) for f in g["files"] if f["add"].isdigit())
            gd = sum(int(f["del"]) for f in g["files"] if f["del"].isdigit())
            rows.append(
                f'<tr class="nb"><td>{html.escape(key)}</td>'
                f'<td>{badge(g["kind"], KIND[g["kind"]])}</td>'
                f'<td class="num pos">+{ga}</td><td class="num neg">-{gd}</td>'
                f'<td>{"".join(status_badge(f["st"]) for f in g["files"])}</td></tr>'
            )
            for f in g["files"]:
                was = ""
                if f["old"]:
                    prev = f["old"].split("/")[-2] if "/" in f["old"] else f["old"]
                    was = f'<div class="old">was: {html.escape(prev)}</div>'
                rows.append(
                    f'<tr class="f"><td class="fn">{html.escape(f["name"])}{was}</td>'
                    f'<td>{status_badge(f["st"])}</td>'
                    f'<td class="num pos">+{f["add"]}</td><td class="num neg">-{f["del"]}</td><td></td></tr>'
                )

    total_add = sum(int(a) for a, d in numstat.values() if a.isdigit())
    total_del = sum(int(d) for a, d in numstat.values() if d.isdigit())
    layer_stats = "".join(
        f'<div class="stat"><b style="color:{LAYER_COLOR.get(l, "#8b949e")}">{len(by_layer[l])}</b>'
        f'<span>{html.escape(l)}</span></div>'
        for l in sorted(by_layer, key=lambda l: LAYER_ORDER.index(l) if l in LAYER_ORDER else 99)
    )

    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(meta["title"])}</title><style>
:root{{color-scheme:dark light;--bg:#0d1117;--fg:#e6edf3;--card:#161b22;--bd:#30363d;--mut:#8b949e}}
html[data-t=light]{{--bg:#ffffff;--fg:#1f2328;--card:#f6f8fa;--bd:#d0d7de;--mut:#656d76}}
@media (prefers-color-scheme:light){{html:not([data-t]){{--bg:#ffffff;--fg:#1f2328;--card:#f6f8fa;--bd:#d0d7de;--mut:#656d76}}}}
body{{margin:0;font:16px/1.5 -apple-system,'Segoe UI',sans-serif;background:var(--bg);color:var(--fg)}}
.wrap{{max-width:1100px;margin:0 auto;padding:28px 20px 60px}}
h1{{font-size:22px;margin:0 0 4px}}
.sub{{color:var(--mut);font-size:14px;margin-bottom:20px}}
.stats{{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:22px}}
.stat{{background:var(--card);border:1px solid var(--bd);border-radius:8px;padding:10px 16px}}
.stat b{{display:block;font-size:21px}} .stat span{{color:var(--mut);font-size:12.5px}}
table{{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--bd);
border-radius:8px;overflow:hidden}}
td,th{{padding:7px 12px;border-bottom:1px solid var(--bd);text-align:left;font-size:16px}}
th{{font-size:12.5px;color:var(--mut);text-transform:uppercase;letter-spacing:.5px}}
tr.ly td{{background:rgba(127,127,127,.13);font-weight:700;font-size:13px;
text-transform:uppercase;letter-spacing:.9px;padding:9px 12px}}
tr.ly .ct{{float:right;font-weight:400;text-transform:none;letter-spacing:0;
color:var(--mut);font-size:12.5px}}
tr.nb td{{background:rgba(127,127,127,.07);font-weight:600;font-size:16.5px}}
tr.f .fn{{padding-left:34px;color:var(--mut);font-family:ui-monospace,Consolas,monospace;
font-size:13.5px;font-weight:400}}
.old{{color:#8957e5;font-size:12px;margin-top:2px}}
.num{{text-align:right;font-family:ui-monospace,Consolas,monospace;width:80px}}
.pos{{color:#3fb950}} .neg{{color:#f85149}}
.badge{{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11.5px;margin-right:4px}}
button{{position:fixed;top:16px;right:16px;background:var(--card);color:var(--fg);
border:1px solid var(--bd);border-radius:8px;padding:8px 14px;cursor:pointer;font-size:14px}}
</style></head><body>
<button onclick="var r=document.documentElement;r.dataset.t=r.dataset.t=='light'?'dark':'light'">theme</button>
<div class="wrap">
<h1>{html.escape(meta["title"])}</h1>
<div class="sub">{html.escape(meta["branch"])} &middot; generated {meta["when"]}</div>
<div class="stats">
<div class="stat"><b>{meta["groups"]}</b><span>notebooks</span></div>
<div class="stat"><b>{len(numstat)}</b><span>files</span></div>
<div class="stat"><b class="pos">+{total_add}</b><span>added</span></div>
<div class="stat"><b class="neg">-{total_del}</b><span>removed</span></div>
{layer_stats}
</div>
<table><tr><th>notebook / file</th><th>type</th><th>+</th><th>-</th><th>changes</th></tr>
{"".join(rows)}</table>
</div></body></html>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--range", dest="rng", default="origin/main...HEAD")
    ap.add_argument("--out", default="change_report.html")
    ap.add_argument("--title", default="Changed files")
    ap.add_argument("--branch", default="", help="label for the subtitle, e.g. 'my/branch -> main'")
    ap.add_argument("--open", action="store_true")
    a = ap.parse_args()

    groups, numstat = collect(a.repo, a.rng)
    if not numstat:
        sys.exit(f"no changes in range {a.rng}")

    branch = a.branch
    if not branch and "..." in a.rng:
        left, right = a.rng.split("...")
        branch = f"{right} \u2192 {left.replace('origin/', '')}"

    meta = {
        "title": a.title,
        "branch": branch or a.rng,
        "when": datetime.datetime.now().strftime("%Y-%m-%d %H:%M local"),
        "groups": len(groups),
    }
    out = os.path.abspath(a.out)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(render(groups, numstat, meta))
    print(f"{meta['groups']} notebooks, {len(numstat)} files -> {out}")
    if a.open:
        webbrowser.open(f"file:///{out.replace(os.sep, '/')}")


if __name__ == "__main__":
    main()
