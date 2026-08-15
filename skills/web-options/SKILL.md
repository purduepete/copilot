---
name: web-options
description: >-
  Build and extend @jimb's personal options-trading web dashboards. Two
  capabilities today: (1) turn a weekly Multiplier/Substack options-newsletter
  article (fetched with his own subscriber session cookie) into a personal,
  local HTML weekly calendar dashboard of covered-call/cash-secured-put trade
  picks, grouped by risk tier and day; (2) a live HTML dashboard backed by a
  local Flask server reading VADER Telegram signals from the webportfolio
  database, developed in the `weboptions` repo. Named generically since the
  dashboard/server code isn't Vader-specific, even though today's only data
  sources are. WHEN: "vader options calendar", "build my weekly options
  calendar", "update the options calendar", "pull this week's multiplier
  newsletter", "new vader options picks", "weekly trade calendar", "options
  newsletter to html", "refresh the covered call calendar", "telegram signals
  dashboard", "start the vader telegram server", "live vader telegram
  calendar", "weboptions", "web options dashboard".
argument-hint: <substack article URL>
---

# Web Options — options-trading dashboards

Two related but independent capabilities, both personal-use HTML dashboards
for options-trading picks. Built starting in session `ae15e7af-...`.
Originally named `vader-options` (renamed here since the code itself is
generic; only the current data sources happen to be VADER/Multiplier).

1. **Weekly Substack calendar** - a static, dated HTML file built from a
   paywalled newsletter article, one file per week.
2. **Live Telegram dashboard** - a small local Flask API + a permanent HTML
   file that queries a live database on every load, developed in the
   `weboptions` GitHub repo (`C:\Files\Dev\main\weboptions`).

## Capability 1: weekly Substack calendar

Turns a paywalled weekly article from **The Multiplier** (Substack, VADER
screening tool) into a personal, local HTML dashboard: a Monday-Friday
calendar of covered-call / cash-secured-put picks, grouped by risk tier, with
day-specific trading rules.

### Access model (read this first)

- @jimb has his own **paid** subscription to `themultiplier.substack.com`.
  `web_fetch` alone only returns the free preview - the paywalled body isn't
  in the anonymous HTML at all.
- The Substack session cookie value is stored at
  `C:\Files\Dev\main\config\substack\substack_config.json` (key `"vader"`). Read
  it from there first - do NOT ask @jimb to paste the cookie again unless
  that file is missing or the stored value stops working (401/redirect to
  login), in which case ask him to re-export a fresh one from browser
  DevTools -> Application -> Cookies and update that file.
- **That config file must never be committed.** It lives in its own git repo
  (`C:\Files\Dev\main\config`, remote `github.com/purduepete/config`) and is
  covered by a `.gitignore` entry (`substack/substack_config.json`) - verify
  that entry is still present (`git check-ignore -v
  substack\substack_config.json` from that repo root) before ever running `git
  add`/`git commit` there. If the `.gitignore` entry is ever missing, add it
  before touching git, and never `git add -A`/`git add .` in that repo
  without checking `git status` first for the `vader/` folder.
- Fetch the full page with `Invoke-WebRequest -Headers @{Cookie="substack.sid=<value>"}`
  (or `curl.exe -H "Cookie: ..."`), save to a temp file, then grep the raw
  HTML for the section headers and list items to extract data. Do NOT use
  `web_fetch` for the authenticated pull - it can't carry cookies.
- Treat the cookie value as equivalent to a password: don't print it in chat
  output beyond what's needed to construct the request, and don't copy it
  anywhere besides that one config file.
- **Copyright:** only extract structured facts (ticker, put/call, strike,
  expiry, DTE, delta, annualized %, premium $, collateral $, risk tag) and
  short paraphrases of the day-by-day trading rules. Never reproduce the
  article's original prose, headers, or editorial wording verbatim into the
  HTML file or the chat.

### What the article generally contains

- 3 macro notes (index/VIX/rate moves) plus one or two "key event" callouts
  for the week (e.g. a CPI print, a big-name earnings report).
- ~15 option trade picks, each with a **risk tag**: Conservative / Balanced /
  Aggressive, tagged to a **day-of-week execution rule**, e.g.:
  - a Monday/Tuesday window for event-insensitive names (place any day in
    that window - don't invent a rigid one-per-day split if the source
    doesn't specify one; ask @jimb rather than guessing when a header
    genuinely groups multiple days together),
  - a Wednesday-after-CPI conditional batch (only fires if the print lands at
    or below the stated threshold),
  - Thursday as a "no new risk, wait for confirmation" day tied to
    earnings/PPI/jobless-claims,
  - Friday reserved for high-earnings-risk sector names (e.g. chips/networking)
    once the risk events have cleared.
