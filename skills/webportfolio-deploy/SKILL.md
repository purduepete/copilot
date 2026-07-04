---
name: webportfolio-deploy
description: >-
  Deploy @jimb's webportfolio app (C:\Files\Dev\main\webportfolio) to Azure the safe
  way — smoke-test + deploy the frontend/backend Container Apps via web-deploy.ps1
  (which reruns smoke tests post-deploy), and the Python price-updater Azure Function
  via deploy-price-updater.ps1. Knows the prereqs (az login, azd, smoke API key), that
  pushes are deploy-safe (ci.yml/smoke.yml never deploy), and that deploys hit the
  single SHARED PROD database so they need explicit confirmation (and an optional
  Gemini pre-deploy review). WHEN: "deploy webportfolio", "deploy the frontend/backend",
  "deploy to prod", "smoke test and deploy", "run a smoke test", "run smoke tests",
  "deploy the price updater", "deploy the azure function", "is this safe to deploy",
  "will this deploy", "ship webportfolio to azure", "push to production", "web-deploy".
argument-hint: optionally what to deploy — "frontend", "backend", "price-updater", or "all"; add "smoke only" to just run smoke tests
---

# WebPortfolio — Deploy

Deploy **@jimb's** **webportfolio** app (`C:\Files\Dev\main\webportfolio` — Express API +
React SPA + Python Azure Function, **single SHARED PROD Azure SQL DB**) to Azure, safely.

> **Prod is prod.** All deploy scripts target `azure-prod` and hit the one shared
> production database. **Always plan-first and get explicit confirmation before
> deploying**, and offer a **Gemini pre-deploy review** of the shipping commits (see
> below) — @jimb often asks for one.

## What deploys what

| Component | Script | Target |
|---|---|---|
| Frontend (Static Web App) + Backend (Container App) | `scripts/web-deploy.ps1` | `azure-prod` |
| Python price-updater | `scripts/deploy-price-updater.ps1` | Function App `funcghdwfwlt5yb6u-price-flex`, RG `investmentportfolio` |
| Smoke tests (standalone) | `scripts/run-smoke-tests.ps1` | `azure-prod` (default) |

**`web-deploy.ps1` covers ONLY frontend + backend.** The price-updater Function is a
**separate** deploy — if the change touched `azure-functions/price-updater/**`, deploy
it too with `deploy-price-updater.ps1`.

## Deploy safety (pushes do NOT deploy)

The only GitHub workflows are `ci.yml` and `smoke.yml`; **neither runs any deploy**
(no `azd deploy`, `swa deploy`, `containerapp update`, or `func … publish`). So
**pushing to `main` is deploy-safe** — production only changes when you run one of the
manual scripts above. Confirm this stays true if asked "will this deploy?".

## Prerequisites (check before deploying)

```powershell
az account show --query "{name:name, user:user.name}" -o json   # must be logged in
(Get-Command azd -ErrorAction SilentlyContinue).Source          # azd installed
Test-Path C:\Files\Dev\main\webportfolio\validation\smoke\.env.smoke.local  # smoke cfg
```
The smoke API key is resolved (in order): `-SmokeTestApiKey` → `SMOKE_API_KEY` in
`validation/smoke/.env.smoke.local` (or `.env.smoke`) → `SECURITY_API_KEY` from
`.azure/azure-prod/.env`. If none is present the deploy throws before smoke.

## Recommended flow

1. **Confirm scope + repo state** — working tree clean, `main` in sync with
   `origin/main`; decide frontend/backend/price-updater. Plan-first, then confirm.
2. **Gemini pre-deploy review (optional, @jimb often wants it):** run a `code-review`
   agent on model `gemini-3.1-pro-preview` over the exact commits being shipped, asking
   for a GO / NO-GO deploy-risk verdict (public-surface preservation for refactors,
   runtime/behavior changes, async correctness). Wait for GO before deploying.
3. **Smoke test (baseline, optional):**
   ```powershell
   pwsh -File C:\Files\Dev\main\webportfolio\scripts\run-smoke-tests.ps1 azure-prod
   ```
4. **Deploy frontend + backend** (this **reruns smoke tests post-deploy** automatically
   unless `-SkipSmokeTests`):
   ```powershell
   cd C:\Files\Dev\main\webportfolio
   pwsh -File scripts\web-deploy.ps1 deploy -EnvironmentName azure-prod
   # frontend-only change? let it auto-skip the backend build:
   pwsh -File scripts\web-deploy.ps1 deploy -AutoSkipBackend
   ```
5. **Deploy price-updater** (only if `azure-functions/price-updater/**` changed):
   ```powershell
   pwsh -File C:\Files\Dev\main\webportfolio\scripts\deploy-price-updater.ps1
   # code only, infra already exists:
   pwsh -File C:\Files\Dev\main\webportfolio\scripts\deploy-price-updater.ps1 -SkipInfrastructure
   ```
6. **Report** smoke-test results and confirm the deploy succeeded.

## web-deploy.ps1 useful flags

`-SkipBackend` / `-SkipFrontend` (deploy just one), `-AutoSkipBackend` (auto-skip
backend when only `frontend/`, `shared/`, docs or `*.md` changed — big speedup),
`-SkipSmokeTests`, `-SmokeTestApiKey <key>`, `-SkipRefresh` (skip `azd env refresh`),
`-EnvironmentName <env>` (default from `.azure/config.json`). Run
`pwsh -File scripts\web-deploy.ps1 help` for the full list.

## Notes

- Config for each Azure env lives in `.azure/<env>/.env` (`azure-dev`, `azure-prod`).
  `web-deploy.ps1` / `run-smoke-tests.ps1` read `API_BASE_URL` / `WEB_BASE_URL` etc.
  from there — never print secret values from it.
- Smoke tests need a token unless you pass `-SkipToken`; `-SkipBackendValidation`
  skips the backend-side checks.
- After deploying, the app's Site Config → Build Info shows the shipped
  commit/branch/timestamp (written by `generate-build-info.mjs` at build time).
