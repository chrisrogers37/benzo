---
title: "[enhancement] Show honest read results in existing diagnostics"
type: plan
status: active
owner: claudna:audit
created: 2026-11-02
tags: [enhancement, reliability, "priority:medium"]
repos: chrisrogers37/benzo
---

## Summary

One bounded PR fixes errors presented as empty data, stale refresh results, and unsupported green verification in the existing diagnostics panels. Keep sessions, wake reason, USB and reported settings; present observations without claiming ownership, successful restoration or physical sleep behavior.

This replaces the former P6 supplement scope. Execute after **03 → 01**, independently of conditional [02_recovery-engine.md](02_recovery-engine.md); there is no prerequisite controller, scheduler identity provider, receipt UI, preflight, logging framework or capability-matrix project.

## Evidence

All source references below use pinned main `eed0a969b097142042dc4412424fbc71a04d2c0d`; refresh references at the accepted implementation parent.

- `Benzo/Benzo/Services/DiagnosticService.swift:7–8,63–69` converts command failure, malformed profiler JSON and absent USB datatype to empty collections.
- `Benzo/Benzo/ViewModels/BenzoViewModel.swift:235–249` has no refresh-generation check and reads settings on the main callback; its earlier results can overwrite a later request.
- `Benzo/Benzo/Views/DiagnosticView.swift:149–152` shows “No USB devices connected” for failed reads. Lines 180–181 already show “Could not read settings” for an empty array: this is **not** an empty-array green-summary bug.
- `DiagnosticService.swift:124–131` makes inactive/disabled settings match automatically. `DiagnosticView.swift:205–212` then claims “All settings verified”; `src/landing/NativeAppDemo.jsx:6–21` mirrors that unsupported comparison.
- `Benzo/Benzo/Models/SleepSession.swift:38–43` matches generic `User` before `UserActivity`, giving a specific event the wrong label.

## Implementation Plan

### Dependencies

[03_lifecycle.md](03_lifecycle.md) must be merged first, then [01_command-permissions.md](01_command-permissions.md) with its reusable bounded, nonmutating reader. Shared ViewModel, dependency, composition and demo files require sequential work. Adopt 01's accepted read API; do not introduce a second process runner or async-convert legacy writes as part of diagnostics.

03 explicitly removes the main blocker display, its now-unused state/callback and the active demo's blocker example when it removes their refresh path. This phase does not resurrect those surfaces or require replacement blocker acquisition.

### Blocks

None for deciding whether 02's new manual controls are justified. Truthful diagnostics is a prerequisite for accepting these retained panels, not evidence that remaining manual mutations or recovery are safe. No intermediate native release; the family release gate still applies.

### Steps

1. **Own only the retained diagnostic path.** Modify the following existing files; create no new subsystem or file.

   | Files | Change |
   |---|---|
   | `Benzo/Benzo/Services/DiagnosticService.swift`, `Benzo/Benzo/Services/BenzoDependencies.swift`, `Benzo/Benzo/App/AppDelegate.swift` | Inject 01's reader into remaining diagnostic reads and preserve their success/error outcomes. |
   | `Benzo/Benzo/Models/ServiceTypes.swift`, `Benzo/Benzo/Models/SleepSession.swift` | Small diagnostic error/observation types and the specific wake-label correction. |
   | `Benzo/Benzo/ViewModels/BenzoViewModel.swift`, `Benzo/Benzo/Views/DiagnosticView.swift` | Per-dataset loading/result state, stale-result rejection and neutral existing panels. |
   | `Benzo/BenzoTests/BenzoCoreTests.swift`, `Benzo/BenzoTests/TestDoubles.swift`, `Benzo/Benzo.xcodeproj/project.pbxproj` | Existing fake/fixture tests; add the now-injected `DiagnosticService` to the unhosted test target without live adapters. |
   | `src/landing/NativeAppDemo.jsx`, `src/landing/NativeAppDemo.test.jsx`, `src/demo/useBenzoDemo.js`, `src/design/appPresentation.js` | Active simulation parity and focused result fixtures using its existing single state. |
   | `CLAUDE.md`, `AGENTS.md`, `src/design/README.md` | Update touched parity/diagnostic descriptions if 03/01 have not already corrected them; name the active route and preserve historical files. |

