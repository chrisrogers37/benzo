---
title: "[plan] P3 — Bounded commands and explicit permission setup"
type: plan
status: draft
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-25
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size L, risk high. Replace blocking/unbounded child execution and misleading setup detection with a typed asynchronous runner and explicit finite account-scoped authorization. One PR on `codex/benzo-command-permissions`; the temporary exact `-a` policy deliberately matches the existing adapter until P4 changes both together.

## Evidence

`ShellExecutor.swift:90–109` waits before draining a combined pipe; the evaluation reproduced a 1 MiB deadlock. `:77–85` grants `%admin` numeric-prefix glob commands; `:43` probes a command absent from that rule; `:142` treats every exit 1 as cancellation. `BenzoViewModel.swift:62` automatically initiates repair. `PMSetService.swift:33,69` validates during sequential writes, so merely tightening the policy can strand original values after earlier writes.

## Implementation Plan

### Dependencies

P2 merged under the chosen schedule; F2 authorization/account model accepted. Packaging is not a technical runtime prerequisite: an isolated packaging stall requires a concrete owner-approved reorder/scope amendment, not silent delay/reordering of safety scope. C7 is normative. Dedicated-Mac authorization tests require scoped approval; never run them on this always-on host.

### Blocks

P4's reliable transaction transport and policy migration; P5/P6's caller/diagnostic integration.

### Steps

1. **Own files:** `Services/ShellExecutor.swift`, `Services/PMSetService.swift`, `ViewModels/BenzoViewModel.swift`, `Views/SetupView.swift`; new `Services/CommandRunner.swift`, `Services/ExecutionFenceStore.swift`, `Services/DurableFileStore.swift`, `Services/BootIdentityProvider.swift`, `Services/PermissionManager.swift`, `Models/PermissionPolicy.swift`, runner/policy/setup tests under `Benzo/BenzoTests/`; extracted React demo/state/fixtures and tests; setup documentation. Keep P1 injection rather than introduce another service layer.
2. Replace the `waitUntilExit(); readDataToEndOfFile()` pattern with `CommandRunning.run(request) async -> CommandOutcome`. Detailed skeleton:
   ```swift
   struct CommandRequest { let executable: URL; let arguments: [String]; let policy: ExecutionPolicy }
   struct CommandOutcome { let stdout: Data; let stderr: Data; let termination: Termination; let childStopped: Bool; let executionQuiescence: ExecutionQuiescence; let outputTruncated: Bool; let outputComplete: Bool }
   enum Termination { case exited(Int32), signaled(Int32), timedOut, cancelled, launchFailed(String) }
   ```
   Drain stdout/stderr concurrently from launch and keep them separate without blocking the main actor. Bound the **entire request**, including waiting for pipe EOF/drain/finalization after direct-child exit. Reserve bounded finalization within the total request deadline; at that deadline stop owned readers/close only local read endpoints and return incomplete/truncated output plus uncertain execution rather than waiting indefinitely. A descendant retaining inherited writers cannot extend the deadline. Do not kill unrelated processes to manufacture EOF. Enforce named bounded policies: pmset reads 10s/8MiB, profiler reads 30s/16MiB, mutation 15s/1MiB, interactive setup 120s/1MiB; tune only with recorded evidence. On output limits keep draining/discarding safely or terminate the owned child, never deadlock by ceasing reads. Cancellation/timeout operates only on known owned processes; uncertain privileged descendants yield `childStopped=false`, not invented success. Before any potentially mutating launch (including setup/retirement or sleep), `ExecutionFenceStore` durably records the C4 boot/app-incarnation/operation fence via the checked `DurableFileStore`; this starts in P3, not P4. Record launch uncertainty before any child identity exists. Clear only after proven whole foreground execution-chain completion using documented/tested transport semantics; direct-child exit alone is insufficient if descendants/EOF remain uncertain. The kernel-backed `BootIdentityProvider` must yield a trustworthy boot-session ID, otherwise mutation is unavailable. Same-boot pending fences survive restart and block writes, compensation, Keep Current/ownership release, install/repair/retirement and uninstall. If reliable same-boot proof is lost, a verified later boot is the conservative escape, followed by read-only reconciliation. No automatic reboot/kill. P4 consumes this fence and reuses the file-store adapter; it must not replace a pending fence with new state.
