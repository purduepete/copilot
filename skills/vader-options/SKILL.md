---
name: vader-options
description: >-
  Turn a weekly Multiplier/Substack options-newsletter article (fetched with
  @jimb's own subscriber session cookie) into a personal, local HTML weekly
  calendar dashboard of covered-call/cash-secured-put trade picks, grouped by
  risk tier and day, in @jimb's webapp-style design system. WHEN: "vader
  options calendar", "build my weekly options calendar", "update the options
  calendar", "pull this week's multiplier newsletter", "new vader options
  picks", "weekly trade calendar", "options newsletter to html", "refresh the
  covered call calendar".
argument-hint: <substack article URL>
---

# Vader Options — weekly trade-calendar dashboard

Turns a paywalled weekly article from **The Multiplier** (Substack, VADER
screening tool) into a personal, local HTML dashboard: a Monday–Friday
calendar of covered-call / cash-secured-put picks, grouped by risk tier, with
day-specific trading rules. Built once in session `ae15e7af-...` and meant to
repeat weekly whenever @jimb pastes a new article URL.

## Access model (read this first)

- @jimb has his own **paid** subscription to `themultiplier.substack.com`.
  `web_fetch` alone only returns the free preview — the paywalled body isn't
  in the anonymous HTML at all.
- The Substack session cookie value is stored at
  `C:\Files\Dev\main\config\substack\substack_config.json` (key `"vader"`). Read
  it from there first — do NOT ask @jimb to paste the cookie again unless
  that file is missing or the stored value stops working (401/redirect to
  login), in which case ask him to re-export a fresh one from browser
  DevTools → Application → Cookies and update that file.
- **That config file must never be committed.** It lives in its own git repo
  (`C:\Files\Dev\main\config`, remote `github.com/purduepete/config`) and is
  covered by a   `.gitignore` entry (`substack/substack_config.json`) — verify
  that entry is still present (`git check-ignore -v
  substack\substack_config.json` from that repo root) before ever running `git
  add`/`git commit` there. If the `.gitignore` entry is ever missing, add it
  before touching git, and never `git add -A`/`git add .` in that repo
  without checking `git status` first for the `vader/` folder.
- Fetch the full page with `Invoke-WebRequest -Headers @{Cookie="substack.sid=<value>"}`
  (or `curl.exe -H "Cookie: ..."`), save to a temp file, then grep the raw
  HTML for the section headers and list items to extract data. Do NOT use
  `web_fetch` for the authenticated pull — it can't carry cookies.
- Treat the cookie value as equivalent to a password: don't print it in chat
  output beyond what's needed to construct the request, and don't copy it
  anywhere besides that one config file.
- **Copyright:** only extract structured facts (ticker, put/call, strike,
  expiry, DTE, delta, annualized %, premium $, collateral $, risk tag) and
  short paraphrases of the day-by-day trading rules. Never reproduce the
  article's original prose, headers, or editorial wording verbatim into the
  HTML file or the chat.

## What the article generally contains

- 3 macro notes (index/VIX/rate moves) plus one or two "key event" callouts
  for the week (e.g. a CPI print, a big-name earnings report).
- ~15 option trade picks, each with a **risk tag**: Conservative / Balanced /
  Aggressive, tagged to a **day-of-week execution rule**, e.g.:
  - a Monday/Tuesday window for event-insensitive names (place any day in
    that window — don't invent a rigid one-per-day split if the source
    doesn't specify one; ask @jimb rather than guessing when a header
    genuinely groups multiple days together),
  - a Wednesday-after-CPI conditional batch (only fires if the print lands at
    or below the stated threshold),
  - Thursday as a "no new risk, wait for confirmation" day tied to
    earnings/PPI/jobless-claims,
  - Friday reserved for high-earnings-risk sector names (e.g. chips/networking)
    once the risk events have cleared.
- **Read the section headers carefully** before assigning trades to days —
  the article's own headers state the day grouping explicitly (e.g. "Monday
  and Tuesday: ...", "Wednesday Afternoon: ..."). Don't guess; grep the raw
  HTML for `<h3` / heading text near each trade list to confirm.

## Build the dashboard

1. Load the `webapp-style` skill for the design tokens (squared corners,
   indigo/violet accent gradient, dark-default + light theme + toggle,
   Lucide-style stroke SVG icons, Inter font).
2. Single self-contained `weekly-options-calendar.html`, no build step, saved
   to `C:\Users\JimBrown\OneDrive\Trading\Vader\weekly-options-calendar.html`
   (the standing output location — personal use only; overwrite it each week
   rather than creating dated copies unless @jimb asks to keep history). Include a "Week of / generated <timestamp>, local time" stamp
   in the header so stale data is obvious.
3. Layout: a Mon–Fri grid of day cards. Use **CSS Grid `subgrid`** so every
   day's rule/event box and trade list start at the *same* shared row across
   all 5 columns, regardless of how long that day's rule text or event
   banner is — reference implementation:
   `weekly-options-calendar.html`'s `.week-grid` / `.day-card { display:
   grid; grid-template-rows: subgrid; }` plus JS that sets
   `grid.style.gridTemplateRows` and per-child `style="grid-row:N"`.
   - Rows 1–3 = day head / optional event banner / rule text (shared height).
   - Row 4 = a single `.tickets` flex column holding the risk-group headings
     + trade tickets for that day. Do **not** reserve fixed row-slots per
     named risk group (conservative/balanced/aggressive) — that caused
     visible gaps on days missing a group. Groups just stack in order,
     starting at the same row 4 for every day.
4. Within each day's ticket list: group trades under **Conservative /
   Balanced / Aggressive** headings (in that order), and within each group,
   **puts before calls**, sorted by **annualized % descending**. No
   per-ticket risk-tag pill needed once the group heading exists (redundant).
5. Footer: educational-only disclaimer + "personal use only, not for
   redistribution" note.
6. Open the file in the browser (`Start-Process <path>`) after every
   meaningful change so @jimb can eyeball it before iterating further.

## Weekly repeat workflow

When @jimb pastes a new article URL:

1. `web_fetch` it first — grab whatever's in the free preview for context.
2. Ask for the session cookie value if the paywalled body is needed (most
   weeks it will be).
3. Fetch authenticated, extract the macro notes, key events, and the trade
   table (ticker/strike/expiry/delta/ann%/premium/collateral/risk tag) plus
   the day-of-week rules, respecting the article's own day-grouping headers.
4. Rebuild `weekly-options-calendar.html` with the new week's data, following
   the layout conventions above.
5. Open it, and iterate on any feedback before considering the week done.

## Independent review

Per @jimb's personal instructions, a plan for building/updating this
dashboard should get a quick independent-model sanity check (different model
family than the primary) before finalizing, since it involves fetching
paywalled content under his subscription — mainly to reconfirm the
copyright/personal-use guardrails and flag any technical gaps (e.g. embedding
the cookie in output). It is not a database-altering change, so this is a
light-touch check, not a mandatory gate.
