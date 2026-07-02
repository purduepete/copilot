---
name: azure-health-check
description: >-
  Read-only health check across the WHOLE Azure subscription for the last N days
  (default 7) — surfaces cost step-ups, who-changed-what from the Activity Log
  (correlated to cost jumps), failed operations, scale-to-zero regressions, and
  high-impact Advisor recommendations, rendered to a self-contained HTML report.
  WHEN: "azure health check", "run a health check on my azure subscription",
  "check my azure subscription for problems", "what changed in azure in the last
  N days", "did anything break in azure", "azure subscription health", "any azure
  cost anomalies", "who changed what in azure", "azure activity log review",
  "check for scale-to-zero regressions", "azure advisor high impact".
argument-hint: "[-Days 7] [-Subscription <id>] [-Json] [-NoOpen]"
---

# Azure subscription health check

Scans an entire Azure subscription for the kinds of problems that creep in
unnoticed — a resource that quietly started costing money, a manual change that
broke scale-to-zero, a failed deploy, an Advisor flag. **Read-only.** Renders a
self-contained HTML report in house style and opens it.

Script: `C:\Files\Dev\main\copilot\skills\azure-health-check\Invoke-AzureHealthCheck.ps1`

## Run it

```powershell
# default: current az subscription, last 7 days, opens HTML
pwsh -File C:\Files\Dev\main\copilot\skills\azure-health-check\Invoke-AzureHealthCheck.ps1

# a wider window
pwsh -File C:\Files\Dev\main\copilot\skills\azure-health-check\Invoke-AzureHealthCheck.ps1 -Days 30

# machine-readable summary for the agent (no browser)
pwsh -File C:\Files\Dev\main\copilot\skills\azure-health-check\Invoke-AzureHealthCheck.ps1 -Json -NoOpen
```

Parameters: `-Days` (default 7), `-Subscription` (defaults to the current
`az account`), `-Json`, `-NoOpen`, `-OutDir`, `-AdvisorIgnore <patterns>` (extra
H5 suppression regexes), `-ShowIgnored` (reveal the normally-suppressed H5 items).

## What it checks

| # | Check | What it flags |
|---|-------|---------------|
| **H1** | Cost anomalies | Daily cost by **service** and by **resource**; a step-up = the recent half of the window costing materially more than the earlier baseline (catches a resource that went from ~$0/day to $X/day). |
| **H2** | Notable changes | Activity-Log create/update/delete/scale **writes** (who = `caller`, what, when), with a `cost-linked` tag when the change hit a resource that also stepped up in cost. |
| **H3** | Failed operations | Activity-Log entries with `status = Failed`. |
| **H4** | Scale-to-zero regressions | Container Apps with `minReplicas > 0` (won't scale to zero). |
| **H5** | Advisor | High-impact **Cost** + **HighAvailability** recommendations, **minus** low-value HA upsells (see below). |
| **H6** | Scheduled automation | **Logic App run history**: **failed/cancelled** runs, and **Enabled** workflows with **zero runs** in the window (missed-schedule signal). Catches data-plane failures the Activity Log (H3) never sees. *(Function App execution failures via App Insights are a planned follow-up.)* |

### H5 ignore list (deliberately suppressed)

H5 hides "spend MORE for enterprise HA" recommendations that don't fit a
single-region personal subscription and run counter to keeping cost down. Built-in
ignore patterns: *Set minimum instance count for App Service*, *Use Standard or
Premium tier*, *Use zone-supported App Service Plan*, *Enable zone redundancy*
(storage / SQL / managed env). The report shows a "*N low-value HA upsells
suppressed*" note; run with `-ShowIgnored` to see them, or add more patterns with
`-AdvisorIgnore`. Genuinely actionable items (API retirements, free health checks,
service-health alerts) are **never** suppressed.

## How to use the output

- Start with the **overall** card and the two H1 tables. A resource step-up is the
  signal; the matching **H2** row (same resource, `cost-linked`) is usually the
  cause — e.g. a manual "Create or Update Container App" that reactivated an app.
- **H4** is the standing-cost check: anything with `minReplicas > 0` is paying to
  stay warm 24/7 — confirm that's intended.
- Pair with the **webportfolio-azure-cost** skill for a billing-cycle-accurate cost
  projection of the `investmentportfolio` RG specifically.


## Notes

- Everything is read-only — nothing is modified.
- Cost Management throttles (429); the script retries with backoff.
- Activity Log retains ~90 days, so `-Days` beyond that returns nothing for H2/H3.
- Requires `az` signed in; `containerapp` and `advisor` checks skip gracefully if
  unavailable.
