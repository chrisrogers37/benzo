---
title: "[plan] Conditional final manual sessions and safe recovery"
type: plan
status: draft
owner: claudna:audit
created: 2026-11-02
tags: [security, reliability, conditional]
repos: chrisrogers37/benzo
---

## Summary

**Conditional, not implementation-ready.** One final PR on `codex/benzo-recovery-engine` replaces legacy manual mutation with a frozen-session coordinator, safe recovery and truthful quit. New persistent-setting control requires one real owner workflow and a useful, named hardware/OS/power target. Personal use is sufficient; no market research, telemetry or hardware-matrix project is required.

An actual supported legacy-recovery case independently justifies the safety work it needs. Declining new control does not make current unsafe recovery acceptable: explicitly scope a recovery-only/read-only endpoint before supporting existing users or releasing remaining mutations. This document does not authorize that alternative implementation silently.

The accepted YAGNI revision supersedes old P3/P4/P5 scheduling and feature scope. Retained [canonical C1–C6][master] safety obligations apply; live edits, ongoing profile acquisition, timers, a temporary `-a` policy and the old standing-grant design are removed from this plan. Current authority is documentation only.

## Evidence

Source references are pinned to **eed0a969b097142042dc4412424fbc71a04d2c0d**; proposed final services do not exist there.

| Source | Verified defect or constraint |
|---|---|
| [PMSetService.swift:25–52,69–78][pmset] | Sequential `-a` writes can partially apply; validation can fail after earlier writes; no readback/compensation. |
| [BenzoViewModel.swift:95–99,255–305][vm] | Preferences change before application; backup existence reuses stale originals; missing backup becomes false Off. |
| [BenzoViewModel.swift:119–158][vm] | Quit suppresses restore failures; Sleep Now implicitly activates and queues a delayed write. |
| [PMSetState.swift:7–18][parser], [BackupService.swift:7–24][backup] | Flat capture loses profile identity; file existence and `.atomic` do not establish validated durable originals. |
| [ShellExecutor.swift:35–89][shell] | Launch/setup migration and broad `%admin` wildcard grant need explicit retirement; existing authorization transport does not prove the proposed completion contract. |

Historical audit receipt only: at eed0a96, Node 24.22.1 web checks reported 33/33 tests and no moderate-or-higher audit findings. No full-Xcode/native acceptance was established. No app tests or native/network operations are run for this document revision.

## Implementation Plan

### Dependencies

Execute [03 containment](03_lifecycle.md) → [01 bounded reads](01_command-permissions.md) → [04 truthful diagnostics](04_diagnostics.md) → this conditional PR, with predecessors merged before dependent work. Refresh their exact heads and interfaces. Reuse 01's single bounded runner; it supplies read-side progress, **not accepted privileged-chain completion or mutation admission**. Packaging is a release gate, not a predecessor to safety fixes.

Before coding, close these narrow entry gates in this document:

- **G1 — Need and scope:** record the owner's concrete workflow, useful outcome, selected settings and eligible reported profiles on one hardware/OS/power target. Record any actual legacy-recovery case separately. If new control is unjustified, make the explicit recovery-only/read-only scope decision above; do not abandon existing evidence or recovery support.
- **G2 — Authorization feasibility:** explicit per-operation administrator authorization is the preferred candidate, not an accepted transport. Specify the supported macOS API/executable, exact bounded request encoding, prompt/denial/cancellation behavior, and documented foreground lifetime of the entire privileged execution chain. Explain how one logical operation, readback and necessary compensation complete without launching an unobserved writer. Evidence must distinguish canceled-before-launch from possibly executed; timeout/direct-child exit alone is insufficient. If these guarantees are unavailable, stop for a bounded design decision rather than inventing them or quietly installing a standing grant/helper.
- **G3 — Recovery and retirement:** specify how the same account holding originals can authorize recovery after relaunch, denial or credential loss; which exact restoring values the transport accepts; and safe direct legacy → final recovery/grant retirement. Establish grant ownership and permission inspection/removal semantics before implementation. Unknown prior controller, unreadable/out-of-domain originals or uncertain execution block retirement. Another admin's empty local state does not authorize takeover; no scanning other homes. Retain prerequisites until reviewed recovery/retirement is possible; unresolved cases need an explicit administrator-recovery decision.
- **G4 — Persistence and execution proof:** document supported macOS checked file/directory durability calls, kernel boot identity source and the evidence that clears a whole-chain fence. Resolve feasibility with separately authorized dedicated-host evidence where needed; record limits honestly. Update the exact transport file map and native acceptance cases before this becomes implementation-ready.

