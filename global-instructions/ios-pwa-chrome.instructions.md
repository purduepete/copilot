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

## After deploying

Apps using `vite-plugin-pwa` with `registerType: "autoUpdate"` cache the shell. The first relaunch
fetches the new HTML and the second one shows it. Verify on device across two launches, and toggle
light and dark once to confirm the status bar follows.
