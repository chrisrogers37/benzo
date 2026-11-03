---
title: "Benzo remediation after YAGNI review"
type: plan
status: active
owner: claudna:audit
created: 2026-11-02
updated: 2026-11-02
tags: [tech-debt, reliability]
repos: [chrisrogers37/benzo]
x-execution-order: [03_lifecycle, 01_command-permissions, 04_diagnostics, 02_recovery-engine]
---

# Benzo remediation after YAGNI review

## Summary

The owner accepted the November 2 YAGNI recommendation: remove surprising automation, preserve recovery, and build further manual control only when a real use case justifies it. This revision replaces the six-phase queue with **three bounded preparation/correction PRs and one conditional final controller PR**. Two former phases become decisions, not implementation work.

Immediate containment removes timers, blocker killing, automatic drift writes and launch-time permission mutation. Selections freeze before edits while active/recovery evidence remains. Manual Sleep Now is temporarily unavailable until the final controller establishes readiness; its queued half-second continuation is removed. Remaining legacy apply/restore/quit defects stay explicitly unresolved. Intermediate PRs do not constitute a safe native release.

One actual owner workflow and initial hardware/OS/power target can justify new control; no telemetry or market-research project is required. Existing users' recovery obligations remain even if new control is declined.

## Authority and baseline

This accepted scope amendment supersedes this family's former requirement to retain all features and execute canonical P2–P8 unchanged. Old canonical plans are design references, not authority to reinstate removed scope. Packaging remains a release requirement where applicable, not a predecessor to source containment.

