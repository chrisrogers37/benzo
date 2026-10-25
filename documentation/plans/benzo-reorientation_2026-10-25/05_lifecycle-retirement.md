---
title: "[plan] P5 — Lifecycle, cancellation and safe retirement"
type: plan
status: draft
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-25
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size L, risk high. Route app lifecycle, timer, login state and uninstall preparation through the P4 recovery boundary. One PR on `codex/benzo-lifecycle-retirement` removes hidden reapplication and unrelated blocker termination under F1, and makes graceful quit/recovery limits explicit under F5.

## Evidence

`BenzoViewModel.swift:117` swallows restore failure before exit, `:142` queues uncancellable delayed sleep, `:160` timer survives deactivate/restore, `:192` can apply stale drift results, and `:313` can leave login binding ahead of OS state. `AppDelegate.swift:102` triggers drift on open and has no termination hook. `PMSetService.swift:82` broadly calls pkill. `Casks/benzo.rb:14,17` removes the grant and zaps recovery storage without verified restoration prerequisites.

## Implementation Plan

### Dependencies

P4 merged and real recovery acceptance passed. F1/F5 accepted. C8 is normative; C4 remains the sole write path.

### Blocks

P6–P8 and any public release of the new controller. #79 remains open through P6 capability and P7 popover disposition.

### Steps

1. **Own files:** `App/AppDelegate.swift`, `App/BenzoApp.swift`, `ViewModels/BenzoViewModel.swift`, `Services/PMSetService.swift`, `Services/OperationCoordinator.swift`; new `Services/SleepScheduler.swift`, `Models/BlockerSnapshot.swift`, `Services/UninstallPreparation.swift`; extend P1 `LoginItemClient`/live adapter and existing `Services/DiagnosticService.swift`/`SleepBlocker` model for the production blocker provider; `App/Main.swift` only after Homebrew consumer feasibility is demonstrated; `Views/SleepNowButton.swift`, `Views/FooterView.swift`, recovery presentation; `Casks/benzo.rb`; native lifecycle/scheduler tests; extracted demo/state/tests; README lifecycle/uninstall docs.
2. Replace `verifyAndCorrectSettings()` with read-only reconciliation; popover open, startup and wake never write. Tag diagnostic/drift results with generation/capture identity and discard stale completions. An off/restore/new operation wins over older work. Rename callers in `AppDelegate`; no hidden auto-repair remains.
3. Route footer and AppKit Quit through `applicationShouldTerminate` with `terminateLater` and the shared coordinator. Immediately invalidate scheduled sleep, settle current operation, restore/verify owned cells, then `reply(toApplicationShouldTerminate: true)`. On failure/conflict show Retry, Stay Open, Quit Anyway; the last preserves journal and warns settings may remain changed. Repeated termination requests must not start duplicate restores. Handle logout/shutdown as best-effort AppKit lifecycle with next-launch recovery; never promise SIGKILL restoration.
4. Replace timer/delay callbacks with an injected `SleepScheduler` holding frozen selected intent, generation, expiry and observed blocker identities. Scheduling displays its scope. Off, Restore, Quit, new schedule, selection edits and recovery failure cancel/clear it and increment generation. Observe system sleep notifications too: any system sleep invalidates the timer and queued expiry; wake never runs an overdue timer. At expiry revalidate generation, permission, capture and blockers under the coordinator; new/unknown blocker data cancels into needs-user-action, never kills. Existing blockers at scheduling must be visible in the explicit confirmation. Manual sleep presents blockers and can request sleep explicitly without terminating them. Remove `killCaffeinateProcesses` and the half-second delay; verified configuration readiness replaces the delay. Journal sleep intent and never replay it after restart.

   **Production blocker prerequisite in P5:** define `BlockerSnapshot(capturedAt, completeness, assertions, error)` and stable observed assertion/process identity from available reported assertion ID/type/owner PID plus process incarnation/start evidence when obtainable. A generated UI UUID, friendly name or PID alone cannot establish unchanged identity. If supported output cannot establish sufficient identity, mark unknown and cancel scheduling/expiry conservatively. Capture must be successful, complete and fresh at schedule/fire (take a new capture immediately before expiry decisions under the coordinator); failure, stale generation, partial/truncated/malformed output or unparseable identity cancels into needs-user-action. Preserve successful empty separately. Same reported assertion/process unchanged may remain, disappearance is allowed, new assertion or same-name process replacement cancels. Implement this in the actual `DiagnosticService` parser/adapter and have scheduler consume that provider, not a second reader or rich fake over an old production API. P6 extends its presentation and other datasets.

   **Demo behavior in P5:** implement the injected fake clock, selected frozen intent, actual selected-duration countdown and all cancel/system-sleep/unknown-blocker states now, with deterministic reducer/clock tests. P7/P8 only polish and reverify; no hard-coded countdown or postponed behavior remains.
