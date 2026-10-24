---
applyTo: '**/*.html, **/*.css, **/*.tsx, **/*.jsx, **/vite.config.*, **/tailwind.config.*, **/eslint.config.*, **/.prettierrc*'
description: "@jimb's web app standard: look, custom dropdowns, dark/light themes, iOS PWA, deployment, and code conventions. Use when building a new web page, new site or new app, or changing any of his web sites."
---

# Web app standard

Written 2026-10-19. The 10 hosted apps had drifted: 3 separate theme implementations, 3 font
setups, 2 Prettier configs, and the same iOS status-bar bug fixed 3 times in 3 repos.

The reference app is **web-portfolio** (`C:\Files\Dev\main\web-portfolio\frontend`). When this file
and web-portfolio disagree, follow this file and say which one should change. Existing apps keep
working as they are; bring a rule into an app when you are already changing that area.

## Visual design

Values come from `web-portfolio/frontend/src/index.css` and `tailwind.config.js`.

- **Font:** Roboto Flex, variable axes `opsz,wght@8..144,100..1000`, with this exact fallback:
  `'Roboto Flex', ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI',
  'Helvetica Neue', Arial, 'Noto Sans', sans-serif`. Load it from Google Fonts with `preconnect`
  or from `@fontsource-variable/roboto-flex`. Body weight 400, `antialiased`. Form controls use
  `font-family: inherit`. No Inter, no second UI font.
- **Corners:** square. `border-radius: 0` is the default for inputs, selects, textareas, buttons,
  cards and modals. `rounded-full` is allowed for pills, avatars, dots and toggle tracks only.
- **Palette:** Tailwind slate and gray for neutrals and status colors.
- **Highlight color** (accents, selected states, primary buttons, focus rings). Defaults from
  `web-portfolio/shared/theme-constants.ts` lines 63-68:

  | Theme | Default highlight | Text on a highlight fill |
  |---|---|---|
  | midnight (and optional dark) | Steel Blue `#6b8cae` | `#0f172a` (5.1:1) |
  | light | Midnight Blue `#2f477b` | `#f8fafc` (8.7:1) |

  Never put white text on Steel Blue (3.5:1, below AA). Switching theme resets the highlight to
  that theme's default. An app may let the user pick another highlight from web-portfolio's
  `HIGHLIGHT_COLOR_OPTIONS` list, but the defaults are fixed. Expose it as the
  `--local-highlight-color` variable (or `--accent` in apps without Tailwind).

  Existing apps that keep their own highlight by choice: Home Automation (slate), Ferry Tracker
  (teal), Work Log (`#4d8dff`, plus its extra themes) and Plex (gold). Leave Web Bookmarks
  untouched. Every other app, and every new app, uses the defaults above.
- **Surfaces per theme** (page background is `--theme-gray-900`):

  | Token | light | midnight | dark (optional) |
  |---|---|---|---|
  | page background | `#ffffff` | `#020617` | `#111827` |
  | `--theme-gray-800` (panels) | n/a | `#0f172a` | `#1f2937` |
  | `--theme-gray-750` (raised) | n/a | `#1e293b` | `#1d2735` |

- **Tokens:** colors, chrome heights and safe-area offsets live in CSS custom properties on
  `:root`, overridden by `.dark` and `.theme-midnight`. Components read the variables; they do not
  hard-code hex values. Tailwind is optional. If used, use v4 and map theme colors to
  `var(--theme-*)` the way web-portfolio does.
- **Icons:** `lucide-react` (stroke icons). No emoji as UI icons.
- **Info boxes and contextual help:** use a compact custom, theme-aware info box for
  explanatory text and control status. Keep the control row compact; put longer help in the
  box rather than an always-visible paragraph. Open it on hover over a dedicated Lucide
  `Info` button, not the surrounding checkbox, label or row. Also support keyboard focus and
  tap/click on that button. Do not use a browser `title` tooltip or `window.alert` for this help.
  Reuse the app font, square corners, surface/text/muted/border tokens and restrained shadow
  in Light and Midnight. Use a short heading, readable wrapping and compact padding. Keep the
  box within the viewport; portal it when an ancestor would clip it.
  Give the trigger an accessible name and connect the description with `aria-describedby`.
  Expose open state with `aria-expanded`; use `role="tooltip"` for non-interactive help.
  Keep the box open while the pointer moves onto it, and support Escape, outside-click and
  focus-leaving dismissal. Keep explanatory text available to assistive technology while
  visually collapsed. Errors must still be announced; never hide a failure solely in hover text.
  Test icon-only hover, keyboard focus, touch activation, dismissal, both themes and 390px
  overflow. Ferry Tracker's `frontend/src/components/NotificationControl.tsx` and
  `.notification-description` styles are the initial reference; reuse an existing app helper
  before adding another implementation.
