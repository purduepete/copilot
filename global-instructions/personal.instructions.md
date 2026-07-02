# Personal global Copilot instructions (@purduepete)

Shared across **all** repositories and machines. The canonical copy lives in the
`copilot` repo at `global-instructions\personal.instructions.md` and is linked into
`%USERPROFILE%\.copilot\instructions\` by `skills\Install-Skills.ps1` (directory
junction — no admin required). Edit here, commit/push, then `git pull` on other
machines to sync. Repo-specific rules still belong in each repo's
`.github/copilot-instructions.md`, which take precedence for that repo.

## Preferences

- When cloning source/solution repos for analysis, clone them under
  `C:\Files\Dev\msft` (not a temp directory). On the work computer, new repos are
  most often written to `C:\Files\Dev\msft`.
- Treat the WorkLog category alias `dev` as `development`.

## Communication style

- **Be concise; lead with the answer, minimal preamble.**
- **Plan first, then implement.** I don't do well when work jumps straight to
  implementation — lay out a short plan and let me confirm before you build.
- **I'm a visual person — dense text is not great.** HTML is by far the best way to
  share information; prefer it for anything substantial.
- **For any HTML you produce, include both a dark and a light theme** (with a way to
  toggle / respect the system preference).

## Commits

Include the trailer on commits:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
