---
name: worklog-profile
description: >-
  Show or set this machine's default WorkLog profile (work vs personal) via the
  cloud WorkLog CLI. Reads the active profile, or switches it so future worklog
  commands log under the chosen profile by default. WHEN: "set profile <x>",
  "change profile to personal", "switch to work profile", "set my worklog
  profile", "what profile am I on", "which worklog profile is active", "use the
  personal log by default", "change my default profile".
argument-hint: set profile personal | set profile work | what profile am I on
---

# WorkLog profile

Each machine has a **default WorkLog profile** (`work` or `personal`) that decides
where time-tracking entries land unless a command overrides it with `-Profile`.
This skill just shows or sets that machine default through the one WorkLog entry
point:

```
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile [name]
```

## Show the current profile

"What profile am I on?" / "which worklog profile is active?"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile
# -> Current profile: personal
```

## Set / change the profile

"Set profile personal" / "change profile to work" / "switch to the personal log"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile personal
# -> Default profile for this machine set to 'personal'.
```

Valid names are **`work`** and **`personal`** only. Normalize obvious phrasings
("the personal log", "my work profile") to the bare name. If the user names
anything else, ask which of the two they mean rather than guessing.

## Rules

1. **Confirm the change back** — after setting, state the new default and that
   future commands use it unless overridden with `-Profile <other>`.
2. **This is the machine default, not a per-command flag.** It persists in the
   cloud WorkLog state for this machine. A one-off `-Profile work` on a single
   `start`/`add`/etc. does **not** change the default — use this skill for that.
3. **Boundary reminder.** The `work` profile enforces start/end-of-day markers and
   the work-day window; the `personal` profile has no concept of start/end day. So
   switching to `work` means logging now requires that day's `startday` marker and
   tasks must fall inside the work-day window.
4. Don't pass `-Profile` to the `profile` verb — the profile name is a positional
   argument (`profile personal`), not a `-Profile` switch.