- **Dropdowns:** use custom, theme-aware dropdowns for every app-owned choice control,
  including theme, settings and filters. Do not use a native `<select>` or `<datalist>`
  popup, even when its closed control is styled. Reuse the app's existing dropdown
  component; static pages follow the same rule without adding a UI framework.
  The trigger and popup use the app font, square corners, surface/border/accent tokens,
  visible selected state, focus indicator and themed scrollbars in Light and Midnight.
  Use the appropriate accessible button/listbox or menu-radio pattern with a label,
  expanded state and selected state. Support arrows, Home/End, Enter/Space, Escape,
  Tab and outside-click dismissal, with correct focus return. Keep popups within the
  viewport and usable by touch. A popup inside a scrolling or `overflow` container (tables,
  virtualized lists) renders in a portal on `document.body` so the container cannot clip it;
  web-portfolio's `SelectField` is the pattern. Test keyboard selection, dismissal, persistence and
  both themes; include a regression check rejecting native selects in the changed UI.
  OS-owned file, date and time pickers are separate controls.
- **Motion:** background transitions 0.3s; entrance animations `fade-in` / `fade-up` 0.6s
  ease-out. Honor `prefers-reduced-motion`.
- **Dates and times:** a date reads `mm/dd/yyyy` (`10/23/2026`) and a time reads 24-hour
  `HH:mm` (`06:35`, `13:05`), zero-padded, in the user's local time zone. A timestamp is the two
  joined by a space (`10/23/2026 13:05`). Pacific is the default and is never labeled: no
  `PDT`/`PST` suffix and no "All times Pacific" note. Add the zone abbreviation only to a time
  shown in another zone (`10/23/2026 16:05 EDT`). Where space is tight and the year is plain from context (chart axis
  ticks, day-card heads, week ranges, stat asides) the year may drop to `mm/dd`. No month names
  (`Oct 23`), no weekday-led dates (`Fri, Oct 23`), no AM/PM and no raw ISO `2026-10-23` anywhere
  a person reads it. ISO stays the format for URLs, storage and APIs. Format through one shared
  helper per app rather than inline `toLocaleString` calls, and pin `hourCycle: 'h23'` when using
  `Intl`. A month-only axis tick may stay a month name.

## Dark and light themes

Pattern from `web-portfolio/frontend/src/contexts/ThemeContext.tsx` and the pre-paint script in
`index.html`.

- Every app offers at least `system`, `light` and `midnight`. **Default is `midnight`**.
- `system` is a real, selectable preference that tracks the OS live: it resolves to `midnight`
  when the OS is dark and `light` otherwise, and re-resolves on `prefers-color-scheme` changes. The
  user can always get back to it after picking a fixed theme.
- **Midnight is the dark theme.** An app with a single dark theme uses the midnight palette and
  labels it "Midnight". The gray `dark` theme (`#111827`) is an optional extra; only apps that
  offer both keep it, and `system` still resolves to `midnight`.
- **Exception: work-log** keeps its named theme set (nord, dracula, rose, tokyo, paper and the
  default). It still needs `system`, `light` and `midnight` among them, with midnight as the
  default; the others stay as extras.
- **One theme control in the header.** Use either a compact dropdown listing every preference
  (`system`, `light`, `midnight`, plus any extras) or a toggle that cycles `light` → `midnight`
  (→ `dark` where present), never both side by side. An app with a toggle in the header lists the
  full set, including `system`, on a settings or appearance page.
- Every control in the header bar (icon buttons, dropdowns, segmented groups, text buttons such as
  Logout) shares one height token (36px in web-portfolio) and the same top edge, with no stray
  `margin-top` or padding on a group wrapper. `Test-WebStandard.mjs` fails an app with more than
  one header theme control or a misaligned one.
- Persist the preference in `localStorage`. Classes on `<html>`: `light`, `dark theme-midnight`,
  or `dark` (gray dark only). Also set `style.colorScheme`.
- Settings that must outlive a day on iPhone or iPad also need a server-set cookie. Safari deletes
  script-written storage (`localStorage` and `document.cookie`) after 7 days without a visit, and
  after a day when the page was reached through a cross-site redirect such as the Cloudflare Access
  sign-in. Read `localStorage` first, then the cookie. Site Dock's `POST /api/preferences` is the
  reference.
- An inline script in `index.html` applies the class, `color-scheme`, and the `theme-color` meta
  **before** first paint. No flash of the wrong theme.
- The theme hook updates `meta[name="theme-color"]` in the same effect that writes the class, using
  the color of the fixed top bar (usually the page background; the panel color when the top bar
  uses it).
