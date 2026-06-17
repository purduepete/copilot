# Weekly Summary - Week of 2026-06-08 to 2026-06-14

## Accomplishments
### Sat 06-13
- Fidelity Tampermonkey overlay consistency overhaul (webportfolio) - Reworked Fidelity trade-context overlays for consistent parameters across new vs owned positions, account & holdings-by-strategy & stock-performance pages, close-position/buy-to-close and roll workflows; common new-option overlay with dashes for empty values; Barchart overlay consistency; multiple site audits; committed, updated gist, deployed. (4h 13m)
- Fix slow iOS Safari B2C auth + Pushover deploy alerts (webportfolio) - Diagnosed/fixed slow Azure B2C login screen (timeout) on iPad/iPhone Safari; gh task, committed, pushed, deployed; added Pushover API notification on deploy completion. (45m)
- Trade alerts + browser/push notifications & helper page (webportfolio) - Added prod/101/100 API-URL dropdown (default 101) to audit tampermonkey; paper vs active in alerts; browser/window + Pushover notifications with extensive testing; alert pill color (blue) and close links; standardized price-change email alert format; iPad helper-page Fidelity link ordering; gh tasks, commits, deploys. (2h 0m)
- Watchlist research links + tampermonkey script renames (webportfolio) - Made options-watchlist research links a common site action; renamed tampermonkey scripts (Fidelity Trade Overlay, Fidelity CSP Audit, Fidelity Auto Trade Controller); reworked Evaluate Trade & Execute Option Trade research buttons; close-position deep links from stock-performance & holdings-by-strategy into Execute Option Trade; committed, pushed, deployed. (1h 5m)
### Sun 06-14
- Fix weekly report scheduling + failure notifications (webportfolio) - Investigated why Saturday-morning scheduled weekly reports (incl. CSP weekly report) were not being created; fixed scheduling and added failure notifications. (1h 5m)
- Portfolio reports: filter by mode (paper/live) (webportfolio) - Added paper/live mode filtering to the portfolio reports page; gh task, committed, pushed, deployed. (10m)
- Tampermonkey UX: chevron toggle + Auto Trade mode cleanup (webportfolio) - Added a chevron collapse control (far left) to all tampermonkey scripts; clarified/cleaned Auto Trade modes (disabled default, no/ask/preview-only) and restyled the Auto Trade dropdown to match the site. (1h 8m)
- WebBookmarks: font consistency, Tab profile switching, profile-aware groups (webbookmarks) - Unified fonts between apps and tampermonkey script; enabled Tab-key profile switching; made Add-current-page bookmark groups update with the selected profile and excluded All-profile groups from individual profiles; committed, pushed (auto-deploy via gh actions). (44m)
- Execute Option Trade: chain button, research overlay, premium info icon (webportfolio) - Added Fidelity option-chain button (highlighting selected expiration/strike) on Execute Option Trade and Evaluate Trade popout; wired standard research overlay; added info icon/tooltip explaining premium/annualized-gain color coding; fixed favorites ordering; issues, commits, deploys. (1h 17m)

## Time
- Total: 12h 27m
- Dev: 12h 27m

## Blockers
- None