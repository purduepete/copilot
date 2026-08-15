"""
Vader Telegram Live Dashboard - local read-only Flask server.

Serves live VADER cash-secured-put option signals parsed from the private
Telegram channel and stored in webportfolio's production `telegram_signal`
SQL table, so `vader-telegram-live.html` can render the same Monday-Friday
calendar layout as the Substack weekly calendar, but backed by live data
instead of a static newsletter. Puts only, per @jimb's request; covered
calls are excluded from this view.

SECURITY / SCOPE (read this before changing anything):
  * SELECT-only. This script must never INSERT/UPDATE/DELETE. There is no
    write path here at all - if you need one, stop and ask first.
  * Reads DB credentials from webportfolio's own config/config.ini
    ([Database] section). Those credentials currently have full read/write
    rights on the shared production database (they are the same ones the
    ingest pipeline uses to write). This script is trusted to only SELECT;
    that trust is NOT enforced by a database-level read-only login yet.
    Independent review (GPT + Mai, session ae15e7af) flagged this and
    recommended a dedicated read-only SQL login as a follow-up hardening
    step; @jimb chose to defer that and use the existing credentials for
    now. Do not "fix" this by adding writes - if hardening happens, it
    happens as a separate, explicitly-requested change.
  * Binds to 127.0.0.1 only. Never change this to 0.0.0.0 - this process
    holds a path to production DB credentials.
  * Never print/log the DB password. Never commit anything that embeds it.

Usage:
    python server.py
    (then open vader-telegram-live.html in a browser; it fetches from
    http://127.0.0.1:5057/api/week-signals)
"""

import configparser
import datetime as dt
import os
import sys

import pyodbc
from flask import Flask, jsonify, request
from flask_cors import CORS

# --- config -------------------------------------------------------------

# webportfolio's config.ini lives 3 levels up from this file's repo, in a
# sibling repo under C:\Files\Dev\main. Resolve it explicitly rather than
# guessing a relative path, since this script lives in a different repo.
WEBPORTFOLIO_CONFIG_PATH = r"C:\Files\Dev\main\webportfolio\config\config.ini"

PORT = 5057


def _load_database_config():
    config = configparser.ConfigParser()
    if not config.read(WEBPORTFOLIO_CONFIG_PATH):
        print(
            f"Error: could not read config file at {WEBPORTFOLIO_CONFIG_PATH}",
            file=sys.stderr,
        )
        sys.exit(1)
    try:
        db_config = dict(config.items("Database"))
    except configparser.NoSectionError as exc:
        print(f"Error: missing config section: {exc}", file=sys.stderr)
        sys.exit(1)
    return db_config


DATABASE_CONFIG = _load_database_config()


def _odbc_escape(value):
    """Wrap a value in braces and double any closing braces so special characters
    in credentials cannot break the ODBC connection string."""
    return "{" + str(value).replace("}", "}}") + "}"


def get_database_connection():
    """Open a fresh read-only-intent connection. Callers must only SELECT."""
    cfg = DATABASE_CONFIG
    connection_string = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={cfg['server']};"
        f"DATABASE={cfg['database']};"
        f"UID={_odbc_escape(cfg['username'])};"
        f"PWD={_odbc_escape(cfg['password'])};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
        f"Connection Timeout=30;"
        # ApplicationIntent=ReadOnly is honored by SQL Server read-replica
        # routing on some topologies; it is not a hard guarantee on Azure SQL
        # single-database, but it signals intent and costs nothing to set.
        f"ApplicationIntent=ReadOnly;"
    )
    return pyodbc.connect(connection_string)


# --- week math (Pacific calendar dates) ----------------------------------


def _monday_of(d: dt.date) -> dt.date:
    return d - dt.timedelta(days=d.weekday())


def _current_week_monday() -> dt.date:
    # The server and the user are both effectively Pacific-local for this
    # personal tool; use the local system clock's date.
    return _monday_of(dt.date.today())


def _parse_week_param(value: str) -> dt.date:
    parsed = dt.datetime.strptime(value, "%Y-%m-%d").date()
    return _monday_of(parsed)


DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