3. Keep direct executable/argv for all native reads/mutations. Introduce typed `PMSetKey`/accepted values and `PermissionPolicy` whose emitted commands exactly match validator inputs. The smaller alternative disables new interim control until P4 and prepares only final policy in P3. Retain the bridge here for coherent existing control/recovery per merged PR without a broken adapter; acknowledge the second migration and dedicated acceptance cost. Transitional policy has literal `-a` commands for hibernatemode 0/3/25 and six Boolean keys 0/1, plus exact sleepnow; no glob, argumentless pmset, generic shell, extra pairs or `%admin`. Validate **the complete apply and restore candidate** before issuing any command. An old original outside the finite set is an explicit migration blocker, never normalized or silently orphaned.
4. `PermissionManager.status()` returns `notInstalled`, `eligibleNeedsUpdate`, `ready(manifest)`, `notEligible(reason)` or `unknown(error)`. Read selected account identity/admin eligibility; do not infer from a file's existence. The installer creates a root-owned candidate, validates with visudo and performs checked replacement while preserving a usable prior rule until success. Use a strict validated UID/account representation to prevent rule-template injection. A root-owned controller manifest binds controlling UID, generation, policy version, exact canonical rule digest and active/retired status. Serialize installer compare-and-install under a root-owned exclusive lock, and recheck the stored UID inside the privileged boundary; second-admin install/repair cannot replace an active or uncertain owner. Concurrent callers refuse/wait boundedly; a stale/uncertain lock is a blocked repair requiring explicit review, never silently stolen. Write an in-progress record before replacing policy and mark active only after both rule and manifest verify; interrupted pair updates remain unknown. Prior-owner verified retirement is the only normal handoff. Legacy unknown-owner migration blocks until the owner identifies a prior controller and that account performs explicit reviewed recovery/retirement; absent substantiated ownership, preserve the existing rule/evidence for a separately reviewed administrator recovery decision. Never read other users’ homes.

   **Concrete inspection contract:** install a strictly read-only ACL for the selected account on the canonical `/private/etc/sudoers.d/benzo` (root-owned 0440; the known system `/etc` alias resolves here), with verified root-owned canonical parent directories and a root-owned non-user-writable manifest at `/Library/Application Support/Benzo/controller.json`. Do not mistake the known system alias for a user-controlled path, and reject substituted/untrusted symlinks. Open the actual canonical rule without following symlinks; verify root ownership, restrictive mode, only the expected read-only ACL, exact canonical bytes/digest and matching manifest/account/generation/status. Recheck metadata/bytes around secondary nonexecuting permission queries (`sudo -n -l <exact-command>`). Ready means this complete observation matched at the checked time; unreadable, drifted, malformed, partial or inconsistent state is unknown and blocks writes. Queries/cache or receipt alone never establish ready; existing unrelated sudo authority is outside the Benzo-grant claim. **Design prerequisite before privileged implementation:** demonstrate that supported macOS sudo/visudo accepts this precise read-only ACL policy on dedicated hardware and that the selected account can inspect but cannot modify it. If that fails, stop for a bounded design amendment; do not silently add sudo cat, world-writable metadata or a helper. No privileged write probe.
