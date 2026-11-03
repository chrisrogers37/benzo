---
title: "[safety] Prepare bounded reads and truthful permission observation"
type: plan
status: draft
owner: claudna:audit
created: 2026-11-02
tags: [safety, security, performance, "priority:high"]
repos: chrisrogers37/benzo
---

## Summary

One PR adds a reusable bounded read runner and replaces misleading permission readiness with nonmutating observation. It removes the setup/install entrypoint; the existing legacy grant remains untouched. It does not install a temporary exact `-a` policy, controller manifest, ACL, helper or new standing grant. Explicit per-operation authorization is the default to evaluate for conditional [02](02_recovery-engine.md), with transport feasibility settled before implementation.

Execute **03 containment → 01 preparation → 04 retained diagnostics → conditional 02 final manual control**. This replaces the former P3 supplement and its intermediate migration architecture. 01 prepares read-side F3 handling; 04 adopts it in diagnostic callers. Existing synchronous capture/apply/restore/quit remains isolated, unresolved and unreleased until 02 replaces its whole operation boundary. Packaging does not delay source containment; no partial native safety slice is a release candidate.

## Evidence

Source references are repository-relative at pinned main `eed0a969b097142042dc4412424fbc71a04d2c0d`; refresh them on 03's merged parent.

| Source | Current gap |
|---|---|
| `Benzo/Benzo/Services/ShellExecutor.swift:76–94` | One shared pipe is drained after `waitUntilExit`; output can deadlock and execution/draining has no deadline. |
| `Benzo/Benzo/Services/ShellExecutor.swift:11–32,63–69` | Existence/defaults imply readiness; probe executes `sudo -n pmset -g`, absent from its generated write grant. |
| `Benzo/Benzo/Services/ShellExecutor.swift:39–58,124–131` | Setup/removal invokes privileged AppleScript; generic exit 1 is treated as cancellation. |
| `Benzo/Benzo/ViewModels/BenzoViewModel.swift:71–80,255–299` | Setup offers Boolean success; legacy mutations span capture/persistence/multiple writes without complete admission or recovery proof. |
| `Benzo/Benzo/Services/DiagnosticService.swift:8,64,118` | Retained panels execute synchronous log/USB/current-setting reads; settings verification constructs its own live runner. |
| `Benzo/Benzo/Services/BenzoDependencies.swift:3–13,39–54` | Existing injected seams can preserve legacy mutations while a separate read-only capability is introduced. |

The prior audit reported 33/33 web tests, build and npm audit passing on this snapshot. This is historical evidence, not a test run or native acceptance for the rewritten plan.

## Implementation Plan

### Dependencies

03 must be merged first, with automatic mutation, timed sleep, blocker actions and manual Sleep Now removed/disabled. Reconcile current source and owned status; preserve 03's selection freeze and evidence/grant retention. No parallel implementation on shared ViewModel/dependency/demo files. The earlier P2-before-P3 schedule and C7 standing-grant design are superseded by the accepted rescope.

### Blocks

04 consumes this runner and nonmutating observation without gaining write capability. Conditional 02 must reuse this process engine, integrate safe authorization and resolve all retained manual mutation defects before a native release. If new persistent control is unjustified, scope safe legacy recovery/read-only support explicitly; these preparatory PRs cannot silently become the final release.

### Steps

1. **Use this bounded file map.** Native shorthand is relative to `Benzo/Benzo/`; no generic permission framework.

   | Files | Change |
   |---|---|
   | New `Services/CommandRunner.swift` | Request/result types, fixed read requests and one Foundation process engine. |
   | New `Services/PermissionObservation.swift` | Nonmutating observation of the known legacy rule location; no authorization decision. |
   | `Services/ShellExecutor.swift`, `Services/BenzoDependencies.swift`, `ViewModels/BenzoViewModel.swift`, `App/AppDelegate.swift` | Retire misleading probes/setup callbacks; inject observation while retaining legacy synchronous mutation transport. |
   | `Views/SetupView.swift`, `Views/PopoverContentView.swift` | Replace Grant Permission with read-only status refresh and explicit unverified/unknown copy. |
   | New `Benzo/BenzoTests/CommandRunnerTests.swift`, `Benzo/BenzoTests/PermissionObservationTests.swift`, `Benzo/BenzoTests/Fixtures/owned-read-child.sh`; existing `Benzo/BenzoTests/BenzoCoreTests.swift`, `Benzo/BenzoTests/TestDoubles.swift`, `Benzo/Benzo.xcodeproj/project.pbxproj` | Targeted transport/observation coverage in the existing unhosted suite; correct source/fixture membership. |
   | `src/demo/useBenzoDemo.js`, `src/landing/NativeAppDemo.jsx`, `src/landing/NativeAppDemo.test.jsx`, `src/landing/BenzoLanding.test.jsx`, `src/design/appPresentation.js`, `src/design/siteCopy.js`, `README.md`, `AGENTS.md`, `src/design/README.md` | Mirror observation-only setup and document the narrow fixture-test exception and release hold. |