### Blocks

All native control releases remain blocked until retained mutation, recovery, authorization and quit acceptance pass. No public native release of intermediate safety slices. A source/fixture pass does not authorize privileged operations, release, deployment or merge. The user handles merges.

### Steps

1. **Own the following paths only.** Native paths below are relative to `Benzo/Benzo/` except the repo-relative Xcode project; tests are under `Benzo/BenzoTests/`. Shared files are sequential 03 → 01 → 04 → 02, never parallel mutation engines. Transport-specific additions require the G2/G3 amendment first.

| Ownership | Exact paths and responsibility |
|---|---|
| Existing capture/storage | `Models/PMSetState.swift`, `Models/OriginalSettingsBackup.swift`, `Services/BackupService.swift`, `Services/PMSetService.swift`: typed complete capture, preserved legacy decoder, validated exact requests. |
| Existing integration | `Services/ShellExecutor.swift`, `Services/BenzoDependencies.swift`, `Services/DiagnosticService.swift`, `ViewModels/BenzoViewModel.swift`, `App/AppDelegate.swift`: chosen authorization boundary, injected final coordinator, observations and graceful quit. |
| Existing native UI/project | `Views/MasterToggleView.swift`, `Views/SettingRowView.swift`, `Views/FooterView.swift`, `Views/PopoverContentView.swift`, `Views/SetupView.swift`, `Views/SleepNowButton.swift`; `Benzo/Benzo.xcodeproj/project.pbxproj`: state/actions and correct target membership. |
| Six proposed files | `Models/RecoveryJournal.swift`, `Models/ControlState.swift`, `Services/OperationCoordinator.swift`, `Services/DurableJournal.swift`, `Services/ExecutionFenceStore.swift`, `Services/BootIdentityProvider.swift`: bounded responsibilities below, not a generic framework. |
| Existing tests | `BenzoCoreTests.swift`, `TestDoubles.swift`: extend injected fakes and focused failure coverage in the existing unhosted target. |
| Active web parity | `src/demo/useBenzoDemo.js`, `src/landing/NativeAppDemo.jsx`, `src/landing/BenzoLanding.jsx`, `src/landing/NativeAppDemo.test.jsx`, `src/landing/BenzoLanding.test.jsx`, `src/design/appPresentation.js`, `src/design/siteCopy.js`, `src/design/README.md`. |
| Documentation | `README.md`, `CLAUDE.md`, `AGENTS.md`: final workflow/recovery limits and corrected active-demo parity paths. |

Planned map: 29 existing paths modified, six created, none deleted, subject only to the explicit transport gate. Reuse 01's runner; do not add a second process implementation. Models/storage use Foundation, ViewModel retains Combine/Foundation, and AppKit stays at the app boundary; isolate any Darwin file/lock calls in the named services.

2. **Freeze one session.** Absorb 03's selection guards into the final state contract: choices are editable only when fully resolved and unfenced; acquire admission before reading or persisting a requested edit. Start freezes selection and eligible reported profiles. Active/busy/recovery states reject edits without preference changes. Restore or explicitly resolve every owned cell before a fresh session. Newly appearing profiles/settings are observed only; no late acquisition, individual live removal or automatic reapply.

