---
title: "[safety] Contain automatic mutations and freeze active selections"
type: plan
status: active
owner: claudna:audit
created: 2026-11-02
tags: [safety, reliability, "priority:high"]
repos: chrisrogers37/benzo
---

## Summary

**IN PROGRESS — Started 2026-11-02.** Branch `implement/benzo-containment`, parent `eed0a969b097142042dc4412424fbc71a04d2c0d`. The user explicitly requested implementation after the revised YAGNI review. Local implementation and review precede the repository's separate preview-deployment/push gate.

One first implementation PR removes timed sleep, blocker termination, automatic drift reapply and launch-time permission installation. Disable manual Sleep Now and remove its uncancellable delayed continuation until [02](02_recovery-engine.md) can provide verified readiness. Freeze settings before any preference edit while active or recovery evidence is present/unknown. Preserve originals and existing grants.

This is the accepted YAGNI replacement for the former P5 supplement, not an added scheduler project. Execute **03 → 01 → 04 → conditional 02**. Packaging is a release gate, not a predecessor to these source fixes. No intermediate native release is authorized: surviving manual apply/restore/quit defects remain unresolved. If 02's new-control scope is declined, explicitly scope a recovery-only/read-only endpoint; do not abandon existing recovery or release unsafe controls.

## Evidence

Source references are repository-relative at pinned main `eed0a969b097142042dc4412424fbc71a04d2c0d`; refresh line numbers on the implementation parent.

| Source | Current behavior |
|---|---|
| `Benzo/Benzo/ViewModels/BenzoViewModel.swift:61–67,95–99` | Launch queues permission installation; selection changes persist before active settings are reapplied. |
| `Benzo/Benzo/ViewModels/BenzoViewModel.swift:126–190` | Manual sleep queues an uncancellable 0.5-second callback; timer expiry kills blockers and then sleeps. |
| `Benzo/Benzo/ViewModels/BenzoViewModel.swift:195–229`; `Benzo/Benzo/App/AppDelegate.swift:129` | Opening the popover can queue automatic writes based on stale drift reads. |
| `Benzo/Benzo/Services/PMSetService.swift:9,81–84` | Invalid-backup error advises deletion; `killCaffeinateProcesses()` executes `pkill caffeinate`. |
| `Benzo/Benzo/Services/BackupService.swift:7–13`; `Casks/benzo.rb:14–20` | Backup presence creates a directory; cask removal requests quit/deletes the grant and zap trashes originals/preferences. |
| `Benzo/Benzo/ViewModels/BenzoViewModel.swift:119–123,255–299` | Quit suppresses restoration failures; missing backup can produce false Off; capture/apply/restore remain incomplete. |
| `src/demo/useBenzoDemo.js:25–43,51–60` | Active simulation retains timer/expiry and allows active selection edits. |

The prior audit reported 33/33 web tests, build and npm audit passing on this snapshot. Those receipts are historical; no tests or native acceptance ran during this rewrite.

## Implementation Plan

### Dependencies

This PR is first. Reconcile the pinned source with current main and preserve unrelated changes before implementation. The accepted rescope supersedes the old P2–P5 schedule and scheduler/CLI scope; retained safety contracts reached by manual controls remain obligations of 02. No parallel implementation on shared files.

### Blocks

01 begins only after this containment PR is merged; 04 follows 01. Public native release remains blocked until 02 or an explicitly accepted recovery-only endpoint safely resolves remaining mutations and recovery. Removing cask hooks alone does not establish safe uninstall.

### Steps

