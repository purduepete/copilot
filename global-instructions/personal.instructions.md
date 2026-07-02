# Personal global Copilot instructions (@purduepete)

Shared across **all** repositories and machines. The canonical copy lives in the
`copilot` repo at `global-instructions\personal.instructions.md` and is linked into
`%USERPROFILE%\.copilot\instructions\` by `skills\Install-Skills.ps1` (directory
junction — no admin required). Edit here, commit/push, then `git pull` on other
machines to sync. Repo-specific rules still belong in each repo's
`.github/copilot-instructions.md`, which take precedence for that repo.

## Preferences

- When cloning source/solution repos for analysis, clone them under
  `C:\Files\Dev\msft` (not a temp directory).
- Treat the WorkLog category alias `dev` as `development`.

## Commits

Include the trailer on commits:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