3. **Capture/validate the whole plan.** `PMSetState` represents `PowerProfile { ac, battery, ups }`, `ManagedCell(profile,key)` and raw profile capture. Read unprivileged `pmset -g custom`; map reported profiles to exact `-c/-b/-u`, never invent absent profiles. Parse spaces/tabs; reject missing selected keys, duplicates, unexplained suffixes and malformed/non-ASCII/oversized integers. Validate all targets and restoring originals before the first write. Supported values are hibernatemode `{0,3,25}` and Boolean `{0,1}` for standby/autopoweroff/powernap/tcpkeepalive/proximitywake/womp; unsupported originals block acquisition rather than normalization. G1 narrows eligible profiles without promising physical effects.

4. **Persist originals and intent first.** `RecoveryJournal` holds version, UID/host provenance, session/operation identity, revision, raw capture, immutable per-cell originals, separate operation pre-state, complete ordered preconditions/targets, step intents/outcomes/readbacks and conflicts. `DurableJournal.load/commit/replaceResolvedReceipt` checks schema/value/completeness, account ownership, 0700 directory/0600 regular files and symlink rejection. Check write, file flush, same-directory rename and directory persistence; surface every failure. State the G4 durability guarantee; `.atomic`/checksums are not power-loss guarantees or authentication. Retain the unresolved journal, required previous valid generation, one last resolved receipt and unresolved legacy evidence; never prune the only original.

5. **Create one final coordinator.** `OperationCoordinator` owns `reconcileReadOnly`, `startSession`, `restoreSession`, `resolveConflict`, `requestSleep` and `prepareQuit`. It owns a non-reentrant token acquired before the first await and a process-lifetime nonblocking account-local lock excluding cooperating instances. Hold admission through capture, authorization, all forward/compensation writes, final durable receipt and state publication; reject overlap before preference edits. Actor isolation/disabled UI alone are insufficient. All retained writes, including recovery and permission retirement, require this boundary; views/ViewModel/quit have no alternative engine. Stale reads cannot overwrite a newer operation state.

6. **Execute the complete admitted plan.** Validate authorization, fence, restoring originals and persistence; own only cells whose values will change. Commit plan/originals before execution, persist each intent, recheck expected cell value, issue one exact profile/key/value request and capture readback even on nonzero/timeout where observation remains possible. Stop on mismatch/error/unknown. When whole-chain completion is proven, compensate attempted cells in reverse only where current still equals the last verified Benzo write; restore this operation's pre-state. Failed readback/compensation or a third-party value preserves unresolved ownership. Final success requires complete matching readback and checked durable receipt; already-target cells remain unowned. Final Restore uses immutable session originals.

Use deterministic profile/key order. Every read and chosen write transport has bounded time/output and typed outcomes through 01's runner contract; returning from a timeout does not prove quiescence or authorize compensation. Failure before the initial durable plan permits zero writes; later persistence failure leaves prewritten intent unresolved.

Example: AC standby starts at 1 and battery standby at 0. A frozen target of 0 owns only AC after changing 1→0; final Restore targets AC=1 and never writes battery. A new session may capture fresh originals only after all ownership and execution uncertainty resolve.

7. **Fence execution separately from configuration.** `ExecutionFenceStore` durably records boot identity, app incarnation, operation and pre-launch state before any potentially mutating request, including the launch-before-child-identity gap. Same-boot uncertainty blocks new writes, compensation, Keep Current, ownership release, grant retirement and uninstall even if values match originals. Timeout, app lock, bare/reused PID or wrapper exit cannot clear it. Only G2's whole-chain completion proof or a verified later kernel boot permits progress; unavailable boot identity remains unknown. A later boot permits read-only reconciliation only, never automatic restore/replay. Do not kill/reboot to clear a fence.

8. **Reconcile without replay.** Startup reads fence/evidence before deciding state; prepared intents may have executed without a receipt. Missing/corrupt/foreign/unsupported evidence or legacy active/interrupted state becomes `recoveryRequired`, never Off. Once quiescent, current==original resolves without a write; current==last verified Benzo value permits verified restore; a third value requires explicit Keep Current/release or Restore Recorded Original Anyway. Show friendly setting/profile, capture time and qualified original/current values. Defer/dismiss/Escape retains ownership. Acknowledge ABA and read/write races: this lock excludes cooperating Benzo instances, not other administrators/tools.