1. **Own these existing files only; no new subsystem.** Native shorthand below is relative to `Benzo/Benzo/`.

   | Files | Change |
   |---|---|
   | `ViewModels/BenzoViewModel.swift`, `Services/BenzoDependencies.swift`, `App/AppDelegate.swift` | Remove automatic/timed work; reject setting edits before persistence; remove dead timer and blocker seams. |
   | `Services/PMSetService.swift`, `Services/BackupService.swift`, `Services/DiagnosticService.swift` | Remove kill and unused blocker reader; preserve backup evidence and inspect its presence without creating files. |
   | `Views/SleepNowButton.swift`, `Views/PopoverContentView.swift`, `Views/SettingRowView.swift` | Disable Sleep Now, remove timer/blocker UI, display frozen-selection reason. |
   | `Benzo/BenzoTests/BenzoCoreTests.swift`, `Benzo/BenzoTests/TestDoubles.swift` | Replace removed behavior tests and add focused containment cases. |
   | `src/demo/useBenzoDemo.js`, `src/landing/NativeAppDemo.jsx`, `src/landing/NativeAppDemo.test.jsx`, `src/landing/BenzoLanding.test.jsx`, `src/design/appPresentation.js`, `src/design/siteCopy.js`, `src/design/app-demo.css` | Match removed controls, disabled sleep and selection freeze; delete adjacent unused timer styling only after caller search. |
   | `Casks/benzo.rb`, `README.md`, `CLAUDE.md`, `AGENTS.md`, `src/design/README.md` | Preserve recovery during removal; explain temporary limits and correct active parity guidance. |

2. **Delete timed sleep, do not replace it.** Remove `sleepTimerRemaining`, `sleepTimer`, `scheduleSleep(after:)`, `cancelScheduledSleep()` and `executeSleepWithBlockerKill()` from the ViewModel. Delete `PMSetService.killCaffeinateProcesses()`. Remove timer arguments/picker/countdown from `SleepNowButton` and its `PopoverContentView` call. After checking callers, remove `BenzoCancellation`, both scheduling methods from `BenzoClock`, their live adapters and corresponding fake timer code; keep `clock.now` for backup timestamps.

3. **Disable the entire manual sleep entrypoint.** Replace `sleepNow()` with a synchronous refusal setting `errorMessage = "Sleep Now is unavailable while recovery controls are being updated."`; it performs zero backup, preference or command writes. Delete its captured `pmset`/0.5-second continuation and unused `isSleeping` state. Render Sleep Now disabled with the same explanation. No immediate `pmset sleepnow` substitute. 02 alone may reintroduce this action through its final safe operation boundary.

4. **Remove automatic mutation paths.** Delete the `needsSudoersUpdate()`/queued installer block from automatic initialization; retain only existing nonmutating setup observation until 01 replaces it. Remove `verifyAndCorrectSettings()` and its `AppDelegate.togglePopover()` call entirely. Remove the main blocker panel and `sleepBlockers` state, dependency/composition closure, and active-demo blocker example. Delete `DiagnosticService.fetchSleepBlockers()`, its name-filter/map and private parsing helpers only after a repository caller search confirms they are unused. 04 owns retained diagnostic panels; no replacement blocker provider, refresh or identity model is required.

5. **Freeze selection at the model boundary before `didSet`.** Make `settingStates` `private(set)`. Add `BackupEvidencePresence { case absent, present, unknown(String) }` and `BackupStoring.evidencePresence()` in existing `BenzoDependencies.swift`; implement metadata-only inspection in `BackupService` using the injected `fileURL`, never the directory-creating `backupURL`. Only confirmed missing evidence is `.absent`; existing/corrupt files remain `.present`, unreadable paths or ambiguous metadata are `.unknown`. Never read another account's home.

   Replace the existing toggle-then-apply body with this contract (illustrative Swift):

   ```swift
   guard !isActive, !isSelectionEditBlocked else {
       errorMessage = "Resolve the current session or recovery before changing settings."
       return
   }
   settingStates[setting]?.toggle()
   ```

   `isSelectionEditBlocked` is true unless `evidencePresence()` is `.absent`; evaluate that predicate synchronously immediately before edits. Use the same predicate to disable rows/show the reason, but retain the method guard. Remove the now-unused `applyCurrentSettings()` after caller search. Present/unknown legacy evidence stays locked even after legacy Off/Restore appears successful: this slice cannot prove resolution and must not delete evidence to unlock. Missing evidence is never proof that settings are Off or restored.

6. **Preserve recovery prerequisites.** Change `PMSetError.invalidBackupData` advice to retain recovery files and seek recovery; remove the delete-and-reactivate instruction. In `Casks/benzo.rb`, delete the `uninstall quit:/delete:` stanza and both `zap trash:` entries; do not insert another cleanup command. Document that app removal is not verified restoration or grant retirement, and retained evidence/grants require a later explicit safe recovery/retirement flow. Do not create a CLI, cask readiness receipt, migration or new grant.