# The dedup SQL below mirrors webportfolio's own getCspExplorer/getLatestCspSignals
# pattern (telegramSignalService.ts): partition by (report_date, contract_key),
# prefer the tier-bucketed row over a Top-Picks-only row, and OR is_top_pick
# across duplicates. Puts only ('P') - per @jimb's request the dashboard omits
# covered calls entirely.
SIGNAL_QUERY = """
WITH base AS (
    SELECT
        s.report_date,
        s.symbol,
        s.sector,
        s.option_right,
        s.strike,
        s.expiration,
        s.dte,
        s.delta,
        s.annualized_yield,
        s.premium,
        s.collateral,
        s.collateral_bucket,
        COALESCE(s.tier, s.profile) AS tier,
        COALESCE(s.contract_key,
            CONCAT(s.symbol, '|', s.strike, '|', s.expiration)) AS contract_key,
        MAX(CAST(s.is_top_pick AS INT)) OVER (
            PARTITION BY s.report_date,
                COALESCE(s.contract_key,
                    CONCAT(s.symbol, '|', s.strike, '|', s.expiration))
        ) AS is_top_pick,
        ROW_NUMBER() OVER (
            PARTITION BY s.report_date,
                COALESCE(s.contract_key,
                    CONCAT(s.symbol, '|', s.strike, '|', s.expiration))
            ORDER BY CASE WHEN s.tier IS NULL THEN 1 ELSE 0 END,
                     s.annualized_yield DESC
        ) AS rn
    FROM telegram_signal s
    WHERE s.is_current = 1 AND s.parse_status = 'parsed' AND s.option_right = 'P'
      AND s.report_date BETWEEN ? AND ?
)
SELECT
    report_date, symbol, sector, option_right, strike, expiration, dte, delta,
    annualized_yield, premium, collateral, collateral_bucket, tier, is_top_pick
FROM base
WHERE rn = 1
ORDER BY report_date, tier, option_right, annualized_yield DESC
"""

EXISTS_QUERY = """
SELECT TOP 1 1 AS found
FROM telegram_signal
WHERE is_current = 1 AND parse_status = 'parsed' AND option_right = 'P'
  AND report_date BETWEEN ? AND ?
"""


def _iso(d):
    if d is None:
        return None
    if isinstance(d, (dt.date, dt.datetime)):
        return d.strftime("%Y-%m-%d")
    return str(d)[:10]


def _week_has_data(conn, monday: dt.date) -> bool:
    friday = monday + dt.timedelta(days=4)
    cursor = conn.cursor()
    cursor.execute(EXISTS_QUERY, monday, friday)
    return cursor.fetchone() is not None


def _fetch_week(conn, monday: dt.date):
    friday = monday + dt.timedelta(days=4)
    cursor = conn.cursor()
    cursor.execute(SIGNAL_QUERY, monday, friday)
    columns = [c[0] for c in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]

    days = []
    for offset in range(5):
        day_date = monday + dt.timedelta(days=offset)
        day_iso = _iso(day_date)
        day_rows = [r for r in rows if _iso(r["report_date"]) == day_iso]
        if not day_rows:
            continue
        trades = []
        for r in day_rows:
            trades.append(
                {
                    "symbol": r["symbol"],
                    "sector": r["sector"],
                    "optionRight": r["option_right"],
                    "strike": float(r["strike"]) if r["strike"] is not None else None,
                    "expiration": _iso(r["expiration"]),
                    "dte": int(r["dte"]) if r["dte"] is not None else None,
                    "delta": float(r["delta"]) if r["delta"] is not None else None,
                    "annualizedYield": float(r["annualized_yield"])
                    if r["annualized_yield"] is not None
                    else None,
                    "premium": float(r["premium"]) if r["premium"] is not None else None,
                    "collateral": float(r["collateral"]) if r["collateral"] is not None else None,
                    "tier": r["tier"],
                    "isTopPick": bool(r["is_top_pick"]),
                }
            )
        days.append(
            {
                "name": DAY_NAMES[offset],
                "date": day_iso,
                "hasData": True,
                "trades": trades,
            }
        )
    return days


app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})


@app.route("/api/week-signals")
def week_signals():
    week_param = request.args.get("week")
    current_monday = _current_week_monday()

    if week_param:
        try:
            monday = _parse_week_param(week_param)
        except ValueError:
            return jsonify({"error": "week must be YYYY-MM-DD"}), 400
    else:
        monday = current_monday

    friday = monday + dt.timedelta(days=4)
    is_current_week = monday == current_monday

    conn = get_database_connection()
    try:
        days = _fetch_week(conn, monday)
        has_prior = _week_has_data(conn, monday - dt.timedelta(days=7))
        # Never treat a future week as navigable, even if it happened to have
        # rows (shouldn't happen, but the rule is "stop at current week").
        if monday >= current_monday:
            has_next = False
        else:
            has_next = _week_has_data(conn, monday + dt.timedelta(days=7))
    finally:
        conn.close()

    return jsonify(
        {
            "weekStart": _iso(monday),
            "weekEnd": _iso(friday),
            "generatedAt": dt.datetime.now().isoformat(timespec="seconds"),
            "isCurrentWeek": is_current_week,
            "hasPriorWeekData": has_prior,
            "hasNextWeekData": has_next,
            "days": days,
        }
    )


@app.route("/api/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    print(f"Vader Telegram Live Dashboard server starting on http://127.0.0.1:{PORT}")
    print("Read-only. SELECT-only queries against webportfolio's telegram_signal table.")
    app.run(host="127.0.0.1", port=PORT, debug=False)