- When the preference is `system`, listen to `prefers-color-scheme` changes and re-resolve.

## PWA and iOS

Follow `ios-pwa-chrome.instructions.md` in this folder. The short version for `index.html`:

```html
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<!-- iOS ignores an SVG favicon when adding to the home screen and needs this PNG. -->
<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
<meta name="apple-mobile-web-app-title" content="App Name" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
<meta name="theme-color" content="#020617" />
<meta name="mobile-web-app-capable" content="yes" />
```

Every app ships these icon files in `frontend/public`, copied from web-portfolio's pattern:

- `favicon.svg`: the browser tab icon, a rounded card on a 64x64 viewBox.
- `apple-touch-icon.svg`: the source for the iOS icon. Same glyph, full bleed with square corners
  and an opaque background, because iOS applies its own rounded mask and a transparent or inset
  card leaves light wedges.
- `apple-touch-icon.png`: that source rendered at exactly 180x180. Re-render it whenever the SVG
  changes (Playwright with `channel: 'msedge'` works without downloading a browser).

Use the midnight panel color as the background and steel blue `#6b8cae` for the glyph, unless the
app already has its own mark. Site Dock looks for `/favicon.svg` first when it shows a favorite, so
the same file covers the dock. Apps that serve their own routes (FastAPI, a PowerShell listener)
must answer `/favicon.svg` and `/apple-touch-icon.png` at the site root, not only under `/icons/`.

Never add `apple-mobile-web-app-status-bar-style` or a zoom lock. Fixed layers offset by
`--safe-area-*` variables built from `env(safe-area-inset-*)`. The top bar, or the app shell, is
`position: fixed` or `sticky`, touches the top edge, and spans the full width, or Safari 26 blurs
the header text (see the Safari 26 section of `ios-pwa-chrome.instructions.md`).

## Data storage

- An app that stores data uses PostgreSQL 18 on `jimbrownhome1:5432`, with its own database
  (underscores, `public` schema) and separate owner, migration and runtime roles. Runtime never
  runs DDL; schema changes go through the migration identity.
- Follow `solution-deploy\docs\PostgreSQL.md` for roles, password files and reviewed SQL plans,
  and `solution-deploy\docs\PostgreSQLBackups.md` for the nightly backup that covers the new
  database. Every database-altering step gets an independent review first.
- Azure SQL is legacy. Only Web Portfolio and Web Options use it. New apps never use it, and
  existing PostgreSQL apps never move to it.

## Deployment

The source of truth is `C:\Files\Dev\main\solution-deploy\site\sites.json`, plus the deployment
rules in `personal.instructions.md`. For a new app:

- Solution id, host folder, GitHub repo and local folder use hyphens (`web-bookmarks`). The
  PostgreSQL database uses underscores (`web_bookmarks`) and the `public` schema.
- The display name is the same words, capitalized and separated by spaces: "Site Dock",
  "Work Log", "Web Bookmarks", never "SiteDock" or "WorkLog". Use it everywhere a person reads
  the name: `<title>`, `apple-mobile-web-app-title`, the manifest `name`, the header wordmark,
  messages and tooltips, and the `name` in `sites.json`. Code identifiers (`SiteDockToken`,
  `WorkLog.psm1`) keep their joined form.
- Cloudflare hostname is `<solution-id>.jimlertech.com`, behind Cloudflare Access. One hostname,
  no aliases, written only through `Set-CloudflareHostnames.ps1`.
- Tailscale fallback is `https://jimbrownhome1.tail8ad282.ts.net:<port>/`. Take the next unused
  port in `sites.json` and add the entry there in the same change.
- Add a Site Dock favorite. Verify both access paths before calling it deployed.
- **Frontend deploys have no downtime.** Copy the new hashed assets first and `index.html` last,
  and keep the previous build's assets so open tabs can still lazy-load. No backend restart unless
  the inline scripts in `index.html` changed (their CSP hashes are read at startup).
- **CSP must allow inline styles.** Any `Content-Security-Policy` an app sends, from its server or
  a Cloudflare transform rule, must allow `'unsafe-inline'` for `<style>` elements. Put it in
  `style-src-elem` when the policy sets that directive (it overrides `style-src` for elements),
  otherwise in `style-src`. The web-bookmarks Tampermonkey palette injects a `<style>` into its
  shadow root, and `style-src 'self'` blocks it, so the overlay renders as unstyled text (the
  Solution Directory did this until 2026-10-22). Keep `script-src` strict; this exception covers
  styles only.