9. **Handle legacy directly.** Preserve `OriginalSettingsBackup`/`BackupService` decoding and source evidence. Flat originals cannot establish per-profile ownership: restore only where provenance is substantiated, or obtain explicit acceptance of current observed baseline acknowledging lost historical originals. Preserve evidence and label that outcome accepted, not restored. Implement only G3's reviewed same-account recovery/retirement sequence; preserve old prerequisites on failure/unknown. No temporary policy migration, broad-grant use as new final control, or new controller-manifest/ACL subsystem is inherited from old P3/P4.

10. **Publish truthful state and quit.** `ControlState` supplies checking/off/applying/activeVerified(timestamp)/restoring/recoveryRequired; Off requires no unresolved ownership or execution. Replace the existing deactivate failure branch below with `publish(await coordinator.restoreSession())`; this is the intended routing contract, with exact signatures set after G2–G4, and load failure must publish recovery.

```swift
guard let backup = try? dependencies.backup.load() else {
    isActive = false
    onStateChange?(false)
    return
}
```

Persist choices separately; no saved Boolean proves success. Empty selection cannot activate protection. Rename Restore System Defaults to Restore Previous Settings and remove delete/reactivate recovery advice. Status item and accessibility labels show busy/recovery even with the popover closed.

AppDelegate uses AppKit `terminateLater` while the coordinator settles admitted work and restores/verifies. Successful restoration permits termination; denied authorization, unresolved conflict or failed/uncertain execution offers Retry, Stay Open, or explicit Quit Anyway preserving journal/fence and warning settings may remain changed. Never silently terminate on a failed restore; forced termination relies on next-launch reconciliation, not a guaranteed callback.

11. **Keep only explicit manual sleep if G1 needs it.** 03 disables the unsafe Sleep Now path and cancels its 0.5-second continuation. Reintroduce it only through the final coordinator, after a verified frozen session and G2 authorization/readiness; no hidden activation, delay, timer, blocker termination or new identity provider. Persist sleep intent, report sleep requested, retain uncertain completion and never replay after restart. Do not add a no-setting sleep variant without the named workflow requiring it.

12. **Mirror retained behavior and finish caller migration.** One `useBenzoDemo` state drives `NativeAppDemo` and page state. Cover frozen selections, partial apply/recovery, denied authorization, deferred conflict, legacy acknowledgment and truthful quit; keep historical BenzoHybrid/BenzoMockup/demo compatibility files untouched. Update the owned docs' stale parity guidance. Audit callers of `applySettings`, `applySettingsWithRestore`, `restoreValues`, `runDirectWithSudo`, `isActive`, `toggleSetting`, `sleepNow`, `quit` and sudoers setup/removal at parent/final heads; no residual bypass may remain release-enabled. Adapt 04 observations without reintroducing green verification or a receipt/logging product.

## Test Plan

Extend `BenzoCoreTests.swift` and `TestDoubles.swift`; use explicit scratch storage and fakes only, with no production AppDelegate/ViewModel defaults, real commands, backups or login controls. Register pure sources in the existing test target; keep live composition excluded.

| Focus | Required failure assertions |
|---|---|
| Capture/session | Unequal AC/Battery/UPS; absent profile/key; tab/duplicate/suffix/invalid value; unsupported original; no-op unowned cell; frozen edits refused before preference writes; new profile cannot acquire; next resolved session captures fresh originals. |
| Persistence/execution | Fail write/flush/rename/directory-sync at each intent/receipt boundary; crash/restart before/after launch; original survives retention; nonzero after mutation, exit-zero mismatch, unreadable readback and failed compensation retain correct originals/pre-state/ownership. |
| Admission/fence | Held awaits across authorization/capture/write/final commit; competing Restore/Quit/edit/Sleep/second instance; delayed writer and pre-identity crash; PID reuse; same-boot matching values cannot release; verified later boot permits observation only. |
| Authorization/legacy | Canceled-before-launch versus uncertain execution; full privileged-chain completion evidence; same-account relaunch/recovery; denied restore/credential loss; direct legacy → final retirement; unknown owner/out-of-domain originals preserve grant/evidence. |
| Recovery/UI/quit | Missing/corrupt/foreign data never Off; third-value Keep/Restore/Defer and dismiss; closed-popover recovery; quit Retry/Stay/Quit Anyway; no live-edit/timer/hidden-activation path; active-demo parity. |