2. **Carry read failure through the existing service.** Replace `try? ... else { return [] }` and `( [], nil )` fallbacks in `fetchUSBDevices`/`fetchSleepData` with `Result<Payload, DiagnosticReadError>`; define the error in `ServiceTypes.swift` with command failure, incomplete capture and unsupported/malformed format cases. Reuse 01's bounded outcome details for command failures; UI reasons are concise, without raw command output. Keep `Foundation`; no new imports are needed beyond 01's accepted reader boundary.

   ```swift
   // Before: command failure masquerades as a successful empty dataset.
   guard let json = try? ShellExecutor.runDirect("/usr/sbin/system_profiler", ["SPUSBDataType", "-json"]) else { return [] }
   // After: payload contract; completion/async syntax follows the accepted 01 API.
   typealias USBRead = Result<[USBDevice], DiagnosticReadError>
   // Complete, supported empty capture => .success([])
   // Failed, timed-out, truncated or unrecognized capture => .failure(...)
   ```

   Sleep sessions and last wake reason share one capture/result. Extract parsing into static pure functions within `DiagnosticService` so the production parser is exercised with strings. A valid supported USB structure containing no devices is empty; absent datatype is unavailable. Malformed entries or discarded malformed sleep-event candidates fail that dataset as incomplete; do not present a subset as complete. Preserve the five-session bound and missing battery values. An unrecognized log format cannot prove zero events; require a fixture-supported format before showing an empty result. Match `UserActivity` before generic `User` in `SleepSession.humanReadableReason`.

3. **Show current observations instead of verification.** Rename `verifySettings(settingStates:isActive:)` to `readObservedSettings` and `SettingVerification` to `ObservedSetting` in all production/fake consumers. The row contains `key` and optional `actualValue`, with `id` derived from `key`; it has no `expectedValue` or `matches`. Read the same current `pmset -g` scope via 01's bounded reader and parse only the existing `SleepSetting` keys; missing keys say “Not reported”, and no recognized keys means unavailable. This is an observation of the command's current scope, not a per-profile ownership check.

   ```swift
   // Before: matches: !isActive || !enabled || actual == targetValue
   // After: ObservedSetting(key: key, actualValue: state.value(for: key))
   // Panel: "Current Settings"; summary: "Reported by pmset. Changes are not verified."
   ```

   Remove check/cross badges, expected-value comparison, “drifted” and green “All settings verified” from this panel and active demo. Changing preferences or activity state must not change an already-observed value. This plan does not infer any expectation from an unresolved legacy backup or add 02's controller contract.

4. **Prevent stale presentation with one refresh generation.** On `loadDiagnostics`, increment a main-owned generation, clear the previous datasets, and mark each retained dataset loading. Perform every read, including settings, off the main/UI execution context through the injected 01 boundary. Publish each dataset separately on the main boundary only if its captured generation still matches; one failure must not erase another dataset's fresh result. Ignore obsolete completion entirely, including loading flags. Keep existing on-appear refresh/back navigation; add no polling, refresh control or cancellation framework.

5. **Render each existing panel from its result first.** A failed USB read says “Could not read USB devices”; a supported successful-empty read says “No USB devices reported”. Sessions use “Could not read sleep history” versus “No sleep sessions reported”; wake reason shares the sleep-read failure and otherwise retains “Unknown” when no reason was reported. Settings use “Could not read settings” on failure. Reopening diagnostics retries using the existing on-appear path. No failed/new refresh displays prior rows as current. Mirror copy and result behavior in the active `NativeAppDemo`/`useBenzoDemo`/`appPresentation` path; retain `BenzoHybrid`, `BenzoMockup`, legacy fixtures/state and historical tests.

## Test Plan

Extend existing `BenzoCoreTests` and `TestDoubles`: supported-empty versus command failure/timeout/truncation; malformed/absent USB datatype; malformed sleep candidate versus valid no-event capture; missing battery/reason; specific `UserActivity` label; observed values unchanged by active/disabled preferences; missing settings keys; one dataset failure with other successful results; and two refreshes completed in reverse order. Use injected readers and held queues; no production defaults, host commands or new test framework. Adjust `testDiagnosticsAndTerminationUseInjectedCallbacks` to assert that UI publication callbacks perform no command reads, rather than preserving its current main-thread read count.

