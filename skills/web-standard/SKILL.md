---
name: web-standard
description: >-
  Build or change a page, site or app in @jimb's hosted web apps so it matches his web
  standard: Roboto Flex, square corners, system/light/midnight themes with midnight default,
  Steel Blue / Midnight Blue highlights, custom dropdowns, one aligned header theme control,
  iOS PWA chrome, zero-downtime frontend deploys, and live checks on Tailscale and Cloudflare.
  WHEN: "new web page", "add a page", "new site", "new web app", "build a page for",
  "add a screen", "new app on jimbrownhome1", "make this page match the others",
  "follow the web standard", "is this site consistent", "check the web standard",
  "run the web check", "bring <app> up to standard".
argument-hint: Which app, and what the new page or app should do
---

# Web standard workflow

The rules live in `C:\Files\Dev\main\copilot\global-instructions\web-standards.instructions.md`.
Read it in full before planning. This skill is the procedure; that file is the source of truth.
iOS chrome rules are in `ios-pwa-chrome.instructions.md` in the same folder.

## 1. Ground the plan

1. Read the standard file and the target repo's `.github/copilot-instructions.md` if present,
   plus any applicable `.github/instructions/*.instructions.md` files. Follow the repo's
   approval requirements and explicit app-specific exceptions.
2. Open the app's existing pieces you will reuse, and name them with file and line in the plan:
   - dropdown component (web-portfolio: `frontend/src/components/SelectField.tsx`)
   - theme context or hook and the pre-paint script in `index.html`
   - header component and its height token
   - the app's entry in `C:\Files\Dev\main\solution-deploy\site\sites.json`
3. For a new app, use web-portfolio as the reference and copy its `.prettierrc.json`,
   `frontend/eslint.config.js`, `index.html` head and `:root` tokens.
4. Present a short plan and wait for @jimb to confirm. All frontend deploys use the
   zero-downtime procedure. Web Portfolio also requires no downtime during migrations;
   other apps follow the migration downtime defaults in `personal.instructions.md`.

## 2. Build checklist

- Reuse the app's custom dropdown unless the target repo's instructions explicitly allow
  native `<select>` controls. Web Portfolio allows them for simple forms; its data and
  analytics controls use custom dropdowns. No native `<datalist>`. Portal custom popups
  that sit inside tables or scroll containers.
- Theme: `system`, `light`, `midnight` (default midnight), one control in the header, every
  header control the same height and top edge.
- Highlight defaults: Steel Blue `#6b8cae` on midnight with `#0f172a` text; Midnight Blue
  `#2f477b` on light with `#f8fafc` text. Apps with their own highlight are listed in the standard.
- Colors through CSS variables, square corners, `lucide-react` icons, no emoji icons.
- Desktop width (1024px and above): match Solution Directory with a centered 1440px
  border-box outer cap, 20px side padding and 1400px maximum usable content. Header
  contents and main content share the same edges, including wrappers inside frames.
  Keep the header background full-width, preserve safe areas and existing phone spacing.
  Measure header and main edges at 1280, 1440 and 1920px, accounting for scrollbar
  gutters. With a desktop sidebar, apply this geometry within the remaining area,
  including the header contents. Keep Web Inventory's 240px rail and its breakpoint.
  Reserve the same stable, normal-width desktop page scrollbar gutter as the
  directory for exact matching; keep thin control scrollbars. Use the same
  available layout width for header and main, and check both scrolling states.
- Prefer the standard's square segmented control for small option sets (sort order, view mode,
  2 to 4 filters). Use short text or icon buttons with `aria-pressed`, a smooth sliding highlight
  fill, reduced-motion support and a persisted choice where the user selects sort or view.
  Reach for it before a dropdown or a row of full buttons; Solution Directory's A-Z / calendar
  sort control is the reference.
- Keep navigation mounted while views change, animate only the navigation's selection fill,
  and reserve scrollbar space. App-specific loading animations remain in force; Ferry Tracker
  keeps its documented skeleton and 900ms data fade as an exception to brief content entrances.
  Follow the standard's navigation-transition rules; verify rapid switching,
  history, reduced motion, focus and dialogs at phone and tablet widths. Compare reference
  behavior and DOM lifetime, not just animation timing.
- Checkbox selections and checkmarks use theme accent tokens, not device/status colors.
  Check checked, unchecked, disabled and focus states in Light and Midnight.
- Contextual help uses the standard's custom themed info box, opened from the `Info` icon
  only (plus keyboard focus and tap). Keep control rows compact; no browser `title` tooltip.
  Follow the standard's accessibility, dismissal and viewport checks.
- Display name with spaces ("Web Portfolio") anywhere a person reads it.
- Dates `mm/dd/yyyy`, times 24-hour `HH:mm`, local zone; `mm/dd` only where space is tight. No
  month names, AM/PM or raw ISO dates on screen. Label a time zone only when it is not Pacific.