The safety obligations of retained privileged writes remain: correct durable originals, full validation, serialized admission, cooperating-instance exclusion, honest execution uncertainty, readback, conflict preservation and truthful restoration/quit. The [canonical C1–C7 contracts](https://github.com/chrisrogers37/benzo/blob/eed0a969b097142042dc4412424fbc71a04d2c0d/documentation/plans/benzo-reorientation_2026-10-25/00_overview.md#L63) explain them. Their live-edit, timer, temporary-policy and standing-grant choices are amended here.

Source is verified main `eed0a969b097142042dc4412424fbc71a04d2c0d`. Primary local source remains `a0c12f1ddde45a36be2b89e603d3a4ae080871cd` with pre-existing todo/canonical-plan work; it is not the implementation base. Refresh symbols/heads on the actual parent. This revision changes only this seven-document family, not those existing files, source, issues or PR #98.

## Scope decisions

| Decision | Reopen only when |
|---|---|
| Remove unattended timers and the identity-comparison subsystem | A recurring unattended workflow and supported identity/acceptance evidence justify it |
| Freeze active selections; restore/resolve before editing | Restore-before-edit materially obstructs an actual recurring task |
| Skip the unpublished exact `-a` bridge and second migration | A useful independently distributed intermediate controller is specifically needed |
| No new standing-grant implementation by default | Repeated per-operation authorization prevents the demonstrated workflow |
| Keep diagnostics small | A specific support case requires another panel, format or measured claim |
| No standalone helper cleanup | Its file is already changed and a fresh caller search still finds none |
| Routine dependency maintenance | Existing Dependabot cadence, applicable advisory, bug or compatibility need |

These are intentional behavior changes, not semantics-preserving cleanup. Native UI, active demo and copy must reflect retained and removed behavior in each implementation PR.

## Execution order

Filenames preserve existing links; **this table, not numeric order, controls execution**. Shared ViewModel/dependency/demo ownership is sequential, one branch/PR per actionable document.

| Order | Document | Deliverable |
|---|---|---|
| 1 — IN PROGRESS | [03 — Immediate containment](03_lifecycle.md) | Remove timer/kill/drift/launch mutation, freeze selections, disable delayed sleep, preserve cask recovery prerequisites. No new engine. |
| 2 | [01 — Bounded reads and authorization preparation](01_command-permissions.md) | Reusable bounded read transport and non-authorizing observation. No temporary grant or partial async mutation migration. |
| 3 | [04 — Truthful existing diagnostics](04_diagnostics.md) | Adopt bounded reads, distinguish failure/empty, reject stale completions, show neutral observed settings. |
| Conditional | [02 — Final frozen manual sessions and recovery](02_recovery-engine.md) | One final safe operation/authorization/recovery boundary after the gates below. Actual legacy recovery need independently justifies its bounded recovery scope. |
| No PR | [05 — Helper cleanup decision](05_unused-parser.md) | Closed as a standalone project; optional adjacent deletion. |
| No planned PR | [06 — Dependency maintenance decision](06_web-dependencies.md) | Ordinary maintenance, independent of native phase completion. |

No public native release of incomplete safety slices. If 02 is not justified, explicitly scope a recovery-only/read-only endpoint; do not release unsafe remaining manual controls or silently abandon existing users. Plan completion or green tests do not authorize push, merge, preview deployment or release.

## Conditional controller gate

Before implementing 02, record:

1. One actual task, target Mac/OS/power profile and useful outcome. Explicit configuration control may itself be valuable; a changed pmset value does not prove physical hibernation or battery benefit.
2. Necessary settings and reported supported profiles on that target. Do not invent absent profiles or generalize one machine's outcome.
3. Exact authorization transport and same-account recovery behavior. Per-operation authorization is a preferred candidate, not a proven design. Settle foreground-chain completion/cancellation, legacy-grant retirement and dedicated-host feasibility before code depends on them.
4. Legacy recovery separately: available originals/provenance, unknowns and grants/data that must survive. Flat backups cannot be silently expanded into per-profile originals.

A personal need is sufficient; no market-size or payment evidence is required. Actual supported legacy recovery need can justify recovery work without approving new acquisition. If the necessary write guarantees cannot be established, keep mutation unavailable instead of weakening them.

## Complete audit disposition

Original blast-radius / complexity / incorrect-fix risk scores use 1 low–5 high; they are qualitative, not a mandate to build every remedy.

| Finding | Priority; score | Evidence and disposition |
|---|---|---|
| F1 stale timer/drift writes | High; 4/4/5 | `BenzoViewModel.swift:163–190,195–229`: remove these paths in03; remaining async work rejects stale results. |
| F2 false/partial restore and quit | High; 5/5/5 | `BenzoViewModel.swift:119–123,275–299`, `PMSetService.swift:25–52`:03 preserves evidence/removes destructive advice;02 owns final safe restore/quit. Still open. |
| F3 unbounded wait-before-drain | High; 4/4/4 | `ShellExecutor.swift:76–94`:01 supplies bounded reads;04 adopts them. Mutation-chain completion stays open until02. Timeout is not proof a writer stopped. |
| F4 probe/grant mismatch | Medium; 3/4/4 | `ShellExecutor.swift:25–32,63–69`:01 stops presenting probe/cache as authorization truth;02 settles final authorization. No temporary grant enlargement. |
| F5 errors become empty/false assurance | Medium; 3/3/3 | `DiagnosticService.swift:7–8,63–69,124–131`, `DiagnosticView.swift:149–152`:04 carries errors and neutral observed values; preserves the existing empty-settings error guard at180–181. |
| F6 unused parser | Low; 1/1/1 | `DiagnosticService.swift:177–183`: no standalone PR; fresh caller evidence decides adjacent deletion. |
| F7 older tool minors | Low; 2/1/2 | Prior audit found no vulnerabilities. Existing weekly grouped npm Dependabot covers routine maintenance; refresh evidence when proposing an update. |

Native shorthand is under `Benzo/Benzo/`; each actionable plan gives exact paths/call sites. Do not close an issue merely because a feature is deferred or a document changed.

## Shared verification

- Use current test seams and required CI; add only focused regression cases for changed behavior. No new harness/framework.
- Record actual parent/head and affected checks plus required project gates. Historical receipts are not fresh execution.
- Caller-audit removed timer/kill/drift/setup paths and migrated interfaces; verify Xcode target membership for added native files.
- Mirror visible changes in `src/landing/NativeAppDemo.jsx`, `src/demo/useBenzoDemo.js`, `src/design/appPresentation.js` and relevant copy/tests. Preserve historical BenzoHybrid/BenzoMockup sources/tests. Correct stale contributor parity guidance in the first affected implementation PR.
- Test intended feature removal, not parity with removed timers/live editing. Browser, native build/tests and physical outcomes are separate evidence.
- Tiny adjacent cleanup uses proportionate affected checks, not a new validation project.

Historical audit on eed0a96/Node24.22.1 passed `npm ci`, 33/33 tests, build and moderate audit with zero vulnerabilities. No application tests rerun for this markdown revision. Full native Xcode/physical acceptance was not performed.

## Host and release boundaries

The always-on fleet host must not launch production Benzo, change power/grants/login items, sleep/reboot, terminate blockers, or install/uninstall for acceptance. Use the established separately approved dedicated host. Removing cask delete/zap assumptions preserves prerequisites; it does not prove safe uninstall or grant retirement.

No daemon, generic framework, new scheduler, general CLI, telemetry/history/export, duplicate store or second coordinator. Preserve uncertain execution and unresolved originals. Source work remains unmerged/undeployed until the owning workflow actually authorizes and verifies those actions.

## Review history

The first consistency review produced four document corrections. The later independent Architect, Skeptic, Operator, User and Counter-Planner review challenged scope; all recommended narrowing. This revision implements that recommendation. Earlier no-blocker conclusions do not certify this rewritten family. Fresh scoped verification is recorded below.

## Review of the YAGNI revision

On November 2, 2026, two independent subagents performed targeted safety and YAGNI verification of all seven revised documents against the accepted scope and source snapshot `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both returned **NO FINDINGS**. This follows the earlier five-angle review that recommended narrowing; it is not a new broad audit.

The verification covered execution order, the scope amendment, removed automation, independent legacy-recovery obligations, and the prohibition on releasing incomplete native safety slices.

This verdict concerns the revised documents. Implementation, authorization feasibility, native acceptance and release remain unverified; the unchecked implementation gates remain open. No application tests, native actions or network operations were performed by these two reviewers.

## Implementation checkpoint — 2026-11-02

03 is implemented locally on `implement/benzo-containment` from `eed0a969b097142042dc4412424fbc71a04d2c0d`; see its checkpoint for verification and review. It remains active: native Xcode/XCTest and remote CI are unverified, and branch publication awaits separate preview/push authority. No dependent phase has started; no merge or release occurred.