7. **Match the active simulation and guidance.** In `useBenzoDemo`, remove picker/timer/tick/cancel/sleep-finish state/actions and effects; reject `sleep` without activation or other state changes, and reject `setting` while active or `backup` evidence is present. Keep the simulated backup after Restore, matching the conservative lock until 02. Update `NativeAppDemo`, `appPresentation` and `siteCopy` to show unavailable Sleep Now, no timer/blocker panel and the frozen reason. Remove timer claims from adjacent copy; preserve unrelated historical sources/tests. Replace stale `CLAUDE.md`/README parity instructions with `NativeAppDemo` + `useBenzoDemo` + `appPresentation`, owned once by `BenzoLanding`; align `AGENTS.md` ordering with this accepted rescope.

## Test Plan

Future implementation uses existing unhosted XCTest/fakes and Vitest; no tests run for this Markdown revision. Keep manual-startup injection and production composition outside core tests.

| Focused case | Required assertion |
|---|---|
| Automatic startup with old/missing grant; popover open/close | No installer, queued mutation, sleep or process termination. Manual startup still performs no automatic checks. |
| Direct `sleepNow()` calls; former timer routes | Explicit unavailable result and zero commands, backup writes, preference changes or queued continuations; timer symbols have no live callers. |
| Active selection; inactive with valid/corrupt/unreadable evidence | Selection and persisted preferences unchanged; no apply or restore; reason visible. Inactive with confirmed absence edits preferences only. |
| Legacy Off/Restore followed by a selection edit | Existing evidence still locks editing; no deletion or inferred recovery success. |
| Scratch evidence-presence checks | Missing path does not create directories; metadata failure is unknown; file bytes remain unchanged. |
| Active demo | Timer/blocker controls absent; sleep disabled; active/recovery checkbox attempts preserve selection; first-launch absent-evidence choices remain editable. |

Replace `testDelayedSleepUsesInjectedClockAndCommandRunner` and `testScheduledSleepCanBeCancelledWithoutExecutingACommand` with refusal/no-continuation checks. Extend the existing startup test for `.automatic`; keep `.manual` coverage. Update affected demo tests, then run required existing checks once on the completed implementation: Node 24 `npm ci`, `npm test`, `npm run build`, `npm audit --audit-level=moderate`; README's full-Xcode Debug/Release builds and `BenzoCoreTests` using task-owned DerivedData; exact-head existing Gitleaks CI. Missing Xcode/browser evidence remains open.

Use source search for `scheduleSleep|cancelScheduledSleep|executeSleepWithBlockerKill|killCaffeinateProcesses|verifyAndCorrectSettings|pkill|sleepTimerRemaining`; classify historical unbundled fixtures separately. Inspect cask text without install/uninstall. Authorized browser checks cover disabled/frozen affordances; native acceptance requires a separately approved dedicated Mac. Never launch Benzo, invoke pmset/sudo/osascript, alter login, kill blockers, sleep/reboot or install/uninstall on the fleet host.

## Verification Checklist

- [ ] Parent and final-head checks recorded; no historical pass reused as current evidence.
- [x] Timed sleep, kill, drift reapply and launch installer have no live path; manual sleep refuses without queued work (source review; native execution pending).
- [x] Model rejects active/recovery edits before preference persistence; evidence inspection is nonmutating (source review and authored regression cases; XCTest pending).
- [x] Cask and invalid-backup guidance preserve evidence/grants; no safe-uninstall claim added.
- [x] Active native/demo source behavior and contributor guidance agree; independent review completed. Native rendered acceptance remains open.
- [x] Manual mutation, false-Off, persistence, authorization, restore and quit risks remain explicitly held for 02 or scoped recovery-only resolution.

## What NOT To Do

Do not add a scheduler, blocker identity/provider system, live tuning, CLI, new grant or process killing. Do not async-convert the surviving mutation chain, delete originals, claim an Off toggle proves recovery, or equate this containment PR with safe manual control. Do not publish an intermediate native build with unresolved mutation paths.

## Context

Effort: medium, one removal/containment PR; risk: high because legacy mutations remain. This plan intentionally removes features and supersedes the former broad P5 implementation. [01](01_command-permissions.md) owns read/permission preparation, [04](04_diagnostics.md) retained diagnostic truthfulness, and conditional [02](02_recovery-engine.md) final manual control/recovery. Original audit mappings F1/F2 remain historical labels; full resolution is not claimed here.

