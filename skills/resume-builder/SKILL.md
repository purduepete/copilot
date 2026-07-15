---
name: resume-builder
description: >-
  Tailor @jimb's base resume (C:\Files\Dev\main\career) to a specific job
  description, grounded in his semi-annual Connect reviews so every claim stays
  truthful — reorder/emphasize REAL achievements, mirror the JD's language, then
  regenerate a job-specific DOCX + PDF (2 pages, never split a job across pages)
  without ever overwriting the base. WHEN: "tailor my resume", "build a resume for
  this job", "customize my resume", "resume for this job description", "apply for
  this job", "adjust my resume to this JD", "resume builder", "target this job
  posting", "make a resume variant", "rebuild my resume", "update my resume for a
  role".
argument-hint: paste the job description (or a path/URL to it)
---

# Resume builder

Produce a **job-tailored** copy of @jimb's resume from his canonical base, keeping
every claim grounded in his own performance history. The base is never edited by
this skill — tailoring always happens in a per-application copy.

## Canonical inputs (all under `C:\Files\Dev\main\career`)

| File | Role |
|------|------|
| `Jim_Brown_Resume.html` | **Base resume — source of truth.** Never overwrite. |
| `Jim_Brown_Resume.docx` / `.pdf` | Base deliverables (2 pages). |
| `build_resume_docx.py` | Generator: HTML content is mirrored here → DOCX via `python-docx` → PDF via Word COM. |
| `all-connects.md` | Consolidated semi-annual Connect reviews (Nov 2022 → present). |
| `connect_output\` | 24 individual Connect files (Mar 2015 → present). **Primary evidence bank.** |

Target roles: **Senior Database Engineer / Analyst, outside Microsoft.**

## Truthfulness rules (non-negotiable)

1. **Only claim what the connects support.** Every metric or achievement in the
   tailored resume must trace to `all-connects.md` or a `connect_output\*.md` file
   (or already be in the base, which was vetted).
2. **Distinguish his words from manager comments.** In the Connect files, the
   employee response and the *manager* comments are different voices. A number that
   appears only in manager comments is weaker evidence — surface it and ask before
   featuring it as his own accomplishment. (E.g. the "$18K/month PBI Premium" figure
   came from a manager comment and was removed at Jim's request.)
3. **Tailoring = reorder, re-emphasize, re-word to mirror the JD — never invent.**
   You may drop less-relevant bullets, promote relevant ones, and align vocabulary
   to the posting, but only for things he actually did.
4. **No Microsoft-internal jargon** (CDS, TPID, Fusion, RPS, product codenames).
   Genericize to industry-standard terms.
5. Keep it to **2 pages** and **never split a single job across a page break.**
6. **Sound human and in Jim's voice, not AI-generated** — see the next section.
   Never change facts to achieve this.

## Write in Jim's voice (required)

Recruiters and some ATS run AI-detectors, and a flag can deprioritize an accurate
resume. The base resume was deliberately re-voiced to read human-authored (an
independent LLM review dropped its "AI-generated" estimate from *moderate-to-high* to
*low-to-moderate*, "safe to use as-is"). **Preserve that voice in every variant** —
use the base as the tone exemplar and match how Jim actually writes in the connects.

Concrete voice markers to keep (these are what made it read human):

- **No bolded category lead-ins** on bullets (no `Platform architecture & migration:`
  taxonomy). Fold the idea into the sentence.
- **Bursty rhythm** — mix short single-clause bullets with longer ones that trail off
  into an aside. Never make every bullet the same verb→tech→metric shape/length.
- **Mixed voice is good, not a bug** — most bullets in resume-imperative
  ("Migrated roughly 20 years..."), a few drifting into first person mid-bullet
  ("I wrote the PySpark notebooks...", "Along the way I cut..."). That slightly
  unpolished mixing is what a human editing their own draft does; models stay too
  disciplined in one voice.
- **Hedged, imprecise numbers** where he'd be recalling from memory ("roughly 20
  years", "in some cases by around 85%", "50-plus joins") — not suspiciously clean.
- **Colloquial phrasing** he'd actually use ("held up in production", "kick off when
  data lands", "matching the original numbers exactly").
- **Plain punctuation** — no em-dashes, no semicolon-chained compound clauses.

Do **not** over-optimize: the content is dense and every bullet lands a real outcome,
which is fine. Pushing further means weakening true content, and detectors penalize
clean technical writing regardless of authorship. Match the base's register and stop.

## Workflow

1. **Get the JD.** Accept pasted text, a file path, or a URL (fetch it). Extract the
   must-have skills, responsibilities, and the exact phrasing the posting uses.
2. **Study Jim's voice first.** Re-read the current base resume (the tone exemplar)
   and skim a few `connect_output\*.md` employee responses so the rewrite echoes his
   own phrasing and rhythm rather than a generic model register.
3. **Map JD → evidence.** For each key requirement, find the supporting achievement
   in the connects. Grep is fast:
   ```powershell
   Select-String -Path C:\Files\Dev\main\career\connect_output\*.md -Pattern "synapse|pipeline|optimiz|migrat" -SimpleMatch:$false | Select-Object Filename, LineNumber, Line
   ```
   Note any requirement with **no** supporting evidence — do not fabricate; tell Jim
   it's a gap.
4. **Create the application copy** (base stays untouched). Use a slug like
   `<company>-<role>`:
   ```powershell
   $slug = "acme-senior-dba"
   $dir  = "C:\Files\Dev\main\career\applications\$slug"
   New-Item -ItemType Directory -Force -Path $dir | Out-Null
   Copy-Item C:\Files\Dev\main\career\Jim_Brown_Resume.html "$dir\resume.html"
   Copy-Item C:\Files\Dev\main\career\build_resume_docx.py   "$dir\build.py"
   ```
   In `$dir\build.py`, retarget the output path (the `DOCX =` line and the
   `CAREER` base) so it writes `$dir\Jim_Brown_Resume_<slug>.docx`, and keep its
   inline content in sync with `$dir\resume.html`.
5. **Tailor both files together** (HTML + build.py inline content must match):
   reorder/emphasize bullets, tune the Professional Summary opening line and the
   Technical Skills ordering to lead with what the JD asks for. Keep edits truthful,
   and **keep every new/edited line in Jim's voice** per the "Write in Jim's voice"
   section — any bullet you touch must still pass those markers.
6. **Regenerate DOCX + PDF and verify** (see snippet). Confirm 2 pages and that no
   job heading is separated from its bullets.
7. **Voice check before reporting.** Re-read the tailored draft against the "Write in
   Jim's voice" markers — no bolded lead-ins, bursty rhythm, mixed voice, hedged
   numbers, plain punctuation. Fix any line that slid back into generic model
   register. (Optional: ask a Gemini/ChatGPT reviewer to rate how AI-generated it
   reads and confirm it still sounds like Jim.)
8. **Report a match summary** to Jim: a short table of JD requirement → covered?
   (yes/partial/gap) → evidence (which Connect). Offer a **Gemini second opinion**
   (`gemini-3.1-pro-preview`) or ChatGPT (`gpt-5.5`) review of the fit before he
   sends it.

## Build + verify snippet (kills stray Word locks, exports, checks pages)

```powershell
$dir  = "C:\Files\Dev\main\career\applications\acme-senior-dba"
$docx = "$dir\Jim_Brown_Resume_acme-senior-dba.docx"
$pdf  = [IO.Path]::ChangeExtension($docx, ".pdf")
Get-Process WINWORD -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 1
python "$dir\build.py"
$word = New-Object -ComObject Word.Application; $word.Visible = $false
try {
  $doc = $word.Documents.Open($docx, $false, $true)
  $doc.ExportAsFixedFormat($pdf, 17)   # 17 = wdExportFormatPDF
  "PAGES: $($doc.ComputeStatistics(2))" # 2 = wdStatisticPages
  # Confirm a job block isn't split — heading and its bullets must share a page:
  foreach ($t in @("Solavei","Engineered ETL processes")) {
    $r = $doc.Content; $r.Find.Text = $t
    if ($r.Find.Execute()) { "p$($r.Information(3)): $t" }  # 3 = wdActiveEndPageNumber
  }
  $doc.Close($false)
} finally { $word.Quit(); [Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null }
```

## Layout gotcha — why jobs split (and the fix)

Word's "keep with next" (`keepNext`) is honored **only for chains that fit on one
page**. The base `build.py` therefore does **not** chain the 8 Microsoft bullets
(each `bullet(..., keep_next=False)`); the job heading is protected from orphaning by
the tagline paragraph's `keepNext` binding to the first bullet. If you re-introduce a
keep-with-next chain longer than a page, Word drops into a state where it stops
honoring **subsequent** `keepNext` too, and later short jobs (Solavei, Piraeus) start
splitting. Keep short jobs' blocks chained (they fit); never chain a full-page block.

## Verified environment notes

- Python here has working wheels; `python-docx` is installed. PDF export uses the
  installed Word (COM `Word.Application`, `ExportAsFixedFormat(path, 17)`).
- The `career` folder is **not** a git repo — no commit step; just leave the tailored
  files under `applications\<slug>\`.
- If a `~$…docx` lock file lingers, it's a Word temp handle; close Word / stop the
  process before regenerating.
