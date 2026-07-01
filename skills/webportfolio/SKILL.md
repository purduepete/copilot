---
name: webportfolio
description: >-
  Work with @jimb's webportfolio investment app (C:\Files\Dev\main\webportfolio,
  Azure SQL + Express/React). Today it drives a STRATEGY-ALIGNMENT AUDIT: compare how
  strategy_id is assigned across the transactions, option_transactions and
  daily_snapshot tables, validated against the strategies type flags and asset types,
  then render a self-contained HTML discrepancy report and open it in the browser. A
  timeframe can be given (e.g. the last 3 months). Read-only. WHEN: "webportfolio
  strategy audit", "run a strategy audit", "audit webportfolio strategies", "strategy
  discrepancy report", "check strategy alignment", "are my strategies consistent",
  "compare strategies across transactions and snapshots", "strategy audit for the last
  3 months", "audit strategies over the last N months".
argument-hint: optional timeframe, e.g. "-Months 3", "-Since 2026-01-01", "-AllTime"
---

# WebPortfolio

Helper skill for **@jimb's** work on the **webportfolio** app — a personal
investment / paper-trading tracker. Local clone: `C:\Files\Dev\main\webportfolio`
(Express API + React SPA + Azure SQL, single production database).

This skill starts focused on **data-quality auditing** and is built to expand toward
other webportfolio maintenance tasks later. Keep new capabilities as separate support
scripts under this folder and add a row to the table below.

> **Database note:** webportfolio has exactly **one** database (the Azure SQL prod
> DB). Credentials are read from the repo's `.env.development.local`
> (`DB_SERVER/DB_NAME/DB_USER/DB_PASSWORD`). All queries here are **read-only** — the
> audit never writes to the database. Never surface the password in output.

## Capabilities

| Want to… | Run |
|---|---|
| Audit strategy alignment across the three tables (HTML report) | `Invoke-StrategyAudit.ps1` (below) |
| _Other webportfolio audits / maintenance_ | _planned — not yet implemented_ |

## Strategy-alignment audit

`Invoke-StrategyAudit.ps1` compares `strategy_id` across the three strategy-bearing
tables and flags inconsistencies, then writes a **self-contained HTML report** and
**opens it automatically**.

Tables compared:
- `transactions` — stock transactions (`strategy_id`, `transaction_date`)
- `option_transactions` — option trades (`strategy_id`; underlying in `symbol`, plus
  `expiration_date` / `strike_price`)
- `daily_snapshot` — per-day position holdings (`strategy_id`, `snapshot_date`,
  `asset_type_id`; option symbols are OCC-style, prefixed `-`, e.g. `-HOOD260717P85`)

...validated against `strategies` (`is_stock_strategy` / `is_option_strategy` flags).

Checks (each scoped to the chosen timeframe):

| Id | Sev | What it flags |
|----|-----|---------------|
| C1 | HIGH | Snapshot **option** positions on a strategy **not** flagged `is_option_strategy` |
| C2 | HIGH | Asset-type misclassification (option-shaped symbol not typed Option, or vice-versa) |
| C6 | HIGH | Referential integrity — orphaned or cross-user `strategy_id` |
| C3 | MED | Stock symbol whose latest **transaction** strategy ≠ latest **snapshot** strategy |
| C5 | MED | Option whose `option_transactions` strategy ≠ its matched `daily_snapshot` strategy |
| C4 | MED | Same (account, symbol) carrying **multiple** distinct strategies in transactions |
| C7 | INFO | Transactions with **no** strategy assigned, by assignment method |

Options are matched between `option_transactions` and `daily_snapshot` on
**underlying + expiration + strike** (the put/call leg lives only in the snapshot OCC
symbol, so a single-char wildcard covers it) — do not try to derive P/C from
`option_transactions`.

### Run it

```powershell
# Default = last 3 months, writes HTML and opens it
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Invoke-StrategyAudit.ps1

# A specific window
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Invoke-StrategyAudit.ps1 -Months 6
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Invoke-StrategyAudit.ps1 -Since 2026-01-01
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Invoke-StrategyAudit.ps1 -AllTime

# Read the summary yourself (no HTML, no browser) — good before answering the user
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Invoke-StrategyAudit.ps1 -Months 3 -Json -NoOpen
```

**Parameters:** `-Months` (default `3`), `-Since <date>` (overrides `-Months`),
`-AllTime`, `-EnvFile` (default the repo's `.env.development.local`), `-OutDir`
(default `%TEMP%\webportfolio-strategy-audit`), `-Json`, `-NoOpen`.

**How to use in a conversation:** when the user asks for a strategy audit, parse any
timeframe they mention into `-Months`/`-Since`/`-AllTime`, run the script (it opens the
report for them). To *summarise* the findings in chat, run once more with `-Json
-NoOpen` and read the per-check `findings`/`impact`. A timeframe with **0 findings** on
a check is genuinely clean for that window — older issues can fall outside it.

## Extending this skill

Add a new support script in this folder (e.g. another audit or a maintenance helper),
give it `-Json` output for agent consumption and an auto-opening HTML view where
useful, add a row to **Capabilities**, then commit to the copilot repo. No re-junction
needed — scripts live inside the already-linked skill folder.
