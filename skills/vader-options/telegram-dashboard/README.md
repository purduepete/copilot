# Vader Telegram Live Dashboard - local server

Serves live VADER option signals from webportfolio's production
`telegram_signal` table so `vader-telegram-live.html` can render a
Monday-Friday calendar dashboard from live data, the same way the
`vader-options` skill's Substack calendar does from a newsletter.

## What it is

- A small local Flask app (`server.py`), read-only, no build step.
- Lives outside the `webportfolio` repo on purpose: it's a personal,
  read-only side tool, not a production feature, so it doesn't go through
  that repo's mandatory GitHub-issue workflow.
- Reuses webportfolio's own `config/config.ini` `[Database]` section for
  DB credentials, rather than duplicating credentials anywhere new.

## Start it

```powershell
cd C:\Files\Dev\main\copilot\skills\vader-options\telegram-dashboard
pip install -r requirements.txt
python server.py
```

Then open `vader-telegram-live.html` (in `OneDrive\Trading\Vader\`) in a
browser. It fetches from `http://127.0.0.1:5057/api/week-signals`.

## API

- `GET /api/week-signals` - current Mon-Fri week's signals (only days with
  data so far).
- `GET /api/week-signals?week=YYYY-MM-DD` - any prior week's signals (the
  date can be any day in that week; it's normalized to that week's Monday).
  Response includes `isCurrentWeek`, `hasPriorWeekData`, `hasNextWeekData`
  so the frontend can enable/disable its navigation arrows correctly.
- `GET /api/health` - basic liveness check.

## Security notes

- **SELECT-only.** The server never writes to the database. There is no
  write path in this code at all.
- **Binds to 127.0.0.1 only.** Never change this to `0.0.0.0` - it holds a
  path to production DB credentials via `config.ini`.
- **Shared production database.** `telegram_signal` lives in the same Azure
  SQL database webportfolio itself uses. This script reads it directly,
  bypassing webportfolio's own backend API, because that production API is
  scoped to CSP-only signals behind Azure AD auth and doesn't fit this
  read-only personal use case.
- **Credentials are not currently DB-enforced read-only.** The `config.ini`
  credentials have full read/write rights (they're shared with the ingest
  pipeline's own writes). An independent review (GPT-family + Mai-family,
  session `ae15e7af`) recommended a dedicated read-only SQL login as a
  follow-up hardening step. @jimb chose to defer that for now and accept
  the risk temporarily; this script's own code enforces SELECT-only by
  never issuing a write statement.
- Never print, log, or commit the DB password. Never copy `config.ini`'s
  contents anywhere else.
