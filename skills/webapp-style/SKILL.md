---
name: webapp-style
description: >-
  @jimb's house style for web-app UIs — apply this whenever building or restyling
  a front-end so it matches his preferences: a modern indigo→violet accent on
  CSS-variable theming, full light + dark support, clean Lucide-style stroke SVG
  icons (NO emoji), glassy blurred bars, and SQUARED (non-rounded) corners.
  WHEN: "make this look modern", "modernize the UI", "restyle this app",
  "add light/dark theme", "add a theme toggle", "square off the corners",
  "remove rounded corners", "use my design style", "make it match my other apps",
  "pick icons", "replace the emoji", "new web app styling", "theme this app".
argument-hint: optional path to the client/ or styles file to restyle
---

# webapp-style — @jimb's web-app UI house style

Apply these preferences whenever you build a new front-end or restyle an existing
one. The goal is a clean, modern, **squared** look that's consistent across all of
@jimb's web apps (e.g. webinventory, webbookmarks).

## Non-negotiables (the things @jimb always wants)

1. **Squared corners — radius 0 everywhere.** @jimb does NOT like rounded edges.
   Drive ALL corner radius through CSS tokens so it's one place to change:
   ```css
   :root { --radius: 0; --radius-lg: 0; }
   ```
   Every `border-radius` declaration uses `var(--radius)` (or `var(--radius-lg)`),
   never a hardcoded `px` or `999px` pill value. Also zero out any inline
   `style={{ borderRadius: N }}` in components and any `rx`/`ry` on icon/favicon
   rects. Pills/badges/chips are squared rectangles, not lozenges.

2. **No emoji as UI icons.** Use clean **Lucide-style stroke SVGs**. Ship a single
   `Icon.tsx` (or equivalent) that exports a typed `IconName` union and an `Icon`
   component:
   ```tsx
   <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
        stroke="currentColor" strokeWidth={1.75}
        strokeLinecap="round" strokeLinejoin="round">{paths[name]}</svg>
   ```
   Default `size={20}`. Icons inherit color via `currentColor`. (Stroke line-caps
   may stay round — that's about the stroke, not the layout corners.)

3. **Full light + dark theme**, CSS custom properties only:
   - **Dark is the default** under `:root`.
   - Light under `:root[data-theme='light']`, PLUS a system-following block:
     ```css
     @media (prefers-color-scheme: light) {
       :root:not([data-theme='dark']) { /* light vars */ }
     }
     ```
   - A toggle button sets `document.documentElement` `data-theme` and persists to
     `localStorage('theme')`. Toggle shows a **sun** icon in dark mode, **moon** in light.
   - **No FOUC:** an inline `<script>` in `index.html` reads
     `localStorage.getItem('theme')` and sets `data-theme` + the meta theme-color
     BEFORE first paint.
   - Keep `<meta name="theme-color">` in sync dynamically (update it in the theme effect).

## The palette / tokens

Accent is an **indigo → violet** gradient; surfaces are layered (3 levels); glassy
bars use translucent backgrounds + `backdrop-filter: blur()`.

```css
:root {                 /* dark (default) */
  --radius: 0; --radius-lg: 0;
  --bg: #0b0e16; --surface: #141a28; --surface-2: #1d2538; --surface-3: #28324a;
  --text: #e7ecf5; --muted: #9aa6bd; --border: #28324a; --border-strong: #3a465f;
  --accent: #6366f1; --accent-2: #8b5cf6;
  --accent-grad: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
  --on-accent: #fff;
  --glass: rgba(20,26,40,0.72); --glass-strong: rgba(20,26,40,0.9);
  --shadow: 0 1px 2px rgba(0,0,0,0.3), 0 8px 24px rgba(0,0,0,0.28);
  --shadow-accent: 0 8px 20px rgba(99,102,241,0.35);
}
:root[data-theme='light'] {  /* light (also mirror inside the prefers-color-scheme block) */
  --bg: #f5f7fb; --surface: #ffffff; --surface-2: #f1f3f9; --surface-3: #e5e9f2;
  --text: #1a2233; --muted: #5b6678; --border: #e5e9f2; --border-strong: #cdd5e4;
  --glass: rgba(255,255,255,0.72); --glass-strong: rgba(255,255,255,0.9);
}
```

- **Font:** Inter (`<link>` from Google Fonts), `letter-spacing: -0.01em` on headings/buttons.
- **Topbar / tabbar:** sticky, `background: var(--glass)`, `backdrop-filter: blur(12px)`,
  thin `--border` divider, `var(--shadow)`.
- **Buttons:** `background: var(--accent-grad)`, `var(--shadow-accent)`, subtle
  `:active { transform: translateY(1px) scale(0.99); }`. Variants: `.ghost`
  (surface + border, no shadow), `.danger`, `.small`, `.icon-btn`.
- **Cards/inputs:** `var(--surface)` + `1px solid var(--border)`, `var(--radius)`,
  focus ring via accent border + soft glow.
- **Transitions:** ~0.15–0.18s ease on color/background/transform/box-shadow.
- **Links:** `.link` class colored with `--accent-2`.

## Icon set (the named glyphs to provide)

search · box · boxes · camera · plus · printer · trash · close · scan · sync ·
sparkles · check · move · chevron · sun · moon — extend as the app needs, same
stroke style.

## Workflow when restyling

1. Centralize tokens in `styles.css` `:root` (dark) + light overrides + the
   `prefers-color-scheme` block. Set `--radius`/`--radius-lg` to `0`.
2. Replace all hardcoded `border-radius` (incl. `999px` pills) with `var(--radius)`;
   grep for stray `borderRadius`/`rx=` in components, favicon, generated icons.
3. Drop in `Icon.tsx`; replace every emoji with `<Icon name=… />`.
4. Wire the theme toggle: state + `localStorage` + `data-theme` effect + dynamic
   meta theme-color, and add the no-FOUC inline script to `index.html`.
5. `cd client; npm run build` to verify (the >500 kB chunk warning is benign), then
   commit & push.

## Reference implementation

`webinventory` (`C:\Files\Dev\main\webinventory\client`) is the canonical example:
`src/styles.css`, `src/Icon.tsx`, `src/App.tsx` (toggle), `index.html` (no-FOUC).
