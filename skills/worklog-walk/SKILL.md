---
name: worklog-walk
description: >-
  Log @jimb's daily walk to WorkLog with the fixed category 'personal' and
  project 'fitness' (HOME profile only), always recording the distance walked in
  the accomplishment — ask for the mileage if it wasn't given. WHEN: "log my
  daily walk", "log my walk", "daily walk", "I went for a walk", "log a walk",
  "add my walk", "went walking", "record my walk".
argument-hint: Optionally mileage + time range (e.g. "log my daily walk 2.3 miles 07:00-07:45")
---

# WorkLog Daily Walk

Logs @jimb's **daily walk** as a WorkLog entry with fixed fields:

- **Category:** `personal`
- **Project:** `fitness`
- **Profile:** `home` (this is a home-profile activity only — always pass `-Profile home`)

The **accomplishment must state the mileage** (e.g. `Walked 2.3 miles.`). This is a
refinement of the `worklog` skill — prefer it whenever the user asks to log a walk.

## Rules

1. **Mileage is required.** If the user didn't give a distance, **ask** for it (in
   miles) before logging — don't guess or log without it. Put it in the accomplishment
   as `Walked <n> miles.` (or `Walked <n> mile.` for exactly 1).
2. **Always `-Profile home`**, regardless of the machine's default profile.
3. **Fixed fields:** category `personal`, project `fitness` — do not infer or override.
4. **Title:** keep it short, e.g. `Daily walk` (put the distance detail in the
   accomplishment, per the item-naming convention).
5. **Time:** if the user gives a range, use it. If they give only an end ("ending at
   HH:MM"), chain the start from the end of the last logged home entry today
   (`log -Days 1 -Profile home`). If no time at all, either log it as a running task
   with `start` or ask for the range — prefer `add` with an explicit range when known.

## Steps

1. **Get the mileage.** If not supplied, ask: "How far did you walk (miles)?"

2. **Log it** (completed entry with a known range):

   ```powershell
   pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 add "Daily walk" `
     -Start "2026-07-02 07:00" -End "2026-07-02 07:45" `
     -Category personal -Project fitness -Profile home `
     -Accomplishment "Walked 2.3 miles."
   ```

   Or, to start it as the **currently running** task (stop it later):

   ```powershell
   pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 start "Daily walk" `
     -Category personal -Project fitness -Profile home
   # later:
   pwsh -NoProfile -File C:\Files\Dev\main\worklog_web\cli\wl.ps1 stop "Walked 2.3 miles." -Profile home
   ```

3. **Confirm** the logged entry (title, time, and mileage) and remind the user the
   home dashboard reflects it on refresh.
