---
title: "[plan] P4 — Profile-aware recoverable operations"
type: plan
status: draft
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-25
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size L, risk high. Replace flat snapshots and Boolean success with a single recoverable transaction engine whose unit of ownership is a changed profile/key cell. One PR on `codex/benzo-recovery-engine` implements C1–C7, including the matching profile-specific permission migration and minimum truthful native/demo UI.

## Evidence

`PMSetService.swift:18` reads one flat state and `:24,33,69` writes all profiles with `-a`; `PMSetState.swift:7` loses tab-separated values. `BackupService.swift:11` treats existence as validity; `OriginalSettingsBackup.swift:3` has no profile/provenance. `BenzoViewModel.swift:93,255,273,298` saves desired choices ahead of apply, reuses old originals, reports Off after failure and does not compensate checkbox failures. `PMSetService.swift:9` advises deleting the recovery file. These defects are distinct from hardware qualification.

## Implementation Plan

### Dependencies

P3 merged, including bounded runner and internally compatible temporary exact policy. F3/F4 accepted. Use master C1–C7 without reimplementing their logic in UI. A dedicated test Mac is required for real profile/policy round-trip acceptance.

### Blocks

P5 lifecycle/uninstall integration and P6 truthful diagnostics. Public release remains gated on P5 too.

### Steps

1. **Own files:** replace internals of `Models/PMSetState.swift`, `Models/OriginalSettingsBackup.swift`, `Services/BackupService.swift`, `Services/PMSetService.swift`; new `Models/RecoveryJournal.swift`, `Models/ControlState.swift`, `Services/OperationCoordinator.swift`, `Services/DurableJournal.swift`; reuse P3 `DurableFileStore`, `ExecutionFenceStore` and `BootIdentityProvider`; update `PermissionPolicy.swift`, `PermissionManager.swift`, `BenzoViewModel.swift`, `MasterToggleView.swift`, `SettingRowView.swift`, `FooterView.swift`, `PopoverContentView.swift`, `App/AppDelegate.swift`; corresponding native tests, extracted demo/state/fixtures/tests and recovery docs. Register new files in the existing Xcode target/test scheme.
2. Introduce typed profiles/cells and a complete capture. Skeleton:
   ```swift
   enum PowerProfile: String, Codable { case ac, battery, ups }
   struct ManagedCell: Hashable, Codable { let profile: PowerProfile; let key: PMSetKey }
   struct ProfileCapture { let profiles: [PowerProfile: [PMSetKey: Int]]; let raw: String }
   protocol PMSetBackend { func capture() async throws -> ProfileCapture; func write(_ cell: ManagedCell, value: Int) async -> CommandOutcome }
   ```
   Production capture uses `-g custom`; writes map exact profile selectors. Parse/validate C2 before converting strings to typed values. Preserve raw input as evidence. Separate full capture completeness from selected-feature availability; no implicit default/fan-out.
3. Replace backup-exists logic with versioned `RecoveryJournal` and `DurableJournal.load/commit/replaceLastResolvedReceipt`. Follow C3 envelope, last-valid-generation, restrictive permissions and checked durability. Reuse P3 checked file-store durability rather than introducing a competing persistence implementation. Add injectable filesystem faults at write/flush/rename/directory-sync boundaries. Retain exactly current unresolved journal plus required previous valid generation and one last resolved receipt; preserve unresolved/legacy originals separately until explicit appropriate resolution. Test pruning/replacement cannot remove the only unresolved original. No completed-session archive. A commit failure before the first mutation produces zero writes; a failure after a write retains prewritten intent and unresolved state. Verify the macOS durability sequence against supported APIs during implementation; document its exact achievable scope, not a universal power-loss guarantee.
4. `OperationCoordinator` owns one operation token and a process-lifetime account-local lock. Its proposed API is `reconcileReadOnly()`, `apply(selection)`, `restoreOwnedCells()`, `resolveConflict(cell, choice)` and `requestSleep(intent)`; all writes pass through the same gate. Implement deterministic planned-cell ordering and C4 compensation. Keep immutable session original separately from operation pre-state. No-op targets stay unowned; restoring one option releases only its resolved cells. Final success requires readback plus durable receipt. Nonzero/timeout can still have applied; a live/unknown child forbids rollback until reconciled. New reads arriving from an older generation cannot overwrite newer control state. Consume the P3 execution fence before any reconciliation can release ownership: pending same-boot execution blocks compensation, Keep Current, new writes, permission handoff/retirement and uninstall even when current values equal originals. Preserve the launch-before-child-identity gap. Clearing requires trustworthy whole-execution completion; after app restart, absent that proof require a verified later kernel boot-session identity. A later boot allows read-only reconciliation, not automatic restoration. A bare/reused PID, elapsed timeout or acquired lock is never completion proof.
5. Replace desired `isActive` truth with `ControlState`; derive any compatibility display Boolean from `.activeVerified`, never persist it as evidence. Keep selected preferences independently. Empty selection shows Off/no settings selected and cannot claim protection. A failed update preserves requested/applied distinction and recovery action. Change “Restore System Defaults” to “Restore Previous Settings” and delete the destructive recovery advice. Every error identifies whether values may remain changed and how preserved evidence can be reviewed. Update `AppDelegate` status-item subscription/callback ownership from the saved/published Boolean to `ControlState`: recovery/unknown and busy states have distinct presentation plus accessible name/tooltip even while the popover is closed. They must not look Off. Mirror state in the demo immediately; P7 polishes it. Recovery choices display friendly setting/power-source names, capture time and qualified current/original meaning, with raw values in details and clear ownership consequences. Defer/dismiss/Escape preserves unresolved state; no default overwrite.
6. Implement read-only journal startup reconciliation now so the new format is never ignored, while P5 wires all lifecycle callers. Preserve and classify legacy flat data; do not execute old restore to unblock setup. Provide the explicit C6 provenance/accept-current-baseline decision UI in native and demo. Missing/corrupt/foreign-host/UID/schema cases block new writes; retaining or acknowledging evidence is distinct from verified restoration.
7. In the same PR, replace temporary `-a` policy with exact `-b/-c/-u` finite entries and exact sleepnow. Bump manifest version and require explicit safe migration. Remove `-a` from production mutation construction and successfully migrated installed policy. Prevalidate all originals before grant replacement; unresolved legacy out-of-domain recovery keeps migration blocked with old prerequisites intact. Test generated policy and emitted commands as one contract; dedicated-Mac testing proves actual matching. Include direct v0.3.0 legacy → final profile-policy migration bypassing P3, as well as P3 → P4. Root controller UID compare-and-install/handoff remains enforced; another admin cannot use local empty state to replace the prior owner.

