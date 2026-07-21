---
name: webportfolio-pull-data
description: >-
  On-demand refresher for @jimb's external datasets into the webportfolio PROD
  DB — an extensible registry of "pull dataset X now" jobs. Today it pulls the
  VADER Live Telegram options-watchlist digest (ingest -> parse -> surfaces on
  the Options Watchlist "Load from The Multiplier" button); designed so new
  datasets are added as registry entries. WHEN: "pull the data", "pull the
  latest data", "force a data update", "refresh the dataset", "webportfolio
  pull data", "pull the VADER data", "pull the telegram data", "pull the
  options watchlist", "update the multiplier data", "how many days does it
  pull", "ingest the latest telegram digest", "re-parse the signals", "add a
  new dataset to pull", "what datasets can I pull".
argument-hint: <dataset name, e.g. "vader"> (omit to list available datasets)
---

# webportfolio-pull-data

On-demand puller for @jimb's external datasets into the **webportfolio** shared
PROD Azure SQL DB. Think of it as a small **registry of pull jobs**: the user
names a dataset ("pull the VADER data", "force a data update") and this skill
runs that dataset's ingest/refresh steps, then reports what changed.

Only the datasets in the **registry** below are supported. If the user asks for
one that isn't listed, say so and offer to add it (see *Adding a new dataset*).

## Guardrails (READ FIRST)

- These pulls write to the **single shared PROD database** (`sqlgkhw25ijhyzzy`).
  There is no separate dev DB. The pulls are **idempotent upserts** (MERGE / soft
  update by stable key) and do **NOT** change schema — so they're safe to re-run,
  but still **tell the user what you're about to run and confirm before running**.
- @jimb's personal rule: anything that *alters schema/DDL* needs a Gemini second
  opinion first. These registry pulls are data-only upserts (no DDL), so that
  gate does not apply — but if a future dataset adds a migration, it does.
- Run everything from the repo root `C:\Files\Dev\main\webportfolio`.
- Report results in the user's **local time**, never UTC.

## Dataset registry

### `vader` — VADER Live Telegram options-watchlist digest

The daily "Best Opportunities" options digest posted to a private Telegram
channel. Feeds `telegram_option_watchlist` (raw) -> `telegram_signal` (parsed
CSP/CC rows) -> the frontend **Options Watchlist** page ("Load from The
Multiplier" button pulls the latest day's CSPs, strategy *Substack - The
Multiplier*).

**Aliases the user might say:** "VADER", "the multiplier", "telegram data",
"options watchlist data", "the substack data".

**Three steps — ingest, parse, then refresh tracked contracts:**

```powershell
cd C:\Files\Dev\main\webportfolio

# 1. Pull the latest Telegram messages (default: re-scan the last 3 days)
.\telegram_ingest\.venv\Scripts\python.exe .\telegram_ingest\ingest_telegram.py

# 2. Parse newly-ingested messages into telegram_signal
.\telegram_ingest\.venv\Scripts\python.exe .\telegram_ingest\parse_signals.py

# 3. Register any NEW active CSP contracts for forward-price tracking
.\telegram_ingest\.venv\Scripts\python.exe .\telegram_ingest\refresh_tracked_contracts.py
```

**Step 3 is not optional.** `refresh_tracked_contracts.py` MERGEs the distinct
active CSP contracts from `telegram_signal` into `telegram_tracked_contract`
(idempotent upsert, no DDL). If you skip it, the day's new contracts never get
tracked, so:
- the 1:15pm forward-price capture won't price them, and
- the 1:25pm **signal-outcomes rollup FK-fails** (`FK_telegram_signal_outcome_contract`)
  and the **whole batch rolls back** — the Signal Outcomes page silently stops
  updating. (This exact miss broke the rollup on 2026-07-20.)

Then the user clicks **Load from The Multiplier** on the Options Watchlist page
(the endpoint `GET /api/telegram-signals/latest-csp` returns the single most
recent `report_date`).

**How much does it pull?**
- *Ingest* re-scans the **last 3 days** by default (`--overlap-days 3`, up to
  `--limit 200` messages), newest-first, stopping once past the window. Idempotent.
- *The page/endpoint* shows **exactly ONE day** — the newest `report_date` in the
  DB (`SELECT MAX(report_date)`). It never returns a range. So the page's date only
  advances when a **newer digest exists in the channel** and has been ingested+parsed.

**Common variants:**

| Goal | Command |
| --- | --- |
| Preview ingest, write nothing | `ingest_telegram.py --dry-run` |
| Look back further (catch a missed day) | `ingest_telegram.py --overlap-days 7` |
| Parse only, write nothing | `parse_signals.py --dry-run` |
| Re-parse EVERY message (after a parser change) | `parse_signals.py --all` |
| Parse a single message | `parse_signals.py --message-id <id>` |
| Preview tracked-contract refresh, write nothing | `refresh_tracked_contracts.py --dry-run` |

**Reporting after a pull** — surface: messages fetched/inserted/updated, signals
parsed, and the **latest `report_date` before vs after** so the user can see
whether a newer day actually landed. Quick check (reads `config/config.ini`
`[Database]`, needs `$env:PYTHONIOENCODING="utf-8"` to avoid emoji/cp1252 crashes):

```powershell
cd C:\Files\Dev\main\webportfolio; $env:PYTHONIOENCODING="utf-8"
@'
import configparser, os, pyodbc
cfg = configparser.ConfigParser(); cfg.read(os.path.join(os.getcwd(),"config","config.ini"), encoding="utf-8")
db = cfg["Database"]; esc = lambda v: "{"+v.replace("}","}}")+"}"
cs=("DRIVER={ODBC Driver 18 for SQL Server};"
 f"SERVER={db['server']};DATABASE={db['database']};UID={esc(db['username'])};PWD={esc(db['password'])};"
 "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;")
cn=pyodbc.connect(cs,autocommit=True); cur=cn.cursor()
cur.execute("SELECT MAX(report_date), COUNT(*) FROM telegram_signal WHERE is_current=1")
print("latest report_date / current signals:", cur.fetchone())
cn.close()
'@ | .\telegram_ingest\.venv\Scripts\python.exe -
```

**Notes / gotchas:**
- First-ever run needs an authorized session (`telegram_ingest/vader.session`,
  gitignored). It already exists on the primary machine. On a fresh machine, do
  the one-time login via `_login_request.py` then `_login_signin.py` (see the
  repo's `telegram_ingest` runbook).
- Telegram/Database creds live in `config/config.ini` (gitignored) under
  `[Telegram]` and `[Database]`.
- VADER splits each daily digest across TWO messages (>4096 chars); the parser
  already stitches continuation parts — no special handling needed here.

## Adding a new dataset

When the user says "add a new dataset to pull" (or asks to pull something not in
the registry):

1. Ask for: the dataset name/alias, the source, and the exact command(s) that
   pull it (script path + args), plus which table(s) it writes.
2. Confirm it's an **idempotent, schema-safe** upsert. If it needs a migration,
   flag the Gemini-review + migration process (repo rule) — that's out of scope
   for a routine pull.
3. Add a new `### <name>` subsection to the registry above, mirroring the `vader`
   entry (aliases, steps, how-much-it-pulls, variants, reporting, gotchas).
4. Add matching trigger phrases to this SKILL.md's `description` `WHEN:` list so
   the user can invoke it by name — but keep the whole `description` **<= 1024
   chars** (verify, per skill-authoring).
5. Commit + push the copilot repo and tell the user to `/restart`.