- Chart value axes fit the data with a little padding; do not pin them to zero or a full range
  when that flattens the movement being charted.
- No sideways scroll at 390px.

## 3. New app only

Follow "Add a new solution" in `C:\Files\Dev\main\solution-deploy\docs\Deployment.md`; it is the
source of truth for hosting. It needs, at minimum:

- `deploy\application.json` in the app repo (runtime, build, entrypoint, reserved port, JSON
  readiness endpoint, graceful stop, shared-state paths, routes).
- An entry in `solution-deploy\environments\production.json` with `newInstallation: true`, a
  unique app id, account, port, hostname and database.
- Its own PostgreSQL database on `jimbrownhome1:5432` (underscores, `public` schema) with
  separate owner, migration and runtime roles, following `solution-deploy\docs\PostgreSQL.md`
  and covered by the backup in `docs\PostgreSQLBackups.md`. Every database-altering step gets
  an independent review first. Never use Azure SQL for a new app; only Web Portfolio and Web
  Options still use it.
- A `\JimlerTech\SolutionDeploy-<app>` task that starts the app with no window, and a check after
  a reboot without signing in.
- Naming: hyphens for the solution id, folders, repo and hostname.
- The `sites.json` entry with the next unused Tailscale port, and the theme storage key in the
  `apps` map of `solution-deploy\scripts\Test-WebStandard.mjs`.
- Cloudflare hostname `<solution-id>.jimlertech.com` behind Access, written only by the parent
  session through `Set-CloudflareHostnames.ps1`. No aliases.
- The tooling: Prettier, ESLint, husky + lint-staged, the standard npm script names.
- Any CSP allows `'unsafe-inline'` in `style-src-elem` when set, otherwise in `style-src`, or the
  web-bookmarks palette overlay renders unstyled. `script-src` stays strict.
- Any CSP `frame-ancestors` lists both Site Dock origins
  (`https://site-dock.jimlertech.com`, `https://jimbrownhome1.tail8ad282.ts.net:8790`) and no
  `X-Frame-Options` DENY/SAMEORIGIN is sent, or the app is blank inside Site Dock.
- Settings that must survive a day on iPad are mirrored in a server-set cookie, because Safari
  purges `localStorage` after the Access sign-in redirect.
- A Site Dock favorite.

## 4. Validate and deploy

For local-only changes, run the relevant app tests and open its local preview. Stop before the
deployment steps below. Commit and push only when authorized, following the target repo's
approval requirements. Deployed-URL checks cannot validate unshipped edits.

When deployment is requested:
1. In the repo: Prettier, `lint`, `typecheck`, `build`, and the repo's own tests or smoke script.
   Follow the target repo's commit and push approval rules. Commit and push only when
   authorized, with the Copilot trailer. Deploys ship committed code.
2. Check how the app is hosted: is it listed under `apps` in
   `solution-deploy\environments\production.json`?
   - **Framework app** (listed; today Ferry Tracker, Home Automation, Site Dock). Deploy only
     through the framework, following "Deploy a later version" in `docs\Deployment.md`:
     `.\Deploy.ps1 -Action Plan -App <id> -Environment production -Target jimbrownhome1 -OpenReport`,
     then Stage, Deploy and Verify, each with @jimb's approval. Never hand-copy files into its
     release folder: the release then no longer matches its recorded commit. If Plan stops with
     "Managed destination exists without central placement authority", stop and tell @jimb.
     Recording placement is a reviewed production step; do not adopt or bypass it.
   - **Hand-placed app** (everything else). Its release lives under
     `\\jimbrownhome1.local\c$\ProgramData\SolutionDeploy\apps\<id>\releases\` and starts from
     `shared\Start-Service.ps1`. Use the repo's deploy script when it has one (Web Portfolio:
     `scripts\Deploy-PlatformFrontend.ps1`), never a plain `npm run build` copy. Copy hashed
     assets first and `index.html` last. Restart through the `\JimlerTech\SolutionDeploy-<id>`
     task only when backend code or CSP-hashed inline scripts changed.
3. After deployment, from `C:\Files\Dev\main\solution-deploy`, run both paths for the changed app:

   ```powershell
   node .\scripts\Test-WebStandard.mjs --no-open --app '<app-id>'
   node .\scripts\Test-WebStandard.mjs --public --no-open --app '<app-id>'
   ```

   Use `--public --signin` if Cloudflare Access asks for a sign-in. Pass flags to node directly;
   `npm run` drops them.
   Run an unfiltered sweep only when explicitly requested or when shared infrastructure or
   tooling changes affect multiple apps. Do not check unrelated apps for a single-app change.
4. Deployment is verified only when both runs print PASS. Fix and redeploy on FAIL.

## 5. Report

- Say what changed, which checks passed on which path, and what was deployed.
- Mark iPhone and iPad layout as unverified until @jimb checks it on device.
- If the work exposed a rule the standard does not cover, add it to
  `web-standards.instructions.md` in the same change and say so.
