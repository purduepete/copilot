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
  It can also RESOLVE lost strategy/asset-type assignments on current_positions from
  prior-day daily_snapshot data (report by default, writes only with -Apply). WHEN:
  "resolve lost strategies", "current positions lost their strategy", "backfill missing
  strategies from prior day", "positions missing strategy/asset type", "fix current
  positions strategy", "align asset types from the snapshot".
argument-hint: optional timeframe, e.g. "-Months 3", "-Since 2026-01-01", "-AllTime"; or "-Apply" to write resolutions
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
> (`DB_SERVER/DB_NAME/DB_USER/DB_PASSWORD`). Most capabilities here are **read-only**;
> the only one that can write is `Resolve-LostStrategies.ps1`, and only when you pass
> **`-Apply`** (it is a dry-run report otherwise). Never surface the password in output.

## Capabilities

| Want to… | Run |
|---|---|
| Audit strategy alignment across the three tables (HTML report) | `Invoke-StrategyAudit.ps1` (below) |
| Resolve lost strategy / asset-type on current_positions from prior-day snapshot | `Resolve-LostStrategies.ps1` (below) |
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
(default `%TEMP%\webportfolio-strategy-audit`), `-Json`, `-NoOpen`,
`-IncludeAccepted` (show suppressed known-good findings, see below).

### Accepted (known-good) exceptions

Some findings are **intentional** and reviewed-as-acceptable, so the script suppresses
them from `findings`/`impact` (and the HTML/console) by default. They live in the
`$AcceptedExceptions` hashtable near the top of `Invoke-StrategyAudit.ps1`, keyed by
check `Id`; each entry matches result rows by **all** of its column=value pairs
(case-insensitive). Currently accepted:

| Check | Accepted finding | Why |
|-------|------------------|-----|
| C3 | account `7`, symbol `BRKB` (transaction vs snapshot strategy) | Reviewed 2026-07-01 — intentional |

The count of suppressed rows is reported per check (`accepted` in `-Json`, an
`N accepted` pill in HTML, `(N accepted)` in the console). Pass **`-IncludeAccepted`**
to see them anyway. To accept a new finding, add a row-matcher under its check `Id` in
`$AcceptedExceptions`.

**C7 accepted-unassigned:** because C7 is aggregated by assignment method, its
known-good rows are excluded in-SQL via a separate `$AcceptedUnassigned` list of
`@{ Account; Symbol }` pairs (also near the top of the script). Those transactions are
left out of the C7 count and reported as C7's `accepted` (restored with
`-IncludeAccepted`). Currently accepted-unassigned:

| Account | Symbol | Why |
|---------|--------|-----|
| `10` | `123990BL6` | Monthly bond Interest Income with no reference holding to inherit a strategy — intentionally left unassigned (reviewed 2026-07-01) |

**How to use in a conversation:** when the user asks for a strategy audit, parse any
timeframe they mention into `-Months`/`-Since`/`-AllTime`, run the script (it opens the
report for them). To *summarise* the findings in chat, run once more with `-Json
-NoOpen` and read the per-check `findings`/`impact`. A timeframe with **0 findings** on
a check is genuinely clean for that window — older issues can fall outside it.

## Resolve lost strategies & asset types

`Resolve-LostStrategies.ps1` fixes `current_positions` rows that lost their
`strategy_id` and/or `asset_type_id` (broker-CSV re-uploads land with these NULL, since
the CSV carries neither). It reads the value each position held on the most recent
**prior** `daily_snapshot` for the same `authenticated_user_id + account_id + symbol`
and resolves from it. `daily_snapshot` is itself built FROM `current_positions` by
`usp_create_daily_snapshot`, so yesterday's snapshot is the source of truth for the
strategy/asset type a freshly-uploaded position lost.

Scope: current positions only (`is_current = 1`) on tracked accounts, **including
cash** (cash carries a strategy in the snapshots / holdings-by-strategy view, so a
CSV re-upload that NULLs cash strategy would drop those dollars out of their strategy).
Matching **never crosses users** (it joins on `authenticated_user_id`). Strategy and
asset type are resolved **independently** — each from the most recent prior snapshot
with a non-null value for that field — so a position can be partly resolvable.

| Field | Behaviour |
|-------|-----------|
| `strategy_id` | **Backfill only** — set only when currently NULL ("lost"). Never overwrites an existing strategy. |
| `asset_type_id` | **Backfill NULLs AND overwrite disagreements** — set when NULL, and also when the current value differs from the prior snapshot, to keep asset type **aligned**. |

Positions with no usable prior snapshot are reported as **unresolvable** (assign
manually in the app).

**Read-only by default.** It writes a self-contained HTML report (Actionable +
Unresolvable, light/dark) and opens it. Pass **`-Apply`** to actually UPDATE
`current_positions` (`strategy_id` / `asset_type_id` + `date_updated`) for the
actionable rows inside a single transaction.

### Run it

```powershell
# Dry-run: report proposed resolutions and open the HTML (nothing written)
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Resolve-LostStrategies.ps1

# Read the summary yourself (no HTML, no browser) — good before answering / before -Apply
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Resolve-LostStrategies.ps1 -Json -NoOpen

# Refuse to resolve from stale snapshots (only within N days)
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Resolve-LostStrategies.ps1 -MaxSnapshotAgeDays 14

# Actually write the resolutions
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio\Resolve-LostStrategies.ps1 -Apply
```

**Parameters:** `-Apply` (write; otherwise dry-run), `-MaxSnapshotAgeDays <n>` (0 =
no age limit), `-EnvFile`, `-OutDir` (default `%TEMP%\webportfolio-lost-strategies`),
`-Json`, `-NoOpen`.

**`-Json` summary:** `totalInScope`, `actionable`, `unresolvable`,
`strategyBackfills`, `assetBackfills`, `assetOverwrites`, `rowsUpdated`, plus
`actionableRows` / `unresolvableRows` (per-position proposed changes).

**How to use in a conversation:** default to a **dry-run** first — run with `-Json
-NoOpen`, read the counts, and summarise (especially the `assetOverwrites`, since those
change an existing asset type). Because `-Apply` writes to the single production DB,
**confirm with the user before running `-Apply`**.

## Extending this skill

Add a new support script in this folder (e.g. another audit or a maintenance helper),
give it `-Json` output for agent consumption and an auto-opening HTML view where
useful, add a row to **Capabilities**, then commit to the copilot repo. No re-junction
needed — scripts live inside the already-linked skill folder.
