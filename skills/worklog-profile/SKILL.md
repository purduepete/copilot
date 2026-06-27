---
name: worklog-profile
description: >-
  Show or set this machine's default WorkLog profile (work, personal, or any
  other), and turn each profile's "time bound" (daily start/end-of-day
  constraint) on or off. WHEN: "set profile <x>", "get profile", "set time bound
  on", "set time bound off", "get time bound", "change profile to personal",
  "switch to work profile", "what profile am I on", "does this profile use
  time bounds", "turn time bounds off for <profile>", "use the personal log by
  default".
argument-hint: set profile <x> | get profile | set time bound on|off | get time bound
---

# WorkLog profile

Each machine has a **default WorkLog profile** (`work`, `personal`, or any other
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
can log any time without markers (this is how `personal` behaves by default).

The flag is stored **per profile, server-side** (cloud DB), so it's consistent on all
your machines. Resolution when never set explicitly: **OFF for every profile** — opt a
profile into the work-day constraints with `set time bound on`.

## Show the current profile + its time bound

"Get profile" / "what profile am I on?" / "get time bound"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile
# -> Current profile: personal
# -> Daily start/end bounds: not enforced (default)
```

`(default)` means the time bound was never set explicitly (defaults to OFF for every
profile); `(explicit)` means it was set with `-Bounds`.

## Set / change the profile

"Set profile personal" / "change profile to work" / "switch to the personal log"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile personal
# -> Default profile for this machine set to 'personal'.
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

## Rules

1. **Confirm changes back** — after switching, state the new default; after a time
   bound change, state the profile and its new on/off state.
2. **Ask about the time bound when setting a new/unfamiliar profile.** For a profile
   that already has a known setting, don't re-ask unless the user brings it up.
3. **Default names are `work` and `personal`,** but any name is valid (multiple
   profiles are supported). Normalize obvious phrasings ("the personal log") to the
   bare name.
4. **Time-bound reminder.** Time bound ON means logging requires that day's `startday`
   marker and tasks must fall inside the work-day window. Turning it OFF removes those
   constraints (like `personal`).
5. Don't pass `-Profile` to the `profile` verb — the profile name is a positional
   argument (`profile personal`), not a `-Profile` switch. Use `-Bounds` for the time
   bound.