5. Extend the P1-injected `LoginItemClient` to read `SMAppService` status after success or failure. UI shows pending/error/observed state rather than a bound optimistic Boolean. Keep registration explicit and preserve no-op reads on startup. Mirror lifecycle, timer cancellation, blocker and login states in the demo immediately.
6. First verify the current supported Homebrew hook can run before app removal and abort uninstall reliably, using documentation plus an owned harmless fixture. Record the consumer proof before committing to a new native entrypoint. Add explicit **Prepare for Uninstall**: cancel work, require execution quiescence, restore/verify owned changes, then explicitly remove Benzo's grant through the root-serialized prior-owner retirement path, verify retirement and record a bounded ready receipt. Any failure retains prerequisites/evidence and blocks “ready.” Only if the hook/abort consumer is feasible, add a read-only `--check-uninstall-ready` entry that loads validated journal/retirement status and returns failure if recovery or grant retirement remains unresolved; it must never initialize live UI or mutate. If SwiftUI startup needs splitting, remove `@main` from `BenzoApp` and use a small `Main.main` that handles only this exact argument before otherwise calling `BenzoApp.main()`; no general control CLI is added. Test this routing independently.
7. With that consumer proof, make cask uninstall invoke the preflight before removing app files. Remove unconditional grant deletion and prevent zap from deleting unresolved/original evidence; simplest policy preserves the recovery directory during zap and documents explicit post-resolution cleanup. A fresh never-configured install may pass after read-only validation; a user can reopen the app to prepare retirement. Direct-DMG removal uses the same in-app path and documented manual app removal. If Homebrew cannot reliably abort before app removal, do not add the CLI entry; preserve grant/recovery prerequisites, keep the direct-DMG/in-app preparation route, and leave #75 open with the exact unsupported ordering/abort limitation; do not invent a guarantee or delete the cask to close #75.

## Test Plan

Deterministic fake-clock/interleaving cases: Off/Restore/Quit/config edit before expiry, callback already queued, stale drift result after new state, timeout while quitting, repeated Quit, failed compensation and Quit Anyway receipt, cancellation while setup pending, new/unknown blocker at expiry, production parser/adapter-to-scheduler failure/partial/truncation/malformed/stale cases, unchanged assertion, same-name replacement/new assertion and disappeared assertion, frozen timer selection, system sleep initiated elsewhere and queued expiry crossing sleep/wake, functional demo selected-duration/countdown/cancel, no timer restored at launch, ambiguous sleep receipt not replayed. Assert no fake pkill and no write outside coordinator. Login tests check denial/status readback. Uninstall tests fail closed on pending same-boot execution fence, unresolved/corrupt/missing-with-legacy state, failed grant retirement, and unsupported entry arguments.

Dedicated-Mac evidence: actual app Quit/logout behavior and failure UI; login registration/readback; timer cancellation and explicit sleep/wake; direct-DMG retirement and current Homebrew uninstall/zap ordering. Capture a baseline and preserve recovery evidence. No fleet-host sleep, grant removal or login tests. Run P1 gates and parity tests.