2. **Keep one read engine with a small contract.** Add the following detailed skeleton in `CommandRunner.swift` (names are proposed, not existing declarations):

   ```swift
   enum ReadCommand { case currentSettings, sleepLog, usbDevices }
   protocol ReadCommandRunning {
       func run(_ command: ReadCommand) async -> CommandOutcome
   }
   struct CommandOutcome {
       let stdout: Data
       let stderr: Data
       let termination: Termination
       let outputComplete: Bool
       let outputTruncated: Bool
       let directChildStopped: Bool
   }
   enum Termination {
       case exited(Int32), signaled(Int32), timedOut, cancelled, launchFailed(String)
   }
   ```

   `CommandRunner` conforms to `ReadCommandRunning`; map only to `/usr/bin/pmset -g`, `/usr/bin/pmset -g log`, and `/usr/sbin/system_profiler SPUSBDataType -json`. Internally use one executable/argv request implementation, with no shell interpolation. Expose no privileged/general-command capability to diagnostic consumers. 02 reuses this engine through its final authorized-operation adapter; it must not create a second runner. Keep Foundation here and AppKit/ServiceManagement at existing app boundaries.

3. **Bound launch, both streams and finalization.** Drain stdout/stderr concurrently from launch without blocking the main actor. Use total budgets of 10 seconds/8 MiB combined captured output for pmset reads and 30 seconds/16 MiB for system_profiler, reserving finalization time inside each budget. Cap retained bytes while continuing bounded drain/discard; deadline/cancellation closes owned read endpoints and returns incomplete evidence without waiting indefinitely for descendant-held writers. Terminate only an owned synthetic/direct child when permitted; never kill arbitrary processes/groups. Preserve exit code, signal, launch failure, timeout, cancellation and incomplete/truncated output distinctly. A completed read requires exit 0 plus complete, untruncated output; do not discard stderr on failure.

   This API's bounded return and `directChildStopped` are **not** proof of privileged foreground-chain completion. No mutation fence can be cleared from these fields. The reusable engine is preparation only; 02's actual supported authorization transport must establish its own reviewed completion/uncertainty semantics using this engine.

4. **Do not async-convert legacy operations.** Leave `CommandRunning`, `ShellCommandRunner` and `PMSetService.readCurrentState/applySettings/restoreValues` synchronous within the unreleased legacy mutation chain. In particular, do not replace activation's capture read with an `await` while writes still lack whole-operation admission. Do not insert a semaphore bridge, token-per-child substitute, interim mutation fence or temporary policy. 04 changes only diagnostic readers; classify every remaining `ShellExecutor`/`runDirect` caller explicitly as legacy mutation transport or a read migration target. F3 is not fully closed by 01 or 04.

5. **Observe permission evidence without asserting readiness.** In `PermissionObservation.swift`, define `PermissionObservation { case noLegacyRule, legacyRulePresent, unknown(String) }`. Inspect the known `BenzoPaths.sudoers` path using injected metadata access; confirmed absence means no legacy rule, an ordinary existing rule means presence only, unreadable/ambiguous/substituted metadata means unknown. Do not require privileged file reads or create directories/files. These cases never mean authorized, correctly scoped, safe to mutate or safe to remove; other sudo configuration may exist and is not inferred.

   Replace `isSetupComplete`/`needsSudoersUpdate` dependency closures with `observePermission: () -> PermissionObservation`. Automatic startup and explicit `refreshPermissionObservation()` only observe; `.manual` remains free of startup work. Remove `sudoersRuleFunctional()` and its executing `sudo -n pmset -g` probe. Delete unused version-based readiness checks, installer/remover/build-rule methods and callbacks after caller search; retain existing saved version/originals and never uninstall a host rule as cleanup. No new grant is created by this PR.

6. **Remove misleading setup authorization.** Replace `runSetup()` with the nonmutating refresh above; remove `needsSetup` and its Boolean success path. Add `@Published private(set) var permissionObservation: PermissionObservation = .unknown("Not checked")` and `@Published var showPermissionStatus = true`; automatic startup refreshes the observation, while manual startup keeps the injected-test boundary. `PopoverContentView` uses `showPermissionStatus` solely for navigation. `SetupView` displays “No legacy permission rule found”, “Legacy permission rule found; authorization is unverified”, or “Permission status could not be determined”, with “Refresh status” and “Back” buttons. Back sets `showPermissionStatus = false` and changes no permission or active state. 02 defines future per-operation prompts. Keep disabled Sleep Now and frozen selections from 03, and label surviving manual controls unreleased in development/release notes; observation must not make them appear accepted or newly enabled.

