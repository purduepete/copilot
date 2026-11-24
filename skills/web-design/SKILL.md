---
name: web-design
description: >-
  Design, build, review, or change a web page or app for @jimb. Use a
  preview-first workflow, learn from his references, and keep each site's
  pages and controls visually consistent. WHEN: "build a website", "design
  a page", "change the UI", "make the site consistent", "fix the layout",
  "review the design", "use this site for inspiration".
argument-hint: Site, requested change, and any visual references
---

# Web design

Give each site its own identity. Within a site, use consistent typography,
spacing, alignment, controls, navigation, and modal patterns. Favor clean,
organized, simple pages with a strong visual presence.

## Understand and explore

- Establish the page's purpose, audience, content, and necessary behavior.
  For a small change, use the existing design and avoid a lengthy discovery.
- Ask for reference sites or screenshots when the direction is unclear. Ask
  what Jim likes about them, such as layout, typography, color, density, or
  interactions. Explain which qualities will inform an original design; do
  not copy a site wholesale. Don't access private content without permission.
- For an existing site, inspect its pages, styles, shared components, and
  project instructions before choosing a direction. Identify visible
  inconsistencies and agree with Jim on a direction before broad visual changes.
- When a new or substantially revised design needs exploration, discuss
  references and options, then use a working preview to choose and refine the
  direction with Jim. Record agreed site-specific rules and intentional
  exceptions in the project where future changes can find them.

## Learn from feedback

- Treat each review as feedback for future web work. When Jim identifies a
  recurring preference or a missed visual detail, update this skill or the
  appropriate shared instruction so he doesn't need to repeat it.
- Keep choices specific to one site's design in that project's documentation.
  Generalize a site-specific choice only when Jim establishes it as a broader
  preference; reuse recorded guidance before asking the same question again.

## Build consistently

- Use the site's existing shared styles, tokens, and components where
  appropriate. Establish shared patterns for recurring controls rather than
  independently styling equivalent controls on each page or modal.
- Check button size and text, icon, and baseline alignment across comparable
  controls. For example, two equivalent Save buttons in a page and a modal
  should follow the same site rule; a compact icon button can have a documented
  different size. Preserve suitable touch targets and accessible focus states.
- Record site-specific control dimensions and alignment rules in project
  guidance, and implement them with shared styles or tokens. Measure rendered
  field edges and visible button sizes against the established page controls,
  including touch targets, before presenting a preview.
- Inspect the rendered interface closely for small visual misalignments without
  waiting for Jim to point them out. Check text baselines and the optical
  alignment of labels, switches, icons, and badges, including neighboring
  controls. CSS centering alone does not establish that they look aligned.
- Check the space between text and its container edges, especially when an edit
  row reuses styling meant for a row with an icon or handle. Compare and measure
  the inset against nearby rows before presenting the preview.
- Check tooltip styling and behavior across icon controls, status indicators,
  dialogs, and charts. Reuse the site's chosen pattern and preserve keyboard
  descriptions and touch usability.
- Inspect desktop, phone, and tablet layouts, including modals, both themes
  where applicable, wrapping, and browser-specific text rendering. For phone
  and tablet checks, emulate real `pointer: coarse` touch metrics (e.g., CDP
  touch emulation with `mobile: true`), not just a resized desktop window, so
  `@media (pointer: coarse)` rules are actually exercised. Use the actual
  design and measured examples to decide acceptance criteria rather than
  assuming all controls need identical dimensions.
- Before presenting a preview, run a quick geometry and state check across the
  rendered page: verify sibling control heights in every toolbar/row (`0`
  mismatches), exact `top`/`bottom` alignment of adjacent labels and numbers
  (`0px` offset), exact `left`-edge alignment of stacked headers/controls,
  `:hover` rendering (no outer hit-box glow), armed/confirm states at `320px`
  (no label overlap), and resize/orientation transitions (dynamic highlights
  recalculate cleanly).
- Apply shared-pattern changes across every page of the site in the same pass
  (headers, counts, icon buttons, dropdowns, disclosures, dividers), not only
  the single page currently in view.
- When a site combines a shared stylesheet with page-level `<style>` blocks,
  verify computed styles in the preview rather than assuming the shared rule
  won the cascade or specificity. Run an independent `code-review` pass before
  committing multi-file UI changes.
- Follow the shared local-preview procedure. Give the preview the full
  underlying backend data when safely available, including all relevant pages
  and data categories. Check for missing or truncated data, and disclose
  limitations or fixture substitutions. Don't operate real devices or make
  state-changing requests merely to review a page.
- Verify deployed sites through the `localUrl` in Solution Deploy's
  `site\sites.json`, never a Cloudflare or Tailscale URL. Use a separate local
  preview for unreleased changes and identify its data source; the deployed
  address cannot show those changes until release.
- Use previews and other non-test checks while iterating; defer tests until
  before a commit. Run browser/e2e suites only when Jim also asks to deploy.
  Responsive previews do not prove physical iPhone/iPad or installed-app
  rendering; identify those checks as pending until confirmed.