At the actual implementation head run existing `npm ci`, `npm test`, `npm run build`, `npm audit --audit-level=moderate` on `.nvmrc` Node 24; retain separate existing Gitleaks CI evidence. On a full-Xcode runner use README's Debug/Release builds and unhosted BenzoCoreTests with fresh `BENZO_TEST_DERIVED`. No new generic harness or repeat full-suite campaign is required.

Dedicated authorized native acceptance must prove chosen authorization/completion, direct legacy recovery/retirement, distinct-profile apply/restore, interrupted writes, untouched-cell equality, preserved evidence and quit. Browser/native accessibility checks cover the retained states. Record exact heads and before/after observations. Configuration readback is not proof of hibernation, USB power loss or battery benefit. Protected fleet host: no app launch, pmset/sudo/osascript, sleep/reboot, permission/login changes, installs/uninstalls or process killing.

## Verification Checklist

- [ ] G1–G4 closed with actual workflow/recovery need, feasible chosen transport, same-account recovery/retirement and durability/completion evidence before coding.
- [ ] One runner and final coordinator; frozen selections; whole-operation admission/lock; all retained mutations have complete validated durable originals/intent.
- [ ] Readback, compensation, conflicts, legacy preservation and independent execution fence retain unresolved state correctly; no false Off/restored/quit claim.
- [ ] Current-head existing checks and focused fault tests pass; dedicated native and active-demo acceptance complete with independent security/recovery review.
- [ ] Direct legacy → final only; existing grants/evidence preserved until safe explicit retirement; no native partial-slice release or inferred outward authority.

## What NOT To Do

Do not value-gate existing unsafe recovery out of existence; invent an accepted authorization transport; add a standing grant, temporary `-a` bridge, helper or manifest framework by default; fan flat originals across profiles; restore unowned cells; normalize invalid originals; compensate/release while execution is uncertain; or treat matching current values as completion proof. No live editing, ongoing acquisition, scheduler, automatic reapply, blocker killing or ViewModel/interim mutation engine.

## Context

Effort **L**, risk **high** for retained mutation/recovery; scope is conditional and bounded by G1–G4. This replaces the prior execution supplement, not the historical [canonical P4][p4] record. Prior adversarial-review conclusions do not review this revised document. Remaining design gates are explicit above; no implementation/native acceptance claim is made.

[master]: https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/documentation/plans/benzo-reorientation_2026-10-25/00_overview.md
[p4]: https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/documentation/plans/benzo-reorientation_2026-10-25/04_recovery-engine.md
[pmset]: https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/Benzo/Benzo/Services/PMSetService.swift#L25
[vm]: https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/Benzo/Benzo/ViewModels/BenzoViewModel.swift#L95
[parser]: https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/Benzo/Benzo/Models/PMSetState.swift#L7
[backup]: https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/Benzo/Benzo/Services/BackupService.swift#L7
[shell]: https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/Benzo/Benzo/Services/ShellExecutor.swift#L35

## Review of the YAGNI revision

On November 2, 2026, two independent subagents performed targeted safety and YAGNI verification of all seven revised documents against the accepted scope and source snapshot `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both returned **NO FINDINGS**. This follows the earlier five-angle review that recommended narrowing; it is not a new broad audit.

The verification confirmed that frozen sessions retain the necessary write/recovery guarantees. G1–G4 remain unresolved implementation-entry decisions: need, authorization/completion, legacy recovery/retirement and durability/fencing.

This verdict concerns the revised documents. Implementation, authorization feasibility, native acceptance and release remain unverified; the unchecked implementation gates remain open. No application tests, native actions or network operations were performed by these two reviewers.