## Review of the YAGNI revision

On November 2, 2026, two independent subagents performed targeted safety and YAGNI verification of all seven revised documents against the accepted scope and source snapshot `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both returned **NO FINDINGS**. This follows the earlier five-angle review that recommended narrowing; it is not a new broad audit.

The verification covered timer and drift removal, both delayed sleep paths, selection guards before persistence, blocker-display removal, and preservation of originals/grants during cask and guidance changes.

This verdict concerns the revised documents. Implementation, authorization feasibility, native acceptance and release remain unverified; the unchecked implementation gates remain open. No application tests, native actions or network operations were performed by these two reviewers.

## Implementation checkpoint — 2026-11-02

**Local implementation complete; verification and publication pending.** This remains an active plan, not a completed or released phase. The user requested implementation after accepting the narrowed YAGNI scope. A fresh comparison against unchanged main `eed0a969b097142042dc4412424fbc71a04d2c0d` found no missing live paths or new design decision. Branch: `implement/benzo-containment`.

| Deliverable | Result |
|---|---|
| Native containment and frozen selections | Implemented in existing source files. Removed scheduling adapters, automatic correction/installer callbacks and blocker paths; direct sleep refuses. |
| Nonmutating evidence observation | Implemented; confirmed missing paths remain absent without directory creation. Corrupt files, symlinks and ambiguous ancestors remain present/unknown. |
| Recovery preservation | Cask quit/delete/zap hooks removed; invalid-backup deletion advice removed. Legacy manual mutation risks remain open. |
| Active demo and guidance | Implemented; historical behavior preserved. One legacy fixture now owns its unchanged `[5, 15, 30, 60]` values to remove the active presentation dependency. The unused `SleepBlocker` model was deleted after caller audit. |
| Focused tests | Existing Vitest suite: 34/34 pass across all three files. Existing XCTest suite expanded to 23 cases; authored and syntax-parsed, not executed. No new test framework. |
| Required local checks | Node 24.22.1 clean `npm ci`, web tests/build and moderate audit passed; audit reported zero vulnerabilities. Ruby cask syntax, Swift syntax parsing, Command Line Tools type-check of all 24 app Swift files, and diff whitespace checks passed. The CLT type-check is not an Xcode build or XCTest run. |
| Browser evidence | Desktop active state and 390px mobile post-Restore state checked; disabled controls/explanations, fresh editable choices, retained recovery lock, no mobile horizontal overflow and no console warnings/errors observed. Local screenshots retained outside Git. |
| Missing checks | Full-Xcode Debug/Release builds, unhosted XCTest execution and final-head remote security/build CI remain unverified. Native physical/privileged acceptance was not performed. |

Independent read-only reviews covered native safety/reuse, active web correctness/simplification, efficiency, and responsibility boundaries. One important finding was fixed: `ENOENT` beneath a dangling parent symlink could falsely unlock selections. Ancestor metadata now keeps that case unknown; focused re-review returned NO FINDINGS. Other lenses returned NO FINDINGS. An additional CLT type-check caught an Int/Int32 error-code comparison; the comparison was corrected without a force unwrap and all 24 app sources then type-checked successfully. No additional simplification change was justified.

Media decision: **screenshots**, to check disabled/frozen affordances and wrapping. Interaction guards are exercised by the existing tests and observed browser transitions; no video or native-parity claim. Screenshot hashes, source input hashes, dimensions and local validation are retained in the task's external evidence packet. No upload or PR rendering acceptance has occurred.

The Vercel project `benzo` is connected; GitHub deployment records show recent `vercel[bot]` Preview deployments. Per `AGENTS.md`, branch push and its preview require separate scoped authority. No branch push, PR, merge, deployment, native launch or host power/grant/login/process change occurred at this checkpoint. The next dependent phase does not start before user merge.

Exact web test command: `npm test -- src/landing/NativeAppDemo.test.jsx src/landing/BenzoLanding.test.jsx src/components/BenzoMockup.test.jsx`, using task-local Node 24.22.1. Results: active demo 13, landing 4, historical mockup 17; all 34 passed. Web runtime inputs remained unchanged through final native fixes and documentation edits.
