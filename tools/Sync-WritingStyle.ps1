<#
Installs the writing rules from Google Drive into the copilot repo's global-instructions
folder, which is junctioned to ~/.copilot/instructions and loaded by Copilot CLI every
session (glob: $HOME/.copilot/instructions/**/*.instructions.md).

Copies rather than links because G:\My Drive is not present on every machine (the Cloud PC
has no Google Drive mount), and a broken link means the rules silently stop applying.
Re-run this after editing the Google Drive copy to resync.
#>
[CmdletBinding()]
param(
    [string]$Source = 'G:\My Drive\ai\anti-ai-writing-style.md',
    [string]$Dest = 'C:\Files\Dev\main\copilot\global-instructions\writing-style.instructions.md'
)

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Writing-style source not found: $Source. Mount Google Drive or pass -Source with the canonical file path."
}

$body = Get-Content -LiteralPath $Source -Raw

# The applyTo frontmatter must stay on line 1 or VS Code will not auto-load the rules.
$header = @'
---
applyTo: '**'
description: "@jimb's writing rules. Govern every response, commit message, PR, report, comment, and doc. Always in effect."
---

<!--
  SOURCE OF TRUTH: "G:\My Drive\ai\anti-ai-writing-style.md" (@jimb's own file).
  This is a synced copy. Edit the Google Drive original, then re-run
  copilot\tools\Sync-WritingStyle.ps1 to refresh this file, commit, and push.
  Copied rather than symlinked because G:\ is not mounted on every machine.
-->

# Writing style (applies to every response)

These are @jimb's writing rules. They apply to **everything I write to him or for him**:
chat replies, commit messages, PR descriptions and comments, work item text, HTML and
markdown reports, code comments, and documentation.

## How this interacts with the other instruction files

- These rules govern **how** I write. `personal.instructions.md` governs **what** I do
  (workflow, tooling, review policy, time zones, HTML preference). When both apply, follow
  both: a dark/light HTML report is still required, and it is written in this voice.
- On a direct conflict, accuracy wins. Rule 0 in the file below already says so.

## Local exemptions (do not "fix" these)

The banned-vocabulary list in section 4A contains words that are also **literal technical
identifiers** in this work. Renaming a real API is a factual error, which rule 0 ranks above
style. So these stay as-is when naming the actual thing:

- `OPTIMIZE` / `VACUUM` (Delta commands), `optimizeWrite`, `optimize_write_threshold`,
  `spark.sql.*` keys, `spark.native.enabled`
- Azure and Fabric product terms where that is the real name (for example
  "Native Execution Engine", "autoscale")
- Quoted reviewer comments, error messages, log output, commit messages already pushed,
  and any string being copied verbatim

The exemption covers **naming the thing**. It does not license the word as prose: write
"the write got faster", not "we optimized the write".

---

'@

$out = $header + $body
# LF endings, no BOM, matching the rest of the instructions folder.
$out = $out -replace "`r`n", "`n"
[IO.File]::WriteAllText($Dest, $out, (New-Object Text.UTF8Encoding $false))

$srcLines = ($body -split "`n").Count
$dstLines = ($out -split "`n").Count
Write-Host "source : $Source ($($body.Length) chars, $srcLines lines)"
Write-Host "dest   : $Dest ($($out.Length) chars, $dstLines lines)"

# Prove the body survived the copy byte for byte.
$written = [IO.File]::ReadAllText($Dest)
$bodyLf = $body -replace "`r`n", "`n"
if ($written.EndsWith($bodyLf)) {
    Write-Host 'verify : OK - rules copied verbatim'
}
else {
    throw 'verify FAILED - copied body does not match source'
}
