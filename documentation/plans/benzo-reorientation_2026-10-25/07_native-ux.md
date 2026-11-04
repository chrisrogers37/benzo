---
title: "[plan] P7 — Bounded native usability and accessibility"
type: plan
status: scoped-remainder
owner: claudna:forge
created: 2026-10-25
updated: 2026-11-04
tags: [enhancement, reliability]
repos: chrisrogers37/benzo
---

## Current scope

The accepted [November 2 amendment](../../planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md) supersedes the original P7 timer, standing-permission and unchanged P2–P8 prerequisites. This is a narrow proposed presentation task under [#43](https://github.com/chrisrogers37/benzo/issues/43), with related #79/#81/#82 dispositions in the [current ledger](../../planning/tech_debt/benzo-remediation_2026-11-02/07_backlog-reconciliation.md). No implementation or native acceptance is performed by this documentation update.

## Verified remainder at c3a9070

Native paths are relative to `Benzo/Benzo/`.

- `Views/MasterToggleView.swift:31–51` uses a graphic button without an explicit accessible name/value; `PopoverContentView.swift:38–54` makes Options a tap gesture; `FooterView.swift:11–20` has an empty-label login toggle beside separate text. Make retained controls discoverable and operable by keyboard/VoiceOver.
- `App/AppDelegate.swift:124–132` exposes diagnostics through Option-click only. Add a visible labeled entry while retaining the shortcut.
- `Theme/BenzoTheme.swift:7–10`, setting descriptions, permission disclosure and footer use faint small text. Measure affected text/control colors, correct inadequate contrast and verify wrapping/text sizing. Do not redesign the entire palette.
- `Models/SleepSetting.swift:24–28` still promises physical USB/hibernation outcomes. Qualify native descriptions and corresponding active-demo labels without changing settings behavior. The website's external caveat does not correct the native wording.

## Ownership and dependencies

The separate `implement/benzo-native-accessibility` session now owns this follow-through
and its matching demo work. This reconciliation provides the brief, not a competing
implementation. Track its acceptance independently of the website copy slice.

The existing recovery/packaging/native-acceptance/release session owns state meaning, restore/quit, supported profiles/accounts and dedicated native acceptance. The verified login-status readback defect needs a bounded behavior fix with ownership agreed at the recovery/installation boundary; it is not part of this presentation task. The update-checker/installation session owns its in-progress footer/version/update controls. Coordinate the footer handoff before editing it; do not implement a competing update surface or change either owner's behavior. Render their accepted states and route accessibility observations to their existing acceptance pass.

Own only the affected retained native views/theme/option descriptions and matching `src/landing/NativeAppDemo.jsx`, `src/design/appPresentation.js` and `src/design/app-demo.css`. Add no state machine or new control contract. Correct minimum truthful UI with its owning behavior change; this brief must not postpone required recovery disclosure.

## Acceptance for the bounded task

- [ ] Retained controls expose useful names, state/expanded values and keyboard actions; diagnostics has a visible entry.
- [ ] Keyboard focus is predictable across expanded sections, permission/diagnostic navigation and owner-defined recovery/update states; VoiceOver names and values are observed on the dedicated Mac.
- [ ] Affected text meets contextual contrast targets (normal text 4.5:1, large text 3:1, meaningful controls/focus 3:1), with readable wrapping at supported text sizes/appearances. Motion preferences are respected where animation remains.
- [ ] Native option wording avoids categorical hardware benefits, and the active demo matches the accepted presentation at the same state. Browser simulation is not native pixel or hardware evidence.
- [ ] The implementation's affected existing checks and native/browser acceptance receipts identify the exact source and observed states. Do not execute the production app on the fleet host.

## Items needing no separate implementation

First-launch options already match: native starts collapsed and the demo's **First launch** is inactive/collapsed; the active/expanded showcase is intentional. Do not “repair” that distinction. Normal popover close removes its event monitor; no alternate leaking path was demonstrated. The empty Settings scene is an unconfirmed reachability hypothesis, not a reason to invent Settings. Status-icon color already matches the theme. Unused view inputs may be removed only adjacent to justified edits.

Timers, blocker termination/identity, automatic policy writes, new standing grants, generic refactors and telemetry remain excluded. The [original October 25 P7 design/review record](https://github.com/chrisrogers37/benzo/blob/c3a9070b16c602c48b833a6e338fb40930ae4b04/documentation/plans/benzo-reorientation_2026-10-25/07_native-ux.md) remains historical evidence; its checked document-review findings never proved implementation or native acceptance.
