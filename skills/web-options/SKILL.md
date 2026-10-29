---
name: web-options
description: >-
  Build and extend @jimb's personal options-trading web dashboards. Includes a
  local HTML weekly calendar from Multiplier/Substack options-newsletter
  articles and a live HTML dashboard backed by VADER Telegram signals from the
  webportfolio database, developed in the `weboptions` repo. WHEN: "vader
  options calendar", "build my weekly options calendar", "update the options
  calendar", "pull this week's multiplier newsletter", "new vader options
  picks", "weekly trade calendar", "options newsletter to html", "telegram
  signals dashboard", "start the vader telegram server", "weboptions", "web
  options dashboard", "what selling percentage should I use", "take profit
  percentage", "profit target per tier", "analyze my options results".
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
  Fetch the public page first. Some articles expose the complete slate. Compare
  the advertised contract count with the deduplicated rows and confirm the
  timing headings and event tables are present. Use the stored subscription
  cookie only when the public response is incomplete.
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

1. Use the shared design tokens: squared corners, indigo/violet accent gradient,
   dark-default plus a light theme and toggle, Lucide-style stroke SVG icons,
   Inter font.
2. Single self-contained HTML file, no build step, named
   `weekly-options-calendar-<article-published-date>.html` (e.g.
   `weekly-options-calendar-2026-08-10.html`, using the article's own publish
   date, not a guessed "week of" date) and saved to
   `C:\Users\JimBrown\OneDrive\Trading\Vader\` (the standing output folder -
   personal use only). Create a new dated file each week rather than
   overwriting the prior week's, so the history of past calendars is kept.
   The `weboptions` Flask server reads this exact folder directly (no
   copying needed) to serve a card-based index of every week at
   `http://<LAN-IP>:5057/calendars` - dropping a correctly-named file here is
   all that's needed for it to show up there.
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
6. Open the final rendered file in the browser (`Start-Process <path>`) so
  @jimb can inspect it before the SQL write.