- **Read the section headers carefully** before assigning trades to days -
  the article's own headers state the day grouping explicitly (e.g. "Monday
  and Tuesday: ...", "Wednesday Afternoon: ..."). Don't guess; grep the raw
  HTML for `<h3` / heading text near each trade list to confirm.

### Build the dashboard

1. Load the `webapp-style` skill for the design tokens (squared corners,
   indigo/violet accent gradient, dark-default + light theme + toggle,
   Lucide-style stroke SVG icons, Inter font).
2. Single self-contained HTML file, no build step, named
   `weekly-options-calendar-<article-published-date>.html` (e.g.
   `weekly-options-calendar-2026-08-10.html`, using the article's own publish
   date, not a guessed "week of" date) and saved to
   `C:\Users\JimBrown\OneDrive\Trading\Vader\` (the standing output folder -
   personal use only). Create a new dated file each week rather than
   overwriting the prior week's, so the history of past calendars is kept.
   Extract the actual publish date from the fetched page's metadata (look
   for `"datePublished":"..."` or `<meta property="article:published_time"
   content="...">` in the raw HTML) rather than assuming "today" or the
   Monday of the trading week, and convert from UTC to local time per
   @jimb's personal instructions. Show it in the header as "Published <date>"
   plus a separate "Calendar generated <timestamp>, local time" line so it's
   clear which date is the article's and which is when the HTML was built.
   Do not add extra qualifier text after the generated timestamp (e.g. no
   "personal reference only, verify pricing before acting"); keep that line
   to just the date/time.
2b. The Monday-Friday day cards must use the actual calendar dates of the
   week the article covers, computed from that same publish date (e.g. a
   Monday 2026-08-10 publish date means the day cards run Mon Aug 10 through
   Fri Aug 14) -- never guess a following week or an arbitrary date.
2c. No em dashes (\u2014, "&mdash;") anywhere in the generated HTML text
   (headers, rules, notes, meta lines). Use periods, commas, colons,
   semicolons, or parentheses instead, per @jimb's writing-style rules. En
   dashes for date ranges (e.g. "Monday-Friday") are fine; it's the em dash
   used as a clause-separator that's banned.
2d. **All intraday market-event times in the article (data releases,
   earnings, jobs reports, Fed announcements, etc.) are stated in Eastern
   Time.** @jimb is in Pacific Time, so convert every clock time to Pacific
   before showing it (subtract 3 hours during EDT/PDT, which covers most of
   the trading year; check for standard-time overlap around early
   November-early March, where the offset is also 3 hours since both zones
   shift together). Show only the converted Pacific time (e.g. "5:30 AM
   Pacific"); do not also list the Eastern time.
3. Layout: a Mon-Fri grid of day cards. Use **CSS Grid `subgrid`** so every
   day's rule/event box and trade list start at the *same* shared row across
   all 5 columns, regardless of how long that day's rule text or event
   banner is - reference implementation:
   `weekly-options-calendar.html`'s `.week-grid` / `.day-card { display:
   grid; grid-template-rows: subgrid; }` plus JS that sets
   `grid.style.gridTemplateRows` and per-child `style="grid-row:N"`.
   - Rows 1-3 = day head / optional event banner / rule text (shared height).
   - Row 4 = a single `.tickets` flex column holding the risk-group headings
     + trade tickets for that day. Do **not** reserve fixed row-slots per
     named risk group (conservative/balanced/aggressive) - that caused
     visible gaps on days missing a group. Groups just stack in order,
     starting at the same row 4 for every day.
4. Within each day's ticket list: group trades under **Conservative /
   Balanced / Aggressive** headings (in that order), and within each group,
   **puts before calls**, sorted by **annualized % descending**. No
   per-ticket risk-tag pill needed once the group heading exists (redundant).
5. No footer disclaimer text - @jimb asked for it removed; don't re-add it in
   future weeks unless he asks.
6. Open the file in the browser (`Start-Process <path>`) after every
   meaningful change so @jimb can eyeball it before iterating further.

### Weekly repeat workflow

When @jimb pastes a new article URL:

1. `web_fetch` it first - grab whatever's in the free preview for context.
2. Ask for the session cookie value if the paywalled body is needed (most
   weeks it will be).
3. Fetch authenticated, extract the macro notes, key events, and the trade
   table (ticker/strike/expiry/delta/ann%/premium/collateral/risk tag) plus
   the day-of-week rules, respecting the article's own day-grouping headers.
4. Rebuild `weekly-options-calendar.html` with the new week's data, following
   the layout conventions above.
5. Open it, and iterate on any feedback before considering the week done.

### Independent review

Per @jimb's personal instructions, a plan for building/updating this
dashboard should get a quick independent-model sanity check (different model
family than the primary) before finalizing, since it involves fetching
paywalled content under his subscription - mainly to reconfirm the
copyright/personal-use guardrails and flag any technical gaps (e.g. embedding
the cookie in output). It is not a database-altering change, so this is a
light-touch check, not a mandatory gate.

## Capability 2: live Telegram VADER signals dashboard

VADER also posts daily signals into a private Telegram channel, and
`webportfolio`'s `telegram_ingest` pipeline already parses those into the
`telegram_signal` SQL table (production Azure SQL DB). This is a second,
separate output alongside the Substack weekly calendar. As of session
`ae15e7af`, its dev home is the **`weboptions`** GitHub repo
(`github.com/purduepete/weboptions`, private, cloned at
`C:\Files\Dev\main\weboptions`), not this skill's own folder.

- **Live query, not a static snapshot.** Unlike the Substack calendar (one
  dated HTML file per article), this reads the DB directly on every page
  load. The current week's day-card grid grows in place as new
  `report_date`s land, from just Monday early in the week up to all 5 days
  by Friday.
- **Puts only.** Per @jimb's request the dashboard filters to
  cash-secured-put signals (`option_right = 'P'`); covered calls are
  excluded.
- **Files** (in the `weboptions` repo):
  - `server/server.py` - Flask app, SELECT-only against `telegram_signal`.
    Binds this machine's **specific LAN IPv4 address** (not `127.0.0.1`,
    not `0.0.0.0`) so it's reachable from other devices on the home network
    during dev. Reads DB creds from webportfolio's own `config\config.ini`.
    Every `/api/*` route requires an `X-API-Key` header matching the value
    in `server/secrets.ini` (gitignored, never committed; copy
    `secrets.example.ini` and set a real random value). Supports
    `?week=YYYY-MM-DD` for week navigation and returns
    `isCurrentWeek`/`hasPriorWeekData`/`hasNextWeekData` flags.
  - `server/requirements.txt`, `README.md` (start instructions, full
    security notes, API-key rotation steps).
  - `web/vader-telegram-live.html` - single permanent file (not re-dated;
    content is always live), same subgrid/risk-tier/dark-light design
    system as the Substack calendar, with prev/next-week navigation,
    symbol filter, collapsible risk-tier groups, and a simple footer
    timestamp. On first load it prompts once for the server's `host:port`
    and the API key, then remembers both in `sessionStorage` for that
    browser tab/session only (not `localStorage`).
  - **This capability no longer lives under this skill's folder or
    OneDrive** - both prior copies (`copilot/skills/vader-options/
    telegram-dashboard/` and `OneDrive\Trading\Vader\
    vader-telegram-live.html`) were retired when the `weboptions` repo
    became the single source of truth.
- **To use it**: from `weboptions\server`, `pip install -r
  requirements.txt`, set up `secrets.ini`, run `python server.py` (it prints
  the LAN address it bound to), then open `weboptions\web\
  vader-telegram-live.html` in a browser and answer the two prompts.
- **Security guardrails**: DB credentials are read from webportfolio's
  existing config file, never duplicated or committed anywhere else. The
  server is SELECT-only by code discipline; an independent review
  (GPT-family + Mai-family, session `ae15e7af`) recommended a dedicated
  read-only SQL login as a follow-up hardening step, which @jimb chose to
  defer for now. The LAN-bind + shared-secret-API-key remote-access model
  (added later in the same session, also independently reviewed by
  GPT-5.4 + Mai-1.1-flash) is documented in the `weboptions` README; known
  accepted limitations are plaintext HTTP and the still-not-read-only-
  enforced DB creds. If either hardening request comes later, treat it as
  a small, separate follow-up, not a reason to touch anything else here.
- This capability lives entirely outside the `webportfolio` repo on purpose
  (personal, side-project tool, no GitHub issue), per @jimb's explicit
  choice to avoid that repo's mandatory workflow for something that isn't a
  production feature.
- **Future step (not yet done)**: @jimb plans to eventually move this to
  the `jimbrownhome` server for permanent hosting with automated startup
  and data refresh. That's a distinct, later request - don't build it
  unprompted.
