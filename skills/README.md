# Copilot CLI Skills

Personal [GitHub Copilot CLI](https://github.com/github/copilot-cli) skills, kept
under version control here so they are backed up and shared across machines.

The Copilot CLI loads skills from `%USERPROFILE%\.copilot\skills`. Rather than copy
files there, each skill folder in this repo is **linked** into that location with a
Windows **directory junction**. Edits made in the repo are picked up live by the CLI
(no copy step), and `git commit && git push` is all that's needed to sync.

```
%USERPROFILE%\.copilot\skills\worklog   ──(junction)──►   <repo>\skills\worklog
                              \calendar  ──(junction)──►   <repo>\skills\calendar
                              ...
```

## Skills in this folder

| Skill                | Purpose                                                            |
| -------------------- | ----------------------------------------------------------------- |
| `worklog`            | Track time via the local WorkLog CLI (start/stop/edit/notes).     |
| `worklog-highlights` | Generate a specific <=2-line daily highlights / day recap.        |
| `calendar`           | Read the local Outlook calendar (COM, no Graph); list meetings.   |
| `ado-worklist`       | Regenerate the "Open Azure DevOps Work Items" dashboard.          |

> **Note:** These skills use absolute paths (e.g. `C:\Files\Dev\main\copilot\worklog`).
> Clone this repo to the **same path** on every machine, or update the paths inside
> each `SKILL.md`.

## Set up on a new machine

1. Clone (or pull) this repo to the same location, e.g. `C:\Files\Dev\main\copilot`.
2. Run the installer to create the junctions:

   ```powershell
   pwsh -File C:\Files\Dev\main\copilot\skills\Install-Skills.ps1
   ```

   It creates one junction per skill folder under `%USERPROFILE%\.copilot\skills`,
   skipping any that already exist. **Junctions do not require admin rights.**

3. Start a new Copilot CLI session — the skills load at startup.

## Link creation (what `Install-Skills.ps1` does)

A directory **junction** is a filesystem link that makes one folder transparently
resolve to another on the same volume. We use junctions (not symlinks) because they
work **without** admin rights or Developer Mode.

### PowerShell (preferred, no admin)

```powershell
# New-Item -ItemType Junction -Path <link to create> -Target <existing folder>
New-Item -ItemType Junction `
  -Path   "$env:USERPROFILE\.copilot\skills\worklog" `
  -Target "C:\Files\Dev\main\copilot\skills\worklog"
```

Loop over every skill folder in the repo:

```powershell
$repo   = 'C:\Files\Dev\main\copilot\skills'
$target = "$env:USERPROFILE\.copilot\skills"
New-Item -ItemType Directory -Path $target -Force | Out-Null
Get-ChildItem $repo -Directory | ForEach-Object {
  $link = Join-Path $target $_.Name
  if (-not (Test-Path $link)) {
    New-Item -ItemType Junction -Path $link -Target $_.FullName | Out-Null
  }
}
```

### cmd.exe equivalent

```cmd
mklink /J "%USERPROFILE%\.copilot\skills\worklog" "C:\Files\Dev\main\copilot\skills\worklog"
```

`/J` = directory junction. (`/D` would make a directory **symlink**, which needs
admin or Developer Mode — avoid it here.)

### Verify a link

```powershell
Get-ChildItem "$env:USERPROFILE\.copilot\skills" -Force |
  Select-Object Name, LinkType, Target
# LinkType should be 'Junction' and Target should point into this repo.
```

### Remove a link (does NOT delete the repo files)

```powershell
# Safe: removing a junction deletes only the link, not its target contents.
(Get-Item "$env:USERPROFILE\.copilot\skills\worklog").Delete()
# or:
cmd /c rmdir "%USERPROFILE%\.copilot\skills\worklog"
```

> Do **not** use `Remove-Item -Recurse` on a junction on older PowerShell versions —
> it could follow the link and delete target contents. Use `.Delete()` or `rmdir`
> on the junction itself.

## Add a new skill

1. Create `skills\<name>\SKILL.md` in this repo.
2. Run `Install-Skills.ps1` (or create the single junction with the snippet above).
3. Commit & push.

## Why junctions over symlinks or copies?

- **Junctions**: no admin/Developer Mode required; live edits; one source of truth.
- **Symlinks** (`mklink /D`, `New-Item -ItemType SymbolicLink`): require admin or
  Developer Mode on Windows.
- **Copies**: drift between the repo and `~/.copilot/skills`; easy to forget to sync.