7. **Also write a JSON sidecar** to
   `C:\Files\Dev\main\weboptions\data\calendars\weekly-options-calendar-<publish-date>.json`.
   The HTML is for eyeballing; the sidecar is the real handoff. The Node
   server on jimbrownhome cannot read the laptop's OneDrive folder, so a week
   that never reaches this file never reaches the dashboard.
   Shape (display strings exactly as written in the HTML - the ingest step
   normalizes them):
   ```json
   {
     "publishDate": "2026-08-10",
     "title": null,
     "macro": [{ "label": "VIX at its lowest close", "text": "..." }],
     "days": [
       {
         "name": "Monday", "date": "Aug 10",
         "rule": "...", "event": null,
         "trades": [
           { "ticker": "PM", "type": "put", "strike": "$175P",
             "expiry": "2026-09-18", "dte": 42, "delta": "-0.19",
             "ann": "9.7%", "premium": "$195", "collateral": "$17,500",
             "risk": "conservative", "note": "..." }
         ]
       }
     ]
   }
   ```
   All five weekdays must be present even when a day has no trades: the rule
   and the event are the point of an empty day. `macro` carries every
   headline in the banner, which is 3 or 4 depending on the week.
  The sidecar is the single content source. Validate it and generate the HTML:
  ```powershell
  npm run validate-calendar -- .\data\calendars\weekly-options-calendar-<date>.json <count> <iso-published-timestamp>
  npm run render-calendar -- .\data\calendars\weekly-options-calendar-<date>.json <count> <iso-published-timestamp>
  npm run test:calendar
  ```
  `render-calendar` writes to `C:\Users\JimBrown\OneDrive\Trading\Vader\`
  unless a fourth positional value names another file or directory. Do not
  hand-copy the data into HTML or run the full test suite for a sidecar-only
  weekly update.
8. Ingest it, from the weboptions repo root, with the operator credentials
   (never the `weboptions_ro` service login):
   ```powershell
   $env:WEBPORTFOLIO_CONFIG_PATH='C:\Files\Dev\main\webportfolio\config\config.ini'
  npx tsx backend/tools/ingest-calendar.ts .\data\calendars\weekly-options-calendar-<date>.json
   ```
  This first command is the dry run. Review its one-file summary and obtain
  the independent review described below, then rerun it with `--confirm`.
  Run the dry command once more afterward and require `unchanged`. Re-running
  after an intentional edit needs `--force`. Note that `npm run` swallows
  `--confirm`, so call the tool through `npx tsx` directly.

### Weekly repeat workflow

When @jimb pastes a new article URL:

1. Fetch the public page. Count the advertised and deduplicated contracts and
  confirm all timing sections are present. Fetch with the stored cookie only
  if that completeness check fails. Never ask @jimb for a cookie that is
  already valid in the config file.
2. Extract the publish metadata, macro facts, key events, trade facts, and
  day rules. Convert every market time to Pacific while writing the sidecar.
3. Write the dated JSON sidecar. Run `validate-calendar` with the advertised
  trade count and source publication timestamp.
4. Run `render-calendar`, then `test:calendar`. Open the HTML once and use one
  browser check for desktop, 320px mobile, both themes, ticket count, and
  horizontal overflow.
5. Dry-run the ingest against the one dated JSON file.
6. Send the source-handling facts, validator result, focused tests, browser
  result, and dry-run summary to one independent reviewer. This one review
  covers the copyright/secret check and the mandatory database-write check.
7. On `SHIP`, rerun the one-file ingest with `--confirm`, then dry-run it once
  more and require `unchanged` with a matching source hash.

Do not run the full repository suite for a weekly sidecar update. Run it only
when shared application or ingestion code changed.

### Independent review

Use one independent reviewer from a different model family after validation
and the ingest dry run. Ask for one verdict on the copyright and secret rules,
artifact counts, test/browser evidence, and the proposed database write. A
`SHIP` verdict satisfies the light content check and the mandatory pre-write
database review. Record the model and verdict. Never run the confirmed ingest
before that verdict.

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
    Also serves the dashboard page itself (see below). Every `/api/*` route
    requires an `X-API-Key` header matching the value in `server/secrets.ini`
    (gitignored, never committed; copy `secrets.example.ini` and set a real
    random value). Supports `?week=YYYY-MM-DD` for week navigation and
    returns `isCurrentWeek`/`hasPriorWeekData`/`hasNextWeekData` flags.
  - `server/requirements.txt`, `README.md` (start instructions, full
    security notes, API-key rotation steps).
  - `web/vader-telegram-live.html` - single permanent file (not re-dated;
    content is always live), same subgrid/risk-tier/dark-light design
    system as the Substack calendar, with prev/next-week navigation,
    symbol filter, collapsible risk-tier groups, and a simple footer
    timestamp. The committed source contains a placeholder token
    (`__WEBOPTIONS_API_KEY__`) instead of a real key.
  - `web/calendars-index.html` - a card-based index of every weekly
    Substack calendar, served at `/calendars`. The server reads
    `weekly-options-calendar-*.html` filenames directly out of
    `OneDrive\Trading\Vader\` (configurable via `WEBOPTIONS_CALENDARS_DIR`)
    - dropping a correctly-named file there is all that's needed for it to
    show up on this page, newest-first, linking to `/calendars/<date>`. The
    dashboard and calendars-index pages cross-link each other in their
    headers.
  - **This capability no longer lives under this skill's folder or
    OneDrive** - both prior copies (`copilot/skills/vader-options/
    telegram-dashboard/` and `OneDrive\Trading\Vader\
    vader-telegram-live.html`) were retired when the `weboptions` repo
    became the single source of truth.
- **To use it**: from `weboptions\server`, `pip install -r
  requirements.txt`, set up `secrets.ini`, run `python server.py` (it prints
  the LAN address it bound to and the dashboard URL). Then just browse
  directly to `http://<LAN-IP>:5057/vader-telegram-live.html` (or
  `http://<LAN-IP>:5057/`, which redirects there) from any device on the
  home LAN - no local file, no prompts. The server serves the page itself
  with the real API key auto-injected in place of the placeholder, and sets
  `Cache-Control: no-store` on that response so a rotated key never sticks
  in a cached copy.
- **Security guardrails**: DB credentials are read from webportfolio's
  existing config file, never duplicated or committed anywhere else. The
  server is SELECT-only by code discipline; an independent review
  (GPT-family + Mai-family, session `ae15e7af`) recommended a dedicated
  read-only SQL login as a follow-up hardening step, which @jimb chose to
  defer for now - this remains the single highest-priority follow-up
  hardening item. The LAN-bind + shared-secret-API-key remote-access model
  (added later in the same session, independently reviewed by GPT-5.4 +
  Mai-1.1-flash) is documented in the `weboptions` README. **Important
  honest note, from a second independent review** (GPT-5.4 approve-with-
  changes, Mai-1.1-flash reject) after the page itself moved to being
  served by this app: once the API key is embedded in every served page,
  it is NOT real per-request authentication - anyone who can browse to the
  page can view-source the key out and call `/api/*` directly. @jimb
  reviewed this trade-off directly and chose to keep the header check
  anyway, as a light nuisance control, not a security boundary; **the real
  trust boundary is being on the home LAN**. Known accepted limitations
  remain plaintext HTTP and the still-not-read-only-enforced DB creds. If
  any hardening request comes later, treat it as a small, separate
  follow-up, not a reason to touch anything else here.
- This capability lives entirely outside the `webportfolio` repo on purpose
  (personal, side-project tool, no GitHub issue), per @jimb's explicit
  choice to avoid that repo's mandatory workflow for something that isn't a
  production feature.
- **Future step (not yet done)**: @jimb plans to eventually move this to
  the `jimbrownhome` server for permanent hosting with automated startup
  and data refresh. That's a distinct, later request - don't build it
  unprompted.

## Planned capability 3: per-tier profit-take recommendation

**Not built. Recorded 2026-08-19 as a future request.** Don't start it
unprompted; when @jimb asks, confirm the open questions below first.

The goal: analyze the historical signal data and recommend a **selling
percentage per risk tier** that maximizes profit. "Selling %" means the
share of the credit captured at which the position should be bought back
and closed, the standard "take profit at X% of max profit" rule. The
recommendation is **per tier** (conservative / balanced / aggressive), not
one global number, because the tiers have different delta and duration
profiles and almost certainly different optimal exits.

Decisions already made (@jimb, 2026-08-19):

- **Objective is total credit captured**, not return per day of capital
  committed. He considered both and chose raw credit, so optimize for the
  dollars kept rather than for capital turnover. If a low take-profit level
  turns out to win badly on an annualized basis, it is worth mentioning as a
  secondary observation, but the recommended number follows total credit.
- **Tier is the primary cut, delta is the allowed second one.** Start with a
  number per tier, and break it down further by entry delta where the data
  supports it. Nothing else (DTE, IV, VIX) is in scope unless he asks.

Data available for this, all in the shared PROD DB (see the weboptions repo
instructions for the read-only access model):

- `opt.telegram_signal` for the entry side: tier, delta, premium,
  annualized yield, collateral, expiry.
- `opt.telegram_entry_quote` for the market as actually captured at entry
  (`mark`, `delta`, `is_illiquid_quote`), one row per contract per report
  date. **Capture began 2026-08-05 and cannot be backfilled**, so the usable
  sample starts there and grows forward. Say so plainly in any output rather
  than implying a longer history.
- `opt.telegram_contract_price` is **the end-of-day source, and the one to
  build this on** (@jimb's answer to "which table"). It carries the forward
  daily path of each contract, which is what makes a "would this exit have
  fired, and on which day" backtest possible at all. Only `regular_close`
  rows are trustworthy; `missed` and `holiday` sessions are gaps, not zeroes,
  and must not be treated as a day the exit failed to trigger. End-of-day
  granularity also means an intraday touch of the target is invisible, so the
  result is a conservative lower bound on how often an exit would have
  filled. State that rather than implying tick-level accuracy.
- The 10-minute intraday history (local PostgreSQL, the Contract History
  page) is a secondary source only. If it is used, the simulation has to be
  causal: a target fires at capture i+1 only when captures i and i+1 both
  meet it with valid, non-stale prices, and the fill is at capture i+1's
  mark. The read-time overrides the page applies (`overrides[]` on each
  point, rules in `backend/src/history/overrides.ts`) are display repairs,
  never data: don't use a held mark as an observation, and a stale capture
  never confirms or prices an exit.

Guardrails:

- WebOptions is a reader. Any new table this needs goes in the `optcfg`
  schema, never `opt`.
- The sample will be small for a long while. Report the number of closed
  contracts behind every per-tier number and refuse to give a
  recommendation for a tier that doesn't have enough of them, rather than
  producing a confident percentage from a handful of trades. The delta
  breakdown splits an already thin sample again, so treat it as optional:
  show it only where a bucket clears the same bar, and fall back to the
  tier-level number otherwise.
- This is personal analysis of @jimb's own data, not trading advice. Keep
  the output framed as what the historical data shows.
