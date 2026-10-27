# Benzo web design module

`src/design/index.js` is the public entry point for the public landing page and its browser app simulation. It owns shared presentation, without a new framework or dependency:

- `tokens.js`: semantic colors, typography, space, layout, motion and current native reference values. `designVariables(active)` supplies scoped CSS custom properties; do not copy palette/font values into page components.
- `siteCopy.js`: marketing copy, metadata, approved personal tagline, public URLs, and explanations outside the simulated app. Vite renders the same metadata into built HTML and the dev page.
- `appPresentation.js`: current native app wording, settings order/defaults, timer choices, and explicitly fictional diagnostic readings. This is a presentation reference, never an OS execution interface.
- `primitives.jsx`: shared brand, pills, symbols, icons and download link.
- `site.css` and `app-demo.css`: scoped web and app presentation. Keep site typography independent from the small sizes inside the current native panel.

## One interactive state

`BenzoLanding` owns `useBenzoDemo()` from `src/demo/useBenzoDemo.js`. It passes the same state and dispatch to `NativeAppDemo` and computes the page theme from `state.active && state.running`. Never create a second active flag in either view. Master, restore, first launch, sleep, quit and restart must update that same state. Browser timers and fixture results have no native side effects.

## Native ownership and parity

The native Swift sources remain authoritative: `Benzo/Benzo/Views/`, `Models/SleepSetting.swift`, `ViewModels/BenzoViewModel.swift` and `Theme/BenzoTheme.swift`. SwiftUI does not import this JavaScript module. A native design/copy change must be reflected in this reference and reviewed together; a future generated contract needs its own small design decision in P7/P8. Do not claim a universal cross-platform design system already exists.

The current panel keeps native wording such as “USB ports disabled” so it does not silently advertise a different app UI. The external explanation qualifies physical behavior; correcting those native claims and low contrast belongs to P7, then P8. Web SVGs approximate SF Symbols. Native pixel rendering, macOS prompts, physical sleep, recovery, and hardware behavior remain unobserved on this protected host.

## Public route

`src/App.jsx` serves `src/landing/BenzoLanding.jsx` at `/`. Vercel permanently redirects `/draft` to `/`. The public page has no draft banner or noindex override, and its canonical URL is `https://benzo.work/`. Historical Vercel preview deployments remain available at their immutable URLs. The old `BenzoHybrid` and `BenzoMockup` source/tests remain as an unbundled historical baseline; they are no longer a public comparison route. Native behavior and the browser simulation remain separate. The owner authorized this site release on October 27; it does not complete the broader P8/native acceptance plan.

## Validation

Run the existing `npm test` and `npm run build` on Node 24. Interaction coverage includes real timer durations/cancellation, native-source transitions, and page integration after master/restore/first launch/sleep/quit/restart. Render desktop/mobile checks separately: jsdom cannot verify computed colors, wrapping or native pixel parity. Follow the design remediation plan under `documentation/plans/benzo-design-remediation_2026-10-26/` for release and outcome gates.
