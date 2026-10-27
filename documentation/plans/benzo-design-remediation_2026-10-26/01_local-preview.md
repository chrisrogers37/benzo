# Design implementation and acceptance

Status: owner-approved design shipped and merged in PR #97 on October 27. The public route uses `src/landing/BenzoLanding.jsx`; the original preview requirement is historical. Product-dependent trust and native/accessibility acceptance remain open under P2–P8.

## 1. Establish the core web design module

Consolidate presentation under one small `src/design/` module with `index.js` as its public entry point. These responsibilities must remain distinct:

| Responsibility | Owns | Does not own |
|---|---|---|
| Theme — `tokens.js`, `site.css` | Named semantic colors, font stacks, text sizes, spacing, radii, focus and motion values used across the web display; `designVariables(active)` supplies the state-dependent page values. | Native Swift behavior or a second app state machine. |
| Marketing copy — `siteCopy.js` | Hero, sections, setup guidance, FAQs, support/download destinations, metadata title and description, approved tagline. | Native UI wording silently rewritten to fit marketing. |
| App presentation — `appPresentation.js`, `app-demo.css` | Native labels/option descriptions, panel-specific values and presentation fixtures used by `NativeAppDemo`. | Privileged commands, real settings, live diagnostics, native success claims. |
| Shared primitives — `primitives.jsx` | Common brand, icon and link presentation, with accessible semantics. | Business logic or independent active state. |
| Demo state/interface — `src/demo/useBenzoDemo.js` | A single state owner used by `BenzoLanding`, with state/dispatch passed into `NativeAppDemo`. | Mirrored On/Off state separately maintained by the wrapper. |

Keep the existing pure behavior reducer where appropriate; moving files alone is not the goal. Consumers import the design module rather than duplicate tokens or native-label arrays. Document these boundaries in `src/design/README.md`. The legacy page can reuse core fixture colors/settings while retaining its appearance for comparison. Keep ordinary layout CSS readable. Do not add a generalized theme engine, runtime schema, token generator, new package or Swift-to-web build pipeline.

Native `BenzoTheme.swift` and current Swift views remain the authority for app presentation. The module records that provenance and keeps native panel metrics separate from marketing typography. Moving web presentation into the module does not make Swift and CSS a single executable source of truth. Full visual parity still requires an approved native screenshot and a comparison at the same UI state, scale and appearance.

## 2. Restore full master-switch behavior

The defect is the missing connection from the interactive panel to the surrounding page, not a preview-server problem. Drive the page's active/inactive presentation directly from the same state used by the master switch.

- On → Off changes the panel state, removes the active ambient glow, and changes all primary download treatments to their inactive appearance. Download links remain usable.
- Off → On restores the same panel/page relationship without losing unrelated requested settings.
- Restore, reset, setup completion and other existing demo actions that affect active state update the page through the same contract. Do not patch only the switch's click handler.
- Keep existing timers, settings, diagnostics, footer actions and menu open/close interactions working. Mark them as simulation outside the native panel.
- Honor reduced motion and keyboard semantics. A decorative page color must not be the only communication of state.

Add focused integration coverage that renders the whole draft, operates the master switch through its accessible control, and observes both panel and page state across Off/On. Add reset/restore coverage where it crosses this boundary; existing panel-only tests do not prove the regression fixed. Browser checks must also confirm actual computed styles and visible behavior.

## 3. Simplify typography and copy

Use a system sans stack suited to macOS, a smaller normally spaced headline, and approximately 16px reading text. Reserve monospace for technical values; remove repetitive uppercase labels, numbered feature decorations and ornamental italic headline emphasis. Keep the pink capsule identity and concise warm tone. Do not restyle the native panel to match the marketing page.

Use the existing headline words, “Done for the day. Mac still awake?”, with direct supporting copy:

> Benzo puts sleep settings and reported sleep blockers in your Mac's menu bar. Check what's running, choose your settings, and request sleep when you're finished.

Keep the dock/display/audio context as a use case. Connected devices and apps can prevent sleep or wake a Mac; this does not establish that Benzo fixes every combination or extends battery life. Do not imply that recordings, renders or interface connections can be interrupted safely.

Preferred section labels: “Choose your sleep settings”, “Check sleep blockers”, “Install Benzo”, and “Before you install”. Remove “No mystery medicine”, “From download to downtime” and the redundant “Your desk can stay a desk” closing slogan. Retain the final download action and approved origin line exactly.

Keep the primary CTA explicit (“Get Benzo for Mac”) and use the verified GitHub Releases destination until a particular supported artifact is accepted. Say that it opens GitHub Releases. On a phone, make clear installation happens on a Mac. Use real, concise setup guidance: install, find the menu-bar pill, review permissions/settings, finish ongoing work, then try the relevant control.

Reconcile title/description/social-description copy in `index.html` with `siteCopy.js` through Vite's existing `transformIndexHtml` hook so static metadata cannot retain physical guarantees removed from the visible page. Use the current build tools; do not rely on a runtime document-title update alone. The local preview removes nonexistent social-image references and uses a summary card. The canonical URL and production deployment checks are complete. A real approved social asset remains P8 work.

## 4. Verified acceptance and remaining limits

- [x] Theme, marketing copy, native presentation and demo state have documented owners in `src/design/README.md`.
- [x] Whole-page On/Off/reset behavior is tested and visually observed, including CTA and glow changes.
- [x] Demo settings, all timer choices/cancellation, diagnostics, setup, restore, login simulation and quit/restart were exercised. Keyboard Enter/Space, settings, FAQ disclosures and diagnostic scrolling were checked. Full timer expiry is covered by fake-clock tests.
- [x] Desktop 1440px, tablet 768px, mobile 375px and narrow 320px layouts were observed without horizontal overflow. The 320px timer close button is reachable after its spacing correction.
- [x] Measured marketing colors: main text 13.66:1, secondary text 5.78:1, primary CTA 6.42:1, accent/focus 5.95:1, final-band secondary text 4.725:1. These are scoped measurements, not a complete accessibility certification.
- [x] Node 24 web tests/build/audit and secret checks passed; 33 web tests pass. Merged-commit CI also passed full-Xcode Debug/Release and unhosted core tests. No new framework or harness was introduced for this redesign.
- [x] Copy/metadata omit unverified heat/fan/battery-wear guarantees and describe current installation/recovery limits.
- [x] Owner reviewed the previews and approved the site release; PR #97 is merged, `benzo.work` serves the merged version, and both draft paths redirect to `/`.
- [ ] Resolve native-panel contrast in P7, then reflect it in the demo: muted text 2.85:1, descriptions 1.82:1 and Sleep Now text 3.10:1 were recorded as exceptions.
- [ ] Exercise reduced-motion preference and browser zoom/large text; styles were inspected but these modes were not emulated. Complete screen-reader and full focus/state acceptance.
- [ ] Obtain an approved native reference and physical-device evidence for pixel parity, OS prompts, installation, sleep and recovery. SVGs approximate SF Symbols; browser example data cannot prove physical behavior.
- [ ] Reconcile the demo with each future P3–P7 behavior/UI change. Current-source matching does not verify a future contract.

Screenshots retained in this task include `benzo-live-desktop.png`, `benzo-final-demo-{desktop,mobile}.png` and `benzo-spacing-pass-{desktop,mobile,sections}.png` under `/Users/artemis/.codex/visualizations/2026/10/26/01a1786a-31b7-7162-ae49-3b5281585e3d/`. No native app was launched or host setting changed. The published site can be reviewed directly at https://benzo.work/.