Extend `NativeAppDemo.test.jsx` with success-empty/failure fixtures and neutral observed-settings assertions using the existing simulation seam; add no user-facing fault controls. On the implementation head, run the existing required checks once: Node from `.nvmrc`, `npm ci`, `npm test`, `npm run build`, `npm audit --audit-level=moderate`; full-Xcode Debug/Release builds and unhosted `BenzoCoreTests` using README's task-owned DerivedData commands; and required Gitleaks CI. No new validation harness, matrix or repeated baseline/head sweep is required. Authorized browser/native presentation checks cover changed panel text and loading/error layout; native observation requires an approved dedicated Mac. Missing lanes remain open.

## Verification Checklist

- [x] Accepted 03/01 parent and all `fetchSleepData|fetchUSBDevices|verifySettings|SettingVerification|loadDiagnostics` callers are reconciled.
- [x] Production reads use 01's bounded runner; malformed/incomplete/unavailable data never becomes successful empty.
- [x] Old refreshes cannot overwrite current results; failure never presents prior values as current.
- [x] Settings are neutral observations with missing values visible; no preference-derived verification remains in the active native/demo route.
- [ ] Focused fake/fixture tests, existing required checks and changed-panel parity evidence are recorded at the implementation head.
- [x] No claim of recovery completion, physical sleep behavior or native release acceptance is inferred from these results.

## What NOT To Do

Do not rebuild timers, blocker identity or scheduler safety; add a receipt/preflight/history/logging/capability system; cache results; add broader USB datatypes; or change legacy apply/restore/authorization behavior. Do not perform native launches or host power, permission, login, install/uninstall or blocker actions on the protected fleet host. Do not require 02 before fixing these read-only panels.

## Context

- Source skill: claudna:audit; revision date: 2026-11-02; area: retained diagnostics; effort: Medium; risk: Medium; priority: Medium.
- Family scope: [00_TECH_DEBT.md](00_TECH_DEBT.md). Old canonical P6 remains historical context only where behavior is retained.
- Historical receipt: the prior audit reported Node 24.22.1 install, 33 web tests, build and moderate audit passing; no full-Xcode/native pass. None was rerun for this document revision, and none proves future implementation acceptance.

## Review of the YAGNI revision

On November 2, 2026, two independent subagents performed targeted safety and YAGNI verification of all seven revised documents against the accepted scope and source snapshot `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both returned **NO FINDINGS**. This follows the earlier five-angle review that recommended narrowing; it is not a new broad audit.

The verification confirmed the bounded scope of existing diagnostic reads, distinct failure/empty states, stale-completion rejection and neutral observed values without a new diagnostics product.

This verdict concerns the revised documents. Implementation, authorization feasibility, native acceptance and release remain unverified; the unchecked implementation gates remain open. No application tests, native actions or network operations were performed by these two reviewers.

## Implementation checkpoint — November 3

Implementation parent is merged phase 01 `a763f95d25410cd6ff174ba4b720fe3386a1c1d7`. A fresh read-only comparison confirmed the existing async `ReadCommandRunning` boundary supports this scope without another runner or a legacy-write conversion. Native and active-demo owners are implementing the listed files; parser fixtures are synthetic and do not claim dedicated-device acceptance. Required checks and independent review remain pending.

Local verification: Node 24.22.1 passed 45 web tests, build and moderate audit (zero vulnerabilities). All app Swift sources pass CLT typechecking; 11 new XCTest methods were added but full XCTest execution awaits CI. Eleven synthetic parser/injected-read/obsolete-publication smoke scenarios passed outside the app. Independent native and web reviewers returned no remaining findings after tab-message parser validation and optional-value demo corrections. Reuse, Altitude, Efficiency and Simplification review found no further justified changes. Targeted screenshots cover the canonical successful panel and synthetic result states mounted with the existing component; these are browser evidence, not native acceptance.