7. **Mirror the active route and hand off exactly once.** Update `NativeAppDemo`/`useBenzoDemo`/`appPresentation` to simulate the same three evidence states and refresh/back actions without a Grant Permission success transition. Keep one demo state owned by `BenzoLanding`; preserve historical `BenzoHybrid`/`BenzoMockup` and their tests. Extend 03's corrected guidance with the observation-only distinction. 04 adopts `ReadCommandRunning` in retained diagnostics and owns errors/empty/freshness presentation; 01 does not add preflight panels or a new logging/receipt UI.

## Test Plan

Implementation tests use the existing unhosted suite with explicit fakes, scratch paths and a single owned child fixture. No app/native execution or tests occur in this planning pass. The process engine alone may compile into tests for fixture execution; production adapters, AppDelegate, real sudo/pmset/osascript and login composition remain excluded. Make this narrow exception explicit in `AGENTS.md` and Xcode membership, rather than silently violating existing isolation guidance.

| Focused case | Required assertion |
|---|---|
| Simultaneous >1 MiB stdout/stderr; nonzero/signal/launch failure; cap/EOF | No deadlock; separate evidence and exact outcome; incomplete/truncated never becomes success. |
| Timeout/cancel and owned child exiting while its fixture descendant retains pipe writers | Total deadline plus recorded test tolerance holds; fixture teardown affects owned children only; no quiescence claim. |
| Fixed read request mapping | Exact absolute executable/argv/budget; diagnostics cannot request sudo, shell, writes or sleep. |
| Missing/present/unreadable/substituted legacy-rule metadata | Correct non-authorizing observation; no command launch, prompt, persistence or file mutation; saved legacy data unchanged. |
| Automatic/manual startup and refresh/back UI | Zero install/repair/removal; manual startup does no observation; refresh does not change active/requested settings. |
| Async read held while legacy action code is inspected | No async diagnostic result can invoke apply/restore/setup; no new await enters a legacy capture-to-write operation. |

Use source review/caller search for `CommandRunning|ReadCommandRunning|ShellExecutor|runDirect|installSudoersRule|needsSudoersUpdate|runSetup` and classify each surviving path. Preserve targeted existing tests rather than add a new harness. On the completed implementation run Node 24 `npm ci`, `npm test`, `npm run build`, `npm audit --audit-level=moderate`, README's full-Xcode Debug/Release builds and `BenzoCoreTests` with task-owned DerivedData, plus exact-head existing Gitleaks CI. Browser checks of observation states require authorized browser access; no fixture demonstrates native authorization. Missing evidence remains unchecked.

## Verification Checklist

- [ ] Merged 03 parent and exact-head required checks recorded; old receipts remain historical.
- [ ] Read runner is bounded for both streams, caps, cancellation and inherited writers; one reusable engine exists.
- [ ] Permission observation never executes a privileged probe or installer and never claims readiness.
- [ ] No temporary `-a` grant, standing-grant/ACL/manifest implementation or destructive migration added.
- [ ] Legacy mutation calls remain isolated, synchronous and explicitly unreleased; no unsafe await-before-write bridge introduced.
- [ ] Active demo and contributor guidance match; focused coverage and independent review complete.
- [ ] F3 mutation-chain completion and 02 authorization/recovery feasibility remain open entry gates.

## What NOT To Do

Do not grant `pmset -g` to fix the probe mismatch, equate file presence with permission, reinterpret exit 1 as cancellation, or infer child-chain completion from readback/direct-child exit. Do not migrate apply/restore/setup one async call at a time, create an interim command policy, remove legacy grants/originals, or claim this PR makes manual control safe. No production app, pmset, sudo, osascript, login or uninstall actions on the protected fleet host.

## Context

Effort: medium, one read/observation preparation PR; risk: high at the boundary with legacy writes. Historical audit labels F3/F4 track the read hang and permission-probe defects; this plan narrows scope deliberately. Critical 02 gates remain actual per-operation authorization/foreground completion, durable originals and uncertainty, cooperating-instance exclusion, safe legacy recovery and dedicated-Mac acceptance. No guessed transport/ACL feasibility or public-release approval is supplied here.

## Review of the YAGNI revision

On November 2, 2026, two independent subagents performed targeted safety and YAGNI verification of all seven revised documents against the accepted scope and source snapshot `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both returned **NO FINDINGS**. This follows the earlier five-angle review that recommended narrowing; it is not a new broad audit.

The verification confirmed that bounded asynchronous transport is limited to reads. Metadata observation does not authorize writes, and the legacy capture-to-write sequence is not partially migrated before 02.

This verdict concerns the revised documents. Implementation, authorization feasibility, native acceptance and release remain unverified; the unchecked implementation gates remain open. No application tests, native actions or network operations were performed by these two reviewers.
