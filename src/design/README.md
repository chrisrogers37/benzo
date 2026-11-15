# Benzo web design module

`src/design/index.js` is the public entry point for the public landing page and its browser app simulation. It owns shared presentation, without a new framework or dependency:

- `tokens.js`: semantic colors, typography, space, layout, motion and current native reference values. `designVariables(active)` supplies scoped CSS custom properties; do not copy palette/font values into page components.
- `siteCopy.js`: marketing copy, metadata, approved personal tagline, public URLs, and explanations outside the simulated app. Vite renders the same metadata into built HTML and the dev page.
- `appPresentation.js`: current native source wording, settings order/defaults, containment explanations, and explicitly fictional diagnostic result fixtures. This is a presentation reference, never an OS execution interface.
- `primitives.jsx`: shared brand, pills, symbols, icons and download link.
- `site.css` and `app-demo.css`: scoped web and app presentation. Keep site typography independent from the small sizes inside the current native panel.

## One interactive state

`BenzoLanding` owns the one `useBenzoDemo()` reducer and passes it to `NativeAppDemo`; phase is the source of truth for panel and page theme. Phases are checking, off, applying, activeVerified, restoring and recoveryRequired. Choices are editable only in resolved Off. Apply freezes them; Off/System Defaults and quit simulate verified restoration of immutable captured originals. Quit waits for a busy apply to settle before starting restore. Only cells changed by the selected target become owned. Keep Current releases the conflicting cell by explicit choice, while other owned cells remain in recovery until restored. System Defaults means captured pre-Benzo values, not a factory reset. The AC-only target exposes Power Nap, Network Wake and TCP Keep-Alive; Hibernate Mode and Proximity Wake stay unchecked and unavailable because required keys are not reported. Recovery transitions are exported as pure reducer actions so failure, uncertain execution, conflicts and legacy evidence can be exercised without a scenario harness. The demonstration has deterministic success by default and no timer, blocker panel or native side effects.

## Native ownership and parity

The permission panel has three non-authorizing evidence states. Refresh simulates
another observation, and Back only navigates; neither installs a rule or changes
activity, settings or recovery evidence. Existing release setup is described
separately in the website FAQ. Historical mockups retain their original behavior.

Diagnostic datasets have separate loading, success and failure states. Empty results are distinguished from failed reads; sleep sessions and wake reason share one result. Current Settings displays reported values and missing keys without comparisons to preferences or a restoration claim. Fixtures remain browser-only; no device reads are performed.

The native Swift sources remain authoritative: `Benzo/Benzo/Views/`, `Models/SleepSetting.swift`, `ViewModels/BenzoViewModel.swift` and `Theme/BenzoTheme.swift`. SwiftUI does not import this JavaScript module. A native design/copy change must be reflected in the active simulation and reviewed together. No generated contract or new framework is required by the containment plan.

The panel and external explanation do not promise USB power loss or physical hibernation from settings readback. Web SVGs approximate SF Symbols. Native pixel rendering, macOS prompts, physical sleep, recovery, and hardware behavior remain unobserved on this protected host.

## Public route

`src/App.jsx` serves `src/landing/BenzoLanding.jsx` at `/`. Vercel permanently redirects `/draft` to `/`. The public page has no draft banner or noindex override, and its canonical URL is `https://benzo.work/`. Historical Vercel preview deployments remain available at their immutable URLs. The old `BenzoHybrid` and `BenzoMockup` source/tests remain as an unbundled historical baseline; they are no longer a public comparison route. Native behavior and the browser simulation remain separate. The owner authorized this site release on October 27; it does not complete the broader P8/native acceptance plan.

## Validation

Run the existing `npm test` and `npm run build` on Node 24. Interaction coverage includes disabled sleep, active/recovery selection guards, editable first-launch choices, diagnostic loading/error/empty outcomes and neutral observations, and page integration after master/restore/first launch/quit/restart. Historical timer tests belong only to the unbundled baseline. Render desktop/mobile checks separately: jsdom cannot verify computed colors, wrapping or native pixel parity. Follow the [accepted remediation scope](../../documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md) for order and release boundaries. This source simulation does not establish which behavior is in an existing downloaded DMG.
