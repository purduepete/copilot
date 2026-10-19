---
applyTo: '**/index.html'
description: "iOS PWA status bar, theme-color, and safe-area rules for @jimb's installed web apps. Apply to any app that can be added to an iPhone or iPad home screen."
---

# iOS PWA status bar and safe areas

Written 2026-09-11 after the same bug was fixed in webportfolio, fittrack, and webinventory:
in the installed app, the iPad status bar covered the top few pixels of the navbar.

## Never add `apple-mobile-web-app-status-bar-style`

`black-translucent` tells the webview to draw **under** the iOS status bar. On iPad,
`env(safe-area-inset-top)` under-reports that strip, so every padding compensation is a few px
short and the top of the UI stays clipped. No amount of CSS fixes it.

Leave the meta out. iOS then reserves the status bar, paints it from the `theme-color` meta, and
`env(safe-area-inset-top)` becomes `0px` in the vertical orientation.

`apple-mobile-web-app-capable` is also obsolete. `mobile-web-app-capable` plus a manifest with
`"display": "standalone"` is what standalone detection reads now.

## The head that works

```html
<meta name="apple-mobile-web-app-title" content="App Name" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
<meta name="theme-color" content="#020617" />
<meta name="mobile-web-app-capable" content="yes" />
```

`viewport-fit=cover` stays. It is what makes `env(safe-area-inset-*)` report real values for the
landscape notch, the left and right edges, and the home indicator.

No `maximum-scale=1.0, user-scalable=no`. A zoom lock is an accessibility problem and iOS
overrides it anyway.

## Keep `theme-color` in sync with the active theme

The reserved strip is painted from `theme-color`, so a stale value shows a dark bar above a light
app. Set it in two places:

1. The inline pre-paint script in `index.html`, from the same variable that sets the launch
   background. This covers cold launch, before React mounts.
2. The theme hook or context, in the same effect that writes `data-theme` or the `dark` class:
   ```ts
   document.querySelector('meta[name="theme-color"]')?.setAttribute('content', COLORS[theme]);
   ```

Reference implementations: `weboptions/frontend/src/theme/ThemeProvider.tsx`,
`webportfolio/frontend/src/contexts/ThemeContext.tsx`, `fittrack/frontend/src/lib/useTheme.ts`.

## Safe-area CSS still matters

Keep `env(safe-area-inset-left/right/bottom)` on fixed layers. Only the top inset goes to zero, and
only in portrait. Patterns like `max(12px, env(safe-area-inset-top))` and
`calc(env(safe-area-inset-top) + 12px)` are fine, since they collapse to the literal at a zero inset.

## Diagnosing a clipped top bar

When one app renders correctly and another does not, **diff the `index.html` head before touching
any CSS.** Three rounds of padding math went into chasing this symptom before the meta tag was
found.

## Safari 26: the top bar must be fixed or sticky and full width

Written 2026-10-19 after site-dock took 4 deploys to fix on iPad landscape (fixed in site-dock
`d8c353c`). The header text looked blurred and the status bar faded into the header.

In iOS and iPadOS 26 standalone apps, Safari blurs page content near the top edge and tints the
status bar on its own. It skips the blur and uses your color only when a `position: fixed` or
`position: sticky` element is **within 4px of the top edge and at least 80% of the viewport wide**,
with an opaque `background-color` and no `backdrop-filter`.

- The top bar, or the whole app frame, must meet that rule. web-portfolio's navbar is
  `sticky top-0` at full width with `pt-[var(--safe-area-top)]` (`Navbar.tsx` line 288).
- Layouts with side-by-side headers (sidebar brand plus workspace header) fail, because each header
  is under 80%. Make the shell itself the element:
  `.app { position: fixed; inset: 0; background: var(--panel); padding-top: env(safe-area-inset-top); }`
- `theme-color` and the pre-paint `html` background are the top bar's color, not the page
  background, when the 2 differ. Otherwise the status bar shows a different color than the header.
- These did not work in site-dock: changing header heights or colors inside a non-fixed layout,
  and a separate fixed strip only as tall as `env(safe-area-inset-top)`.

## Diagnosing a top-edge problem on device

- **Measure before changing anything.** Ask for a home-screen screenshot, read the pixel colors
  down the top 80 rows, and enlarge the header next to web-portfolio's at the same position. That
  shows whether the problem is a color, a clip, or a blur.
- Change one thing per deploy and confirm it on the device before the next change. Do not report a
  layout bug as fixed until @jimb confirms it from a fresh home-screen launch.

## After deploying

Apps using `vite-plugin-pwa` with `registerType: "autoUpdate"` cache the shell. The first relaunch
fetches the new HTML and the second one shows it. Verify on device across two launches, and toggle
light and dark once to confirm the status bar follows.