## Test Plan

Fault matrix: unequal AC/Battery/UPS originals; missing profile/key; spaces/tabs/duplicate/annotated/malformed/non-ASCII values; already-target no-op; each forward write failing before/after mutation; exit-zero mismatch; unreadable readback; compensation failure; each journal failure boundary; restart after every intent/receipt boundary; live-child timeout; stale baseline across two sessions; per-option rollback to operation pre-state; new acquisition capture; external third-value conflict; keep-current release; explicit restore-anyway; missing/corrupt/legacy/foreign evidence; two instance/operation attempts; app crash while an old delayed writer survives; launch before identity receipt; PID reuse; same-boot restore/Keep Current/uninstall refusal despite matching values; trusted new-boot read-only escape; bounded resolved retention and preserved legacy evidence. Status-item fixtures cover checking/busy/unknown/recovery with the popover closed; mixed-profile/mixed-choice dialog dismissal leaves unresolved cells intact. Document ABA/read-write limitation instead of a false test for impossible exclusivity.

All ordinary tests use fakes and scratch paths. Dedicated-Mac acceptance performs distinct-profile apply/update/restore and permission migration, records originals and final equality for touched cells, verifies untouched cells remain unchanged, and exercises interrupted/failed operations without losing recovery evidence. Native/demo state transitions must match. Run P1 gates and independent security/recovery review.

## Verification Checklist

- [ ] Every planned mutation has a durable original/intent and validated restoring value before execution.
- [ ] Touched ownership, operation-prestate rollback, readback, failed compensation and fresh resolved-session capture have passing tests.
- [ ] False Off/active success and destructive delete/reactivate guidance are removed; legacy acknowledgment is explicit and not labeled restored.
- [ ] New adapter/policy use profile selectors together; no successful migration retains broad or temporary -a authorization.
- [ ] Dedicated-Mac policy/profile/recovery acceptance passes with exact before/after receipts; fake tests alone do not meet this gate.
- [ ] Persistent execution fence, status-item truth, friendly deferred recovery and both migration paths have passing fixture plus required dedicated evidence.
- [ ] Native/demo parity, current-head CI/security and independent review pass; user merges. #36's lifecycle completion still references P5.

## What NOT To Do

Do not restore every captured key, overwrite unresolved originals, silently accept third-party changes, assume error means no side effect, compensate while a child may still run, treat same-user checksums as authentication, replay sleep after restart, or normalize a value into the allowlist. Keep one engine; no duplicate rollback in views or quit handlers.

## Context

- Source: claudna:forge; area: recovery/control; effort L; risk high; priority critical.
- Primary issues: #36, #54, #55, #57, #62, #65, #66. Completes recovery/policy portions of #72/#80 and missing-key portion of #79; all closure follows master ledger.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC04:** Added pre-launch durable execution fence, restart/PID gap rules and verified later-boot escape; ownership/retirement remain blocked while uncertain. Document correction independently verified.
- [x] **IC05:** Root controller UID compare-and-install, refusal/handoff, legacy ownership boundary and concurrent-account acceptance. Document correction independently verified.
- [x] **IC07:** Status-item state/accessibility is truthful in P4, with later presentation polish. Document correction independently verified.
- [x] **IC09:** Friendly mixed-profile recovery choices and non-destructive defer/dismiss, with raw detail and ownership meaning. Document correction independently verified.
- [x] **IC10:** Bounded one resolved receipt plus necessary unresolved generations/legacy evidence; safe pruning and retention disclosure. Document correction independently verified.
- [x] **IC11:** Compared bridge against interim disable; retained coherent-PR bridge with cost and direct legacy-to-final migration acceptance. Document correction independently verified.
