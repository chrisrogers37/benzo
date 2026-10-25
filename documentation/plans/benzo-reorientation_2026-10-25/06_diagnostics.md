---
title: "[plan] P6 — Truthful diagnostics and local operation receipts"
type: plan
status: draft
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-25
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size M, risk medium. Present read-only preflight, configuration evidence, errors and last-operation receipts without implying physical sleep success. One PR on `codex/benzo-diagnostics` completes the useful local observability scope; no export/history/telemetry product is added.

## Evidence

At the research base `DiagnosticService.swift:23,79,107` converts command failures into empty collections; P5 must already fix the blocker subset and its identity/freshness contract before this phase; `:140–146` calls inactive/disabled settings matches. `SleepSession.swift:36` checks generic User before UserActivity. USB Apple Silicon and broad log-format failures remain unverified hypotheses, not proven universal defects. Existing service already supplies bounded sessions, blockers and USB data; extend its error/state contract instead of building an analytics system.

## Implementation Plan

### Dependencies

P5 merged; C1–C9 state/receipt and read-only lifecycle contracts in place.

### Blocks

P7 accessible presentation and final P8 trust claims; completion of #72 diagnostic test scope and #79 capability item.

### Steps

1. **Own files:** `Services/DiagnosticService.swift`, `Models/SleepSession.swift`, `Models/USBDevice.swift`, new `Models/DiagnosticResult.swift`, `Views/DiagnosticView.swift`, `ViewModels/BenzoViewModel.swift`; operation logging integration in runner/coordinator; native fixtures/tests and extracted demo/state/fixtures/tests; new `documentation/support/capability-matrix.md` and support guidance in README.
2. Extend the typed blocker snapshot/provider delivered by P5; do not replace it with a separate reader or weaken its freshness/identity failures. Replace the remaining empty-on-error returns with a typed result such as `DiagnosticResult<Value> { status: success|empty|partial|failure|unknown, value, capturedAt, warnings, error }`. Distinguish permission denial, timeout, unsupported data and successful empty data. Collect independent datasets independently so one failed profiler call does not erase valid blockers/sessions. Tag results with generation and discard stale data as P5 requires.
3. Replace `matches: !isActive || !enabled || actual == targetValue` with verification categories `verified`, `mismatch`, `notOwned`, `notApplicable`, `unknown`. Only a validated owned-cell expectation may be verified. Show expected/actual profile/key/time and pending recovery; disabled/untouched is not verified. A physically unsupported outcome cannot become green because a write returned zero.
4. Extract existing log parsing into pure helpers; match specific wake tokens before generic User, and give unmatched/malformed inputs bounded diagnostic warnings. Fixtures cover supported timestamps/tokens, missing batteries and malformed lines; retain the five-session limit. Do not add arbitrary formatter caching absent measured need. For USB, reproduce representative profiler outputs and label scope exactly; add another data type only if evidence justifies it. Empty/unsupported/error remains visible.
5. Build a read-only preflight view model from selected scope, permission status, pending recovery, current blockers and capability evidence. F3 hardware matrix records OS/chip/power-source/dock, observed setting support and **separate** measured physical outcome. Unqualified combinations display unknown. Process labels use friendly names plus useful identity; do not hide ambiguity or automatically kill them.
6. Surface the last operation receipt already produced by P4: operation identity/time, profile/setting changes, verified/partial/unresolved result and a recovery action. Use local structured `os.Logger` categories for command/permission/journal/recovery failures, with privacy redaction of raw command output, user paths, host fingerprint, device/process names and unrelated logs. Keep only the one last resolved receipt from C3; do not add a successful-session archive. No custom signal handler, crash collector, upload, persistent history store or export button. Document that these logs are not proof of crash-stack collection or durability beyond the journal.
7. Mirror result categories, friendly blocker labels, capability unknown and operation receipt in the demo. Record explicit BZ-029/BZ-032 hypothesis dispositions based on actual fixtures/hardware evidence rather than quietly marking universal claims fixed.

## Test Plan

Pure fixtures: error versus empty, independent partial results, inactive/disabled/untouched versus verified, stale result discard, UserActivity/power-button ordering, each supported log format plus malformed/unmatched input, known USB JSON and missing datatype, unknown capability, receipt/result details and logging redaction. Review bounded output/time handling inherited from P3; no repeated unbounded system_profiler reads.

Dedicated-Mac representative captures qualify claimed log/USB/hardware coverage. A synthetic fixture proves parser behavior for that sample, not universality. Browser/native presentation tests must expose errors and recovery without requiring every dataset. Run P1 gates and parity tests; no physical claim is accepted from mocks.

## Verification Checklist

- [ ] Error/empty/partial/unknown states remain distinguishable end to end.
- [ ] Only owned validated expectations receive verified status; inactive/disabled values do not appear restored or physically proven.
- [ ] Wake ordering and documented format fixtures pass; USB/capability hypotheses have evidence or explicit narrowed scope.
- [ ] Preflight is read-only, receipt reflects P4 data, and local logs avoid sensitive/default raw content.
- [ ] All five #78 rows and #79/BZ-031 have explicit outcomes; #72 closes only when all prior behavior contracts also pass.
- [ ] Current-head checks, native/demo parity and independent review pass; user merges.

## What NOT To Do

Do not infer physical hibernation, USB power or battery causation from configuration; make failed commands look like no blockers; build remote crash reporting, exports/history or custom signal handlers; or treat one Apple Silicon fixture as all-machine support.

## Context

- Source: claudna:forge; area: diagnostics/preflight/local receipts; effort M; risk medium; priority medium.
- Primary issues: #76, #78. Shared #72, #79/BZ-031, #81/BZ-043(c). #37 closes only as explicitly re-scoped, not crash-stack acceptance.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC03:** Moved real typed/fresh blocker identity parser/provider into P5; P6 extends it. Document correction independently verified.
- [x] **IC10:** Bounded one resolved receipt plus necessary unresolved generations/legacy evidence; safe pruning and retention disclosure. Document correction independently verified.
