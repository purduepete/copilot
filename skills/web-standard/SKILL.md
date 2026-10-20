---
name: web-standard
description: >-
  Build or change a page, site or app in @jimb's hosted web apps so it matches his web
  standard: Roboto Flex, square corners, system/light/midnight themes with midnight default,
  Steel Blue / Midnight Blue highlights, custom dropdowns, one aligned header theme control,
  iOS PWA chrome, zero-downtime deploys, and a passing live check on Tailscale and Cloudflare.
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

1. Read the standard file and the target repo's `.github/copilot-instructions.md`.
2. Open the app's existing pieces you will reuse, and name them with file and line in the plan:
   - dropdown component (web-portfolio: `frontend/src/components/SelectField.tsx`)
   - theme context or hook and the pre-paint script in `index.html`
   - header component and its height token
   - the app's entry in `C:\Files\Dev\main\solution-deploy\site\sites.json`
3. For a new app, use web-portfolio as the reference and copy its `.prettierrc.json`,
   `frontend/eslint.config.js`, `index.html` head and `:root` tokens.
4. Present a short plan and wait for @jimb to confirm. Web Portfolio allows no downtime.

## 2. Build checklist

- No native `<select>` or `<datalist>`. Reuse the app's dropdown; portal popups that sit inside
  tables or scroll containers.
- Theme: `system`, `light`, `midnight` (default midnight), one control in the header, every
  header control the same height and top edge.
- Highlight defaults: Steel Blue `#6b8cae` on midnight with `#0f172a` text; Midnight Blue
  `#2f477b` on light with `#f8fafc` text. Apps with their own highlight are listed in the standard.
- Colors through CSS variables, square corners, `lucide-react` icons, no emoji icons.
- Display name with spaces ("Web Portfolio") anywhere a person reads it.
- No sideways scroll at 390px.

## 3. New app only

- Ids: hyphens for the solution, folders, repo and hostname; underscores for the PostgreSQL
  database, `public` schema.
- Add the `sites.json` entry with the next unused Tailscale port.
- Add the theme storage key to the `apps` map in `solution-deploy\scripts\Test-WebStandard.mjs`.
- Cloudflare hostname `<solution-id>.jimlertech.com` behind Access, written only by the parent
  session through `Set-CloudflareHostnames.ps1`. No aliases.
- Add the tooling: Prettier, ESLint, husky + lint-staged, the standard npm script names.
- Add a Site Dock favorite.

## 4. Validate and deploy

1. In the repo: Prettier, `lint`, `typecheck`, `build`, and the repo's own tests or smoke script.
2. Deploy with the repo's deploy script, never a hand copy of `npm run build`.
   Web Portfolio: `scripts\Deploy-PlatformFrontend.ps1`. Copy assets first and `index.html` last.
3. From `C:\Files\Dev\main\solution-deploy`, run both paths:

   ```powershell
   node .\scripts\Test-WebStandard.mjs --no-open --app '<app-id>'
   node .\scripts\Test-WebStandard.mjs --public --no-open --app '<app-id>'
   ```

   Use `--public --signin` if Cloudflare Access asks for a sign-in. Pass flags to node directly;
   `npm run` drops them.
4. Work is done only when both runs print PASS. Fix and redeploy on FAIL.
5. Commit and push with the Copilot trailer.

## 5. Report

- Say what changed, which checks passed on which path, and what was deployed.
- Mark iPhone and iPad layout as unverified until @jimb checks it on device.
- If the work exposed a rule the standard does not cover, add it to
  `web-standards.instructions.md` in the same change and say so.
