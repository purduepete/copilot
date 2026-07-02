---
name: skill-authoring
description: >-
  The end-to-end checklist for creating (or removing) one of @jimb's personal
  Copilot CLI skills — scaffold the SKILL.md, junction it via Install-Skills.ps1,
  commit/push to the copilot repo, store a memory, AND keep the Copilot Reference
  Hub's "My skills" catalog (instructions.html #sk-catalog) in sync. Updating the
  hub is a REQUIRED step whenever a skill is added or removed. WHEN: "create a
  skill", "add a new skill", "author a skill", "make a new skill", "new copilot
  skill", "turn this into a skill", "register a skill", "remove/delete a skill".
argument-hint: The skill name and what it should do / trigger on
---

# Authoring a personal skill

All of @jimb's skills live in the **copilot** repo at
`C:\Files\Dev\main\copilot\skills\<name>\SKILL.md` and are junctioned into
`~/.copilot/skills` (GitHub Copilot CLI). Follow every step below — **do not stop after writing the
SKILL.md.** Updating the Reference Hub catalog (step 5) is mandatory.

## 1. Scaffold the skill folder

```powershell
New-Item -ItemType Directory -Force -Path C:\Files\Dev\main\copilot\skills\<name> | Out-Null
```

Create `C:\Files\Dev\main\copilot\skills\<name>\SKILL.md` with this frontmatter,
then a markdown body (verified PowerShell snippets, real absolute paths):

```markdown
---
name: <name>
description: >-
  <one or two sentences on what it does> WHEN: "<trigger phrase>", "<trigger
  phrase>", "<trigger phrase>".
argument-hint: <optional one-liner>
---

# <Title>

<body…>
```

- Put the trigger phrases after `WHEN:` in the `description` — that's what Copilot
  matches on. Be generous and specific with phrasings.
- Keep skills small and judgment-focused; reference scripts by absolute path rather
  than duplicating long logic.

## 2. Junction it into the skills folder

```powershell
pwsh -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
```

Idempotent and self-healing — it links any new folders and re-points stale ones.
(Equivalent manual one-off: `New-Item -ItemType Junction -Path
"$env:USERPROFILE\.copilot\skills\<name>" -Target
"C:\Files\Dev\main\copilot\skills\<name>"`.)

## 3. Commit & push to the copilot repo

```powershell
cd C:\Files\Dev\main\copilot
git add skills/<name>
git commit -m "Add <name> skill"
git push origin HEAD
```

## 4. Store a memory

Use `store_memory` (scope: user) recording the new skill's name, purpose, and that
it lives in `C:\Files\Dev\main\copilot\skills\<name>` — so future sessions know it
exists.

## 5. Update the Copilot Reference Hub (REQUIRED)

The hub at `C:\Files\Dev\main\copilot\instructions.html` lists every skill in its
**"My skills"** table (`<h4 id="sk-catalog">`). Add a row for the new skill:

```html
<tr><td><code><name></code></td><td><em>"<a representative trigger phrase>"</em></td></tr>
```

- The catalog `<table class="skills">` is sorted **alphabetically by skill name** —
  insert the new row in its correct alphabetical position (do NOT append to the
  bottom).
- The skill-name column must not wrap: this is handled by the CSS rule
  `table.skills td:first-child { white-space: nowrap; }`, so keep the
  `class="skills"` on the table and the name in a `<td><code>…</code></td>` cell.
- When **removing** a skill, delete its row instead.
- Validate before committing — every nav `href="#id"` must still resolve and tags
  must balance:

```powershell
$h = Get-Content C:\Files\Dev\main\copilot\instructions.html -Raw
"table: $(([regex]::Matches($h,'<table')).Count)/$(([regex]::Matches($h,'</table>')).Count)"
```

- Commit the hub change (can be the same push as step 3):

```powershell
cd C:\Files\Dev\main\copilot
git add instructions.html
git commit -m "Reference Hub: add <name> to skills catalog"
git push origin HEAD
```

See the **copilot-reference-hub** skill for the hub's full structure and editing
conventions.

## 6. Activate

Tell the user to run `/restart` so Copilot loads the new skill (skills are read at
startup), and — on their **other 2 machines**, after `git pull` in the copilot
repo — to run `Install-Skills.ps1` once.

## Checklist

- [ ] SKILL.md created with `name` + `WHEN:` triggers
- [ ] Junctioned via Install-Skills.ps1
- [ ] Committed + pushed to the copilot repo
- [ ] Memory stored
- [ ] **Reference Hub `#sk-catalog` row added/removed**
- [ ] Told user to `/restart`
