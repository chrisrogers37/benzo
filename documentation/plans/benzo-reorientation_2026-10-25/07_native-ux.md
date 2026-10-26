---
title: "[plan] P7 — Clear native UX and demo parity"
type: plan
status: draft
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-25
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size M, risk medium. Make the already-correct permission/control/recovery behavior understandable and accessible in the compact native popover, with matching demo presentation. One PR on `codex/benzo-native-ux`; no permission or recovery semantics change is hidden inside visual work.

## Evidence

The setup screenshot in the evaluation shows low-contrast clipped disclosure. `Views/FooterView.swift:32` calls saved originals system defaults; P4 must already have corrected that behavior/label. `App/AppDelegate.swift:118` removes the global monitor on normal close, so an alternate-path leak must first be reproduced. `App/BenzoApp.swift` declares an empty Settings scene; reachability is not established. `src/BenzoHybrid.jsx:9` initially opens options while native parity differs.

## Implementation Plan

### Dependencies

P6 merged. P3–P6 already supply minimum truthful native/demo states; P7 does not defer their correctness.

### Blocks

P8 final web polish and #43 closure across both surfaces. #79/#82 remaining hypotheses require explicit disposition here.

### Steps

1. **Own files:** native `Views/SetupView.swift`, `MasterToggleView.swift`, `SettingRowView.swift`, `SleepNowButton.swift`, `FooterView.swift`, `DiagnosticView.swift`, `PopoverContentView.swift`, `Theme/BenzoTheme.swift`, `Models/SleepSetting.swift` native option descriptions, `App/AppDelegate.swift`, `App/BenzoApp.swift` if a demonstrated scene issue exists; extracted demo component/styles/state/tests; native presentation/accessibility tests and evidence. Preserve C1–C9 contracts.
2. Setup displays the whole persistent-account authorization disclosure, actual controlling account, profile scope, eligibility, Install/Repair pending/error state and removal path. Use readable multiline layout and scrolling/adaptive height where needed; do not truncate consequences to fit the old fixed box. Update `SleepSetting.swift` option descriptions and corresponding demo copy, explaining network/Find My consequences with qualified language. No categorical physical hibernation, zero-drain or USB-power guarantees may survive in native descriptions, including unknown-hardware render states. No implied app-exclusive permission.
3. Establish a visible state hierarchy: checking/in-progress; active configuration observed at time; Off/no owned changes; recovery required with unresolved count and action. Keep requested selection distinguishable from applied state. Rename ambiguous actions consistently to Restore Previous Settings, Review Recovery, Cancel Scheduled Sleep and Prepare for Uninstall. Confirmations for conflict/legacy/Quit Anyway name what remains unknown/changed. Preserve P4’s friendly setting/power-source/capture-time recovery choices, raw detail disclosure and non-destructive defer/dismiss behavior. Preserve the already-truthful status-item recovery/busy/unknown state; this phase does not introduce it for the first time. An ordinary successful action should not add redundant confirmation.
4. Make diagnostics discoverable through a visible labeled control; retain Option-click as an optional shortcut, not sole entry. Timer shows selected frozen intent, actual time remaining and explicit cancel. Buttons/toggles expose names, values, state and appropriate keyboard behavior. Add deterministic focus order/return after setup, dialogs and expanded sections. Test VoiceOver, keyboard-only use, increased text size and standard/light/dark/high-contrast appearance with current supported macOS behavior.
5. Measure rendered text/control contrast; normal text target at least 4.5:1, applicable large text at least 3:1 and meaningful control/focus contrast at least 3:1. Keep brand colors while choosing legible combinations; don't blindly darken every token. Reduce unnecessary motion under accessibility preferences and avoid clipping/overlap at supported text sizes/popover placement.
6. Explicitly align the demo's **options default** with the native default here (BZ-043(d)), record it as intentional parity correction, and mirror the native statuses/action wording. This is not a change to P1's extraction baseline. Demo-only simulation remains visibly a demo.
7. Trace all popover close/deallocation paths and monitor install failure. If an alternate leak is reproduced, give monitor lifetime one clear cleanup owner and test repeated open/close. If normal paths are correct and no reachable defect exists, close the hypothesis with observed/inspected scope. Likewise verify empty Settings reachability before removing the unused scene or wiring an existing needed function; do not invent a settings product merely to fill it. Preserve already-matching icon color unless another measured issue requires change.

## Test Plan

Use pure presentation state tests for labels/actions/focus intent; ordinary tests never run live production initialization. Dedicated-Mac UI acceptance records setup's full text, recovery/quit/conflict states, keyboard traversal, VoiceOver names/values, text-size/contrast screenshots, mixed-profile/mixed-choice recovery with defer/Escape, rendered unknown-hardware option descriptions, timer cancel, popover lifecycle and Settings reachability. Authorized browser checks verify matching states and options default. P8 completes general landing semantics and responsive checks; #43 remains open until both surfaces pass.

## Verification Checklist

- [ ] Full permission/recovery disclosure is readable without clipping and correct for the selected model.
- [ ] Requested/applied/unknown states, restore meaning and timer cancellation are clear in native and demo.
- [ ] Native keyboard/VoiceOver/contrast/text sizing and state-specific UI acceptance are recorded on dedicated hardware.
- [ ] Options-default parity is corrected here; repeated popover/Settings hypotheses are fixed or explicitly dispositioned with evidence.
- [ ] Current-head build/security/behavior checks and independent review pass; user merges.
- [ ] #43 stays open for P8 web completion; #79/#82 close only after every ledger row is resolved/dispositioned.

## What NOT To Do

Do not add new state semantics, hide permission detail in tiny secondary text, claim unsupported physical outcomes, perform a generic style-token rewrite, manufacture a monitor leak, or test power operations on the fleet Mac to obtain screenshots.

## Context

- Source: claudna:forge; area: native UX/accessibility and parity; effort M; risk medium; priority medium.
- Primary issue: #43. Completion rows: #79/BZ-028, #81/BZ-043(d), #82/BZ-048 and qualified BZ-049 disposition.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC07:** Status-item state/accessibility is truthful in P4, with later presentation polish. Document correction independently verified.
- [x] **IC09:** Friendly mixed-profile recovery choices and non-destructive defer/dismiss, with raw detail and ownership meaning. Document correction independently verified.
- [x] **IC13:** Explicit SleepSetting.swift copy ownership and unknown-hardware rendered acceptance. Document correction independently verified.
