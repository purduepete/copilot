---
name: worklog-profile
description: >-
  Show, set, list, create, rename, or delete WorkLog profiles (work, home, or
  any other), and turn each profile's "time bound" (daily start/end-of-day
  constraint) on or off. Deleting a profile removes ALL its data and is strictly
  guarded. WHEN: "set profile <x>", "get profile", "list profiles", "create a
  profile", "new profile <x>", "rename profile <x> to <y>", "delete profile <x>",
  "remove profile <x>", "set time bound on", "set time bound off", "get time
  bound", "change profile to home", "switch to work profile", "what profile am I
  on", "does this profile use time bounds", "turn time bounds off for <profile>",
  "use the home log by default".
argument-hint: set <x> | get | -List | <x> -Create | <x> -Rename <y> | <x> -Delete [-Yes] | -Bounds on|off
---

# WorkLog profile

Each machine has a **default WorkLog profile** (`work`, `home`, or any other
name) that decides where time-tracking entries land unless a command overrides it
with `-Profile`. Each profile also carries a **time bound** flag — whether the daily
start/end-of-day constraints apply to it. Both are managed through the one WorkLog
entry point:

```
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile [name] [-Bounds on|off|default]
```

## Command vocabulary (what the user says -> what to run)

| User says | Action |
|---|---|
| **"set profile `<x>`"** | `wl.ps1 profile <x>` — make `<x>` this machine's default |
| **"get profile"** / "what profile am I on" | `wl.ps1 profile` — show active profile + its time bound |
| **"set time bound on"** / "off" | `wl.ps1 profile -Bounds on` / `off` — toggle the **active** profile (add a name to target another: `profile <x> -Bounds off`) |
| **"get time bound"** | `wl.ps1 profile` — read the active profile's time bound line |

`-Bounds default` clears the explicit flag and reverts to the built-in default.

## Time bound — what it means

When a profile's time bound is **on**, the work-day constraints apply: nothing can be
logged before that day's `startday` marker exists, and tasks must fall inside the
`startday`/`endday` window. When **off**, those constraints are skipped entirely — you
can log any time without markers (this is how `home` behaves by default).

The flag is stored **per profile, server-side** (cloud DB), so it's consistent on all
your machines. Resolution when never set explicitly: **OFF for every profile** — opt a
profile into the work-day constraints with `set time bound on`.

## Show the current profile + its time bound

"Get profile" / "what profile am I on?" / "get time bound"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile
# -> Current profile: home
# -> Daily start/end bounds: not enforced (default)
```

`(default)` means the time bound was never set explicitly (defaults to OFF for every
profile); `(explicit)` means it was set with `-Bounds`.

## Set / change the profile

"Set profile home" / "change profile to work" / "switch to the home log"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile home
# -> Default profile for this machine set to 'home'.
```

**When setting a profile, ASK whether its time bound will be on or off** (unless the
user already said). Then persist their answer for that profile:

```powershell
# time bound ON for the named profile (requires startday/endday)
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile work -Bounds on
# time bound OFF (no startday/endday needed, log any time)
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile side -Bounds off
# revert to the built-in default for that profile
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile work -Bounds default
```

- `-Bounds` accepts **`on`** (enforce), **`off`** (don't), **`default`** (clear the
  explicit flag and use the back-compat default).
- "Set time bound on/off" with no name targets the **active** profile
  (`profile -Bounds on`); add a name to target another (`profile work -Bounds on`).
- Setting `-Bounds` does **not** by itself change the machine default — pass the
  name too if you also want to switch.

## Manage profiles (list / create / rename / delete)

All profile data lives server-side (cloud DB). These operate on the **named**
profile (positional or `-Profile`), independent of the machine default.

```powershell
# List every profile with row counts (* = this machine's default)
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile -List

# Create a new, empty profile (optional -Label / -Org for ADO linking)
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile side -Create
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile side -Create -Label 'Side gig'

# Rename a profile — MIGRATES all of its data (sessions, task-notes, notes,
# commentary) to the new name in one transaction. Fails if the new name exists.
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile side -Rename hobby

# Delete a profile AND ALL its data — strictly guarded (see below)
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile hobby -Delete        # dry run: shows what WOULD be deleted, deletes nothing
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile hobby -Delete -Yes   # actually delete it
```

### Delete guardrails (all enforced — do not try to bypass)

1. **Two-step by default.** `-Delete` without `-Yes` is a **dry run**: it prints the
   exact row counts that would be removed and deletes nothing. Only `-Delete -Yes`
   actually deletes. Always show the user the dry-run counts and get explicit
   go-ahead before re-running with `-Yes`.
2. **Server requires an exact-name confirmation** (`confirm == <name>`); a bare
   delete call is always treated as a preview.
3. **Cannot delete the machine's active/default profile** — switch to another
   profile first (`profile <other>`), then delete.
4. **Cannot delete the last remaining profile** (the server refuses).
5. Deletion is **permanent and cascades** to every session, task-note, standalone
   note, and commentary entry for that profile. Treat it like `rm -rf`.

### Naming
Profile names must be URL-safe: letters, numbers, hyphen or underscore (no spaces),
starting with a letter or number, max 64 chars.

## Rules

1. **Confirm changes back** — after switching, state the new default; after a time
   bound change, state the profile and its new on/off state.
2. **Ask about the time bound when setting a new/unfamiliar profile.** For a profile
   that already has a known setting, don't re-ask unless the user brings it up.
3. **Default names are `work` and `home`,** but any name is valid (multiple
   profiles are supported). Normalize obvious phrasings ("the home log") to the
   bare name.
4. **Time-bound reminder.** Time bound ON means logging requires that day's `startday`
   marker and tasks must fall inside the work-day window. Turning it OFF removes those
   constraints (like `home`).
5. Don't pass `-Profile` to the `profile` verb — the profile name is a positional
   argument (`profile home`), not a `-Profile` switch. Use `-Bounds` for the time
   bound.