5. Explicit Install/Repair is the only route to authorization. Remove automatic launch install/update. Detect real AppleScript cancellation by its structured error code where available, not generic status 1 or an English substring alone; unrelated errors retain detail. Preserve old recovery evidence/rule on failed or unsafe migration. Successfully migrated installation must not retain the broad legacy rule alongside the finite rule. Setup discloses persistent account-wide grant, system power effects, removal path and excluded standard-account support.
6. Mirror eligibility, pending, ready, denial, cancellation and repair-error states in the React demo in this PR. Native UI need only be truthful/readable enough to explain the new behavior; P7 improves presentation, not missing states. Begin local structured operation logging with privacy-conscious IDs/error categories; P6 owns its final display.

## Test Plan

Use synthetic owned children only: >1MiB stdout/stderr, both streams concurrently, nonzero exits, launch failure, timeout, cancellation, output cap, early EOF and possibly-live child outcome. Include an owned parent that exits while its descendant retains both pipe writers; the request still completes by the total deadline with incomplete/uncertain flags. Test restart with pre-launch fence (before child identity), surviving delayed writer and PID reuse; matching values or reacquired lock cannot clear it. New-boot identity permits only reconciliation. Test two-admin/concurrent install/repair/retire refusal and interrupted manifest/rule pair updates. Assert main-actor responsiveness with an injected scheduler; never invoke real sudo/pmset to test the adapter. Policy fixtures reject appended argv, extra settings, arbitrary key, Unicode digits, overflow, bad account text and out-of-domain originals before any write. Setup tests distinguish cancellation from exit 1 and verify no initializer prompts.

Dedicated-Mac acceptance must prove actual NOPASSWD matching, rejected suffix/extra-argument variants, correct selected admin, other-admin replacement refusal, excluded standard account, read-only ACL inspection feasibility/tamper detection, explicit install/repair/migration failure behavior and native responsiveness. Tests of rule strings do not prove sudo's interpretation. Run P1 gates plus React setup state tests.

## Verification Checklist

- [ ] Bounded owned-child tests pass without pipe deadlock or accidental unrelated process termination.
- [ ] Complete candidate prevalidation and policy-command equality are tested; all uncertain child outcomes prevent subsequent writes.
- [ ] Launch performs no setup authorization; ready state requires the specified evidence; generic exit 1 is not cancellation.
- [ ] Exact temporary -a policy is internally compatible and legacy recovery prerequisites survive blocked migration.
- [ ] Dedicated-Mac policy/setup/account evidence is recorded before native acceptance; fleet host remains untouched.
- [ ] Native/demo setup parity, independent review and exact-head build/security checks pass; #80 remains open through P4 and its other rows.

## What NOT To Do

Do not weaken sudoers validation for convenience, count file existence as readiness, silently auto-repair, kill arbitrary process groups, assume cancellation means no mutation, or remove -a grants before the adapter stops emitting -a. This intermediate PR does not resolve flat-profile recovery; no public release until P4/P5 acceptance.

## Context

- Source: claudna:forge; area: process/permission boundary; effort L; risk high; priority critical.
- Primary issues: #63, #64, #67, #80. Shared #76 local evidence, #81/BZ-043(b), #82/BZ-047.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC02:** Bounded total request including EOF/finalization; inherited-descriptor fixture returns incomplete/uncertain outcome. Document correction independently verified.
- [x] **IC04:** Added pre-launch durable execution fence, restart/PID gap rules and verified later-boot escape; ownership/retirement remain blocked while uncertain. Document correction independently verified.
- [x] **IC05:** Root controller UID compare-and-install, refusal/handoff, legacy ownership boundary and concurrent-account acceptance. Document correction independently verified.
- [x] **IC11:** Compared bridge against interim disable; retained coherent-PR bridge with cost and direct legacy-to-final migration acceptance. Document correction independently verified.
- [x] **IC12:** Distinguished schedule from runtime dependency; packaging-only block requires owner-approved amendment. Document correction independently verified.
- [x] **Author design clarification:** exact installed-rule read-only ACL inspection and supported-macOS feasibility check replace the vague manifest placeholder. Unsupported feasibility blocks privileged implementation; no extra read grant/helper is assumed. Document correction independently verified.
