---
name: worklog-profile
description: >-
  Show or set this machine's default WorkLog profile (work, personal, or any
  other), and choose per-profile whether daily start/end-of-day bounds apply.
  Switches the default so future worklog commands log under the chosen profile,
  and toggles/queries that profile's workday-bounds constraint. WHEN: "set
  profile <x>", "change profile to personal", "switch to work profile", "set my
  worklog profile", "what profile am I on", "which worklog profile is active",
  "does this profile use start/end day", "make this profile ignore start/end
  bounds", "turn off daily bounds for <profile>", "use the personal log by
  default", "change my default profile".
argument-hint: set profile personal | set profile work | what profile am I on
---

# WorkLog profile

Each machine has a **default WorkLog profile** (`work`, `personal`, or any other
name) that decides where time-tracking entries land unless a command overrides it
with `-Profile`. Each profile also carries a **"daily start/end bounds" flag** that
controls whether the work-day constraints apply to it. Both are managed through the
one WorkLog entry point:

```
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile [name] [-Bounds on|off|default]
```

## Daily start/end bounds — what the flag means

When a profile **enforces bounds** (`on`), the work-day constraints apply: nothing
can be logged before that day's `startday` marker exists, and tasks must fall inside
the `startday`/`endday` window. When a profile **does not** (`off`), those
constraints are skipped entirely — you can log any time without markers (this is how
`personal` behaves by default).

The flag is stored **per profile, server-side** (cloud DB), so it's consistent on all
your machines. Resolution when never set explicitly (back-compat default):
**`personal` = off, every other profile = on.**

## Show the current profile + its bounds

"What profile am I on?" / "does this profile use start/end day?"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile
# -> Current profile: personal
# -> Daily start/end bounds: not enforced (default)
```

`(default)` means the flag was never set explicitly (using the personal-off /
others-on default); `(explicit)` means it was set with `-Bounds`.

## Set / change the profile

"Set profile personal" / "change profile to work" / "switch to the personal log"

```powershell
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile personal
# -> Default profile for this machine set to 'personal'.
```

**When setting a profile, ASK whether daily start/end bounds will be used** (unless
the user already said). Then persist their answer for that profile:

```powershell
# enforce daily bounds for the named profile
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile work -Bounds on
# don't enforce (no startday/endday needed, log any time)
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile side -Bounds off
# revert to the built-in default for that profile
pwsh -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 profile work -Bounds default
```

- `-Bounds` accepts **`on`** (enforce), **`off`** (don't), **`default`** (clear the
  explicit flag and use the back-compat default).
- With a name (`profile work -Bounds on`) it targets that profile; with no name
  (`profile -Bounds off`) it targets the **active** profile.
- Setting `-Bounds` does **not** by itself change the machine default — pass the
  name too if you also want to switch.

## Rules

1. **Confirm changes back** — after switching, state the new default; after a
   `-Bounds` change, state the profile and its new enforcement.
2. **Ask about bounds when setting a new/unfamiliar profile.** For a profile that
   already has a known setting, don't re-ask unless the user brings it up.
3. **Default names are `work` and `personal`,** but any name is valid (multiple
   profiles are supported). Normalize obvious phrasings ("the personal log") to the
   bare name.
4. **Bounds reminder.** Enforcing bounds means logging requires that day's `startday`
   marker and tasks must fall inside the work-day window. Turning bounds off removes
   those constraints (like `personal`).
5. Don't pass `-Profile` to the `profile` verb — the profile name is a positional
   argument (`profile personal`), not a `-Profile` switch. Use `-Bounds` for the flag.

