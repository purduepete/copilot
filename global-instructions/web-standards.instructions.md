---
applyTo: '**/*.html, **/*.css, **/*.tsx, **/*.jsx, **/vite.config.*, **/tailwind.config.*, **/eslint.config.*, **/.prettierrc*'
description: "@jimb's web app standard: look, dark/light themes, iOS PWA, deployment, and code conventions. Apply when building or changing any of his web sites."
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
- **Motion:** background transitions 0.3s; entrance animations `fade-in` / `fade-up` 0.6s
  ease-out. Honor `prefers-reduced-motion`.

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
- The toggle cycles `light` → `midnight` (→ `dark` where present). A settings control lists every
  preference, including `system`.
- Persist the preference in `localStorage`. Classes on `<html>`: `light`, `dark theme-midnight`,
  or `dark` (gray dark only). Also set `style.colorScheme`.
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
app already has its own mark. SiteDock looks for `/favicon.svg` first when it shows a favorite, so
the same file covers the dock.

Never add `apple-mobile-web-app-status-bar-style` or a zoom lock. Fixed layers offset by
`--safe-area-*` variables built from `env(safe-area-inset-*)`. The top bar, or the app shell, is
`position: fixed` or `sticky`, touches the top edge, and spans the full width, or Safari 26 blurs
the header text (see the Safari 26 section of `ios-pwa-chrome.instructions.md`).

## Deployment

The source of truth is `C:\Files\Dev\main\solution-deploy\site\sites.json`, plus the deployment
rules in `personal.instructions.md`. For a new app:

- Solution id, host folder, GitHub repo and local folder use hyphens (`web-bookmarks`). The
  PostgreSQL database uses underscores (`web_bookmarks`) and the `public` schema.
- Cloudflare hostname is `<solution-id>.jimlertech.com`, behind Cloudflare Access. One hostname,
  no aliases, written only through `Set-CloudflareHostnames.ps1`.
- Tailscale fallback is `https://jimbrownhome1.tail8ad282.ts.net:<port>/`. Take the next unused
  port in `sites.json` and add the entry there in the same change.
- Add a SiteDock favorite. Verify both access paths before calling it deployed.

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
- **Pre-commit:** husky plus lint-staged running Prettier and ESLint on staged files.
- **Tests:** Vitest for unit tests, Playwright for an end-to-end smoke test of the main page in
  light and dark.
- **npm script names:** `dev`, `build`, `preview`, `lint`, `lint:fix`, `format`, `format:check`,
  `typecheck`, `test`, `test:e2e`. Missing scripts are fine; differently named ones are not.

## Checking an app against this standard

Diff the app's `index.html` head and `:root` tokens against web-portfolio before touching other
CSS. Then check, in order: font stack, corner radius, highlight defaults, theme options and
default, `theme-color` sync, icon files (`/favicon.svg` and a 180x180 `/apple-touch-icon.png`
both return 200 from the deployed app), Prettier and ESLint config, script names, and its
`sites.json` entry.

Reading files cannot catch iOS layout bugs. An app passes the PWA and iOS checks only after it is
saved to the home screen and checked on an iPhone in portrait and an iPad in landscape, across 2
launches, in light and midnight. Until then, report it as unverified on device.
