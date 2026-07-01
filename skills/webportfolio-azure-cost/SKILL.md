---
name: webportfolio-azure-cost
description: >-
  Analyze the Azure cost of @jimb's webportfolio app (resource group
  investmentportfolio) and surface concrete ways to cut the monthly bill. Pulls
  actual cost from Cost Management, breaks it down by service and resource,
  projects this month's total from the current run-rate, and flags every service
  pacing OVER last month with a specific reduction lever — then writes a
  self-contained HTML report and opens it. Read-only. WHEN: "webportfolio azure
  cost", "analyze azure cost", "azure cost analysis", "how much is webportfolio
  costing", "reduce my azure bill", "cut azure cost", "why is my azure cost going
  up", "are we spending more this month", "azure cost report", "cost breakdown for
  investmentportfolio", "am I on track on azure spend".
argument-hint: "[-ResourceGroup <rg>] [-Json] [-NoOpen]"
---

# WebPortfolio — Azure cost analysis

Helper for **@jimb's** ongoing effort to keep the **webportfolio** app's Azure bill
down. The app lives in one resource group — **`investmentportfolio`** (subscription
*Visual Studio Credited*, `eastus2`). Last month we did work to reduce cost; this
skill checks whether we're holding the line or creeping back up, and says exactly
where to cut.

Everything here is **read-only** — it only *queries* Cost Management, never changes a
resource. Auth is whatever `az account show` is signed into (no secret needed).

## What it does

`Analyze-AzureCost.ps1` uses the **Cost Management Query REST API** (via `az rest` —
no `costmanagement` extension required) to pull *actual* cost for the resource group,
then:

- **By service** — this cycle-to-date vs **last full cycle**, plus a **projected**
  cycle total from the run-rate (`spend so far ÷ days elapsed × days in cycle`) and the
  **Δ vs last cycle**.
- **By resource** — this cycle-to-date per resource (leaf name), top 20.
- **Overspend list** — every service whose *projection* exceeds last cycle, biggest
  first, each with a **concrete reduction lever** (e.g. SQL → serverless auto-pause;
  Container Apps → scale-to-zero; Log Analytics → retention/daily cap; OpenAI →
  right-size model/TPM; Automation/Logic Apps → trim schedule frequency).

It writes a self-contained **HTML report** (@jimb's house style: indigo→violet accent,
light/dark, squared corners) to `%TEMP%\webportfolio-azure-cost\` and **opens it**.

> 💳 **Billing cycle, not calendar month.** @jimb's invoice period runs from **day 9
> through day 8** of the next month, so the script's "current"/"previous" windows are
> the **billing cycle** (default `-BillingAnchorDay 9`), *not* the calendar month.
> Comparing calendar months would badly misread spend (e.g. on the 1st it looks like
> day-0 with no data, when you're really ~3 weeks into the cycle). Pass
> `-BillingAnchorDay <n>` if the cycle ever changes.

> ⚠️ **Early-cycle caveat.** Azure usage lands with a lag and the run-rate projection
> is **noisy in the first few days** of a cycle (little data ÷ small elapsed fraction).
> Treat early projections as directional; they firm up as the cycle progresses. The
> *last-cycle actual* and *by-service* comparisons are reliable immediately.

## Run it

```powershell
# Default = investmentportfolio, writes HTML and opens it
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio-azure-cost\Analyze-AzureCost.ps1

# Read the summary yourself (no HTML, no browser) before answering the user
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio-azure-cost\Analyze-AzureCost.ps1 -Json -NoOpen

# A different resource group / subscription
pwsh -File C:\Files\Dev\main\copilot\skills\webportfolio-azure-cost\Analyze-AzureCost.ps1 -ResourceGroup <rg> -Subscription <subId>
```

**Parameters:** `-ResourceGroup` (default `investmentportfolio`), `-Subscription`
(default the current `az` account), `-BillingAnchorDay` (default `9` — cycle runs day
9 → day 8), `-OutDir` (default `%TEMP%\webportfolio-azure-cost`), `-Json`, `-NoOpen`.

**How to use in a conversation:** when the user asks about Azure cost / cutting the
bill, run the script (it opens the report). To *summarise* in chat, run once more with
`-Json -NoOpen` and read `totals`, `overspend` (service + Δ + lever), and the top
`resources`. Lead with the **projected vs last cycle** delta and the overspend levers,
and add the early-cycle caveat if it's the first few days of the billing cycle (i.e.
just after day 9).

## Notes / gotchas

- **Throttling (429).** The Cost Management query API is rate-limited; the script
  already **retries with backoff** on 429. If it still bails with *"kept getting
  throttled"*, wait ~a minute and rerun.
- **`TheLastMonth` is unsupported** by this API surface — the script uses an explicit
  `Custom` timeframe (`from`/`to`) for both the current and previous month.
- **Don't merge `stderr` into JSON.** `az rest ... 2>&1 | ConvertFrom-Json` breaks when
  a warning is emitted; the script isolates stderr to a temp file. Follow that pattern
  if you extend it.
- **Reduction levers** are heuristic, keyed by service name in the `$leverMap`
  hashtable near the bottom of the script — add/adjust entries there as the app's
  resource mix changes.

## Extending

Add sibling scripts in this folder for related cost tasks (e.g. a per-resource
day-by-day trend, or a budget/alert checker), give each a `-Json` mode and an
auto-opening HTML view, and note them here. No re-junction needed — scripts live inside
the already-linked skill folder.