## Termination evidence matrix

Every row requires its own receipt for #53; an unexercised dedicated row remains outstanding. “Next launch” first honors the execution fence, then reconciles read-only when quiescence permits. None authorizes fleet-host termination/restart tests.

| Trigger | Immediate expectation | Next-launch expectation / retained evidence | Evidence lane |
|---|---|---|---|
| Footer Quit | Shared deferred quit cancels timer, settles operation, restores/verifies or offers failure choices | Resolved receipt on success; journal/fence retained on Quit Anyway/uncertainty | Fake interleaving plus dedicated native UI |
| Cmd+Q / AppKit Quit | Same `applicationShouldTerminate` route; no duplicate restore | Same as footer; no separate best-effort path | Fake repeated requests plus dedicated keyboard/AppKit |
| Force Quit / SIGKILL | No callback/restoration guarantee | Preserve durable original/intents/fence; same-boot unknown writer blocks mutation/release | Synthetic owned child/restart, then separately approved dedicated native |
| Logout | Cancel timer and attempt AppKit deferred path; OS may force termination | Preserve unresolved journal/fence if completion not proven | Dedicated authorized account lifecycle; outstanding until exercised |
| Restart | Best-effort graceful path only; never initiated by Benzo | Verified later boot clears execution-liveness uncertainty only, then read-only reconciliation; no replay/auto-restore | Boot-identity fixtures plus separately approved dedicated restart |
| Simulated crash | Abrupt exit at each recorded boundary, including after launch before child identity | Retain original/intents and prevent surviving writer race/PID reuse release | Fault-injected core plus bounded owned-process/dedicated receipt |

## Verification Checklist

- [ ] No startup/popover/wake path silently applies settings; stale completions cannot change newer state.
- [ ] All timer/delayed writes are invalidated by canceling actions and checked immediately before side effects.
- [ ] No automatic blocker termination remains; explicit sleep is honestly reported as requested, not physically proven.
- [ ] Graceful termination choices and next-launch recovery pass dedicated-Mac acceptance without swallowed failure.
- [ ] Login truth and restore-before-grant-retirement/uninstall behavior are observed on dedicated hardware; cask ordering is proven or #75 remains open with a concrete blocker.
- [ ] Native/demo behavior, exact-head checks and independent review pass; user merges and relevant resolved issues close only with evidence.

## What NOT To Do

Do not duplicate restore logic in AppDelegate, footer or cask; delete the only journal; claim an exited process's timer persists; kill other fleets' blockers; create a broad public CLI; remove permission while recovery remains unresolved; or treat process exit callbacks as a crash guarantee.

## Context

- Source: claudna:forge; area: lifecycle/scheduling/retirement; effort L; risk high; priority high.
- Primary issues: #53, #56, #61, #68, #74, #75, #79. Shared #36, #81/BZ-043(a); capability/popover rows intentionally finish later.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC03:** Moved real typed/fresh blocker identity parser/provider into P5; P6 extends it. Document correction independently verified.
- [x] **IC04:** Added pre-launch durable execution fence, restart/PID gap rules and verified later-boot escape; ownership/retirement remain blocked while uncertain. Document correction independently verified.
- [x] **IC05:** Root controller UID compare-and-install, refusal/handoff, legacy ownership boundary and concurrent-account acceptance. Document correction independently verified.
- [x] **IC06:** System sleep invalidates timer/queued expiry; wake never fires overdue work. Document correction independently verified.
- [x] **IC08:** Functional demo clock/frozen intent/countdown/cancel moves to P5. Document correction independently verified.
- [x] **IC16:** Prove Homebrew preflight/abort consumer before adding CLI; preserve evidence and unresolved issue if unsupported. Document correction independently verified.
- [x] **IC17:** Added per-trigger immediate/next-launch/journal/evidence-lane termination matrix. Document correction independently verified.