- **Site Dock must be able to frame the app.** Site Dock embeds favorites by their Cloudflare URL
  from both of its own addresses, so `frame-ancestors` must list `'self'`,
  `https://site-dock.jimlertech.com` and `https://jimbrownhome1.tail8ad282.ts.net:8790`, and the
  app must not send `X-Frame-Options: DENY` or `SAMEORIGIN`. Team Scoreboard shipped with
  `frame-ancestors 'self'` and showed a blank pane in Site Dock. `Test-WebStandard.mjs` fails this
  unless the app's `apps` entry sets `frame: false` (apps Site Dock never embeds).
- **Build-time settings live in a deploy script.** When the production bundle needs a variable
  (web-portfolio needs `VITE_AUTH_MODE=access`), the repo's deploy script sets it and refuses a
  bundle built without it. Never copy a plain `npm run build` output to the host. For
  web-portfolio use `scripts\Deploy-PlatformFrontend.ps1`.

## Code conventions

- **Stack for new apps:** React 19, TypeScript (strict), Vite. React Router 7 when there is more
  than one page.
- **Prettier**, at the repo root (copy `web-portfolio/.prettierrc.json`): `printWidth 120`,
  `tabWidth 4` (2 for JSON), `singleQuote`, `semi`, `trailingComma "es5"`, `arrowParens "always"`,
  `endOfLine "lf"`.
- **ESLint** flat config (copy `web-portfolio/frontend/eslint.config.js`): `@eslint/js`
  recommended, `typescript-eslint` recommended, `react-hooks` rules, `no-explicit-any` as error,
  unused vars as error with the `^_` ignore pattern, `no-console` warn except `warn`/`error`. Run
  with `--max-warnings 0`.
- **Pre-commit:** husky plus lint-staged running Prettier and ESLint on staged files. Pass
  `--no-warn-ignored` to the staged ESLint run. When `package.json` lives in a subfolder, use
  `"prepare": "cd .. && husky"` and a root `.husky/pre-commit` of `cd <folder> && npx lint-staged`.
- **Adopting the tooling in an existing repo** (done for Ferry Tracker, Fit Track, Site Dock, Web
  Inventory, Web Options, Home Automation, Plex Track, Work Log and Solution Directory): add `* text=auto eol=lf` to `.gitattributes` so Windows checkouts
  match Prettier, exclude any `index.html` whose inline script is CSP-hashed in `.prettierignore`,
  commit the config first, then the reformat alone, then list the reformat in
  `.git-blame-ignore-revs`. Scope `no-console` to browser code; server and CLI logging is fine. A
  justified exception gets an `eslint-disable-next-line <rule> -- <reason>` on the exact line, after
  Prettier has run, since Prettier can split a line away from its directive. Also exclude HTML
  whose tests read exact source text (Home Automation's pages), and make CSS-matching tests
  tolerant of whitespace and quote style. Plex Track and Work Log render their UI from
  PowerShell, so their tooling covers only JS tests, Markdown, JSON and YAML.
- **Tests:** Vitest for unit tests, Playwright for an end-to-end smoke test of the main page in
  light and dark.
- **npm script names:** `dev`, `build`, `preview`, `lint`, `lint:fix`, `format`, `format:check`,
  `typecheck`, `test`, `test:e2e`. Missing scripts are fine; differently named ones are not.

## Checking an app against this standard

Diff the app's `index.html` head and `:root` tokens against web-portfolio before touching other
CSS. Then check, in order: font stack, corner radius, highlight defaults, theme options and
default, `theme-color` sync, icon files (`/favicon.svg` and a 180x180 `/apple-touch-icon.png`
both return 200 from the deployed app), display name spacing, Prettier and ESLint config, script
names, and its `sites.json` entry.

Reading files cannot catch iOS layout bugs. An app passes the PWA and iOS checks only after it is
saved to the home screen and checked on an iPhone in portrait and an iPad in landscape, across 2
launches, in light and midnight. Until then, report it as unverified on device.

For local-only changes, run the relevant app tests and open its local preview. Checks against
deployed URLs do not validate unshipped edits.

After deploying an app, run both checks from `C:\Files\Dev\main\solution-deploy`, filtered to
that app:

```powershell
node .\scripts\Test-WebStandard.mjs --no-open --app '<app-id>'
node .\scripts\Test-WebStandard.mjs --public --no-open --app '<app-id>'
```

Pass flags directly to `node`; `npm run` can drop them. Use `--public --signin` if Cloudflare
Access requires sign-in. Both paths must print PASS before calling the deployment verified.

Run the unfiltered `npm run check:web` sweep only when explicitly requested or when shared
infrastructure or tooling changes affect multiple apps. A single-app change must not trigger
checks of unrelated apps.

The checks inspect theme, `theme-color`, head tags, icons, font, native dropdowns, console errors
and 390px width, read-only. Add a new app's theme storage key to the `apps` map in
`scripts/Test-WebStandard.mjs` when you add it to `sites.json`.
