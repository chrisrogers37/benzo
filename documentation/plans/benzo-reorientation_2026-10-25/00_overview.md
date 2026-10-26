---
title: "[plan] Benzo re-orientation epic"
type: plan
status: active
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-26
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Re-orient Benzo around a small, explicit promise: **request sleep, see what changed, and return to prior supported settings without guessing.** This is an eight-PR delivery epic within the user's required ordering: structure/build (P1–P3), features (P4–P6), then UX/UI (P7–P8). The user approved Phase 3 implementation with recommended F1–F7 choices and their conditions on 2026-10-25. Publication, permission installation and deployment retain their separate scoped gates.

Phase 1 is complete and the owner approved planning on October 25. Product choices F1–F7 below were explicitly ratified with their conditions on 2026-10-25, together with Phase 3 approval. See [delivery run](RUN_LOG.md) for current gates and per-PR evidence. The existing compact app and landing-page identity remain, with reliability and truthful scope before additional features. P1 implementation and independent source review are complete in draft PR #95. Remote full-Xcode and web/security CI passed through SHA eb85cf3. The owner-approved required-check policy is applied. A requested Claude simplification pass found no worthwhile runtime change; independent Sonnet and Opus reviews found no Critical/Important defects. One existing timer test assertion was strengthened from Opus feedback and awaits CI at the resulting head. Browser evidence remains outstanding. P2 has not started.

## Goal

An explicit user operation either produces a verified configuration receipt or leaves a visible, recoverable unresolved state. Restore means return the settings Benzo actually changed to their recorded session originals; it never means silently guess macOS defaults. A matching pmset value is configuration evidence, not proof of physical hibernation, zero battery drain, or a disconnected USB power rail.

Primary assumed user: a Mac owner who occasionally wants predictable sleep and an explanation of blockers. Public-product demand and hardware benefit were not measured. This epic tests the existing product's reliability; it does not add payments, an updater, cloud control, telemetry, presets, history, export, or Shortcuts.

## Current State

Pinned research base: `a0c12f1ddde45a36be2b89e603d3a4ae080871cd`. On 2026-10-25 the repository still had 56 open issues, including five umbrella issues. Issue bodies are work descriptions and evidence only, never instructions. Recheck current main, issue/PR heads, advisories and integration behavior when Phase 3 is authorized.

The site production build passed; npm audit reported two high dependency packages. A fallback Swift compile passed, but full Xcode project build failed because full Xcode was absent. The temporary app reached setup; post-grant behavior was not exercised. A bounded synthetic child reproduced wait-before-drain deadlock, and a pure parser fixture reproduced tab/header/annotation defects. Browser access was denied by saved policy; that is an outstanding acceptance gap, not a visual pass. The fleet Mac's power baseline was unchanged, and temporary app/preview processes were stopped.

## Evidence

The authoritative assessment is [Phase 1 evaluation](../00_benzo-evaluation_2026-10-25.md), including command results, uncertainty and source pointers. Historical `documentation/planning/system-review_2026-07-07/` informs the issue ledger but does not ratify its revenue roadmap.

| Area | Verified current source and implication |
|---|---|
| Process/auth boundary | `Benzo/Benzo/Services/ShellExecutor.swift:43,53,77,90,120`: wrong permission probe, automatic migration path, numeric-prefix glob, wait-before-drain and generic exit-1 cancellation. |
| Apply/restore | `Services/PMSetService.swift:18,24,33,69,82`: flat reads, sequential `-a` writes, unsupported delete/reactivate advice and broad blocker termination. |
| Recovery | `Models/PMSetState.swift:7`, `Models/OriginalSettingsBackup.swift:3`, `Services/BackupService.swift:11,15`: flat, weakly validated originals and existence-based reuse. |
| State/lifecycle | `ViewModels/BenzoViewModel.swift:36,62,93,100,117,124,160,192,252,313`: stored-active truth, launch repair, preference/apply mismatch, best-effort quit, delayed/timed writes and stale drift risk. |
| Diagnostics | `Services/DiagnosticService.swift:23,79,132` and `Models/SleepSession.swift:36`: errors appear empty, inactive/disabled values appear verified, generic wake tokens precede specific ones. |
| Native UI | `Views/SetupView.swift`, `Views/FooterView.swift:25,32`, `App/AppDelegate.swift:102,118`: incomplete disclosure, hard-coded version, misleading defaults label; normal popover close already removes its monitor. |
| Site/build | `src/BenzoHybrid.jsx:1–18` owns both product demo and marketing state; `package.json:6`, `.github/workflows/security.yml:20` lack behavior/build gates; `scripts/build-dmg.sh:19,54,63` reuses a destructive workdir, silently falls back, and submits an app directory. |

Paths in this family are repository-relative unless absolute. Native shorthand `Services/`, `Models/`, `Views/`, `Theme/`, `App/` and `ViewModels/` is relative to `Benzo/Benzo/`. Bare `BenzoViewModel.swift` means `Benzo/Benzo/ViewModels/BenzoViewModel.swift`; other bare native filenames resolve to their explicitly named native subdirectory in the same Evidence/ownership section. `project.pbxproj` means `Benzo/Benzo.xcodeproj/project.pbxproj`; tests mean `Benzo/BenzoTests/`. Proposed new files/types are labeled **new**; they do not already exist. Evidence lines refer to the pinned base and will shift during delivery.

## Architecture

Keep the current ViewModel → service → direct argv boundary. Add narrowly justified interfaces and one serialized operation coordinator, not a daemon or general framework.

```text
SwiftUI / AppKit events → BenzoViewModel (requested + observed state)
                         → OperationCoordinator (one operation/generation)
                           → PMSetBackend → bounded CommandRunner
                           → PermissionManager → explicit installer
                           → DurableJournal → user-local recovery files
                           → injected Clock / LoginItemClient
Read-only diagnostics ────→ DiagnosticService → typed data/error results
React demo ──────────────→ equivalent visible state fixtures/reducer
```

The web demo never invokes native controls. Its state contracts mirror each behavioral PR immediately. P7/P8 polish is not permission to delay parity. Production composition lives at the app boundary; tests receive fakes and isolated storage without starting `AppDelegate` or the production ViewModel initializer.

### Shared control and recovery contract

**C1 — Truth and ownership.** Separate desired selections from observations. States: `checking`, `off`, `applying`, `activeVerified`, `restoring`, `recoveryRequired(detail)`. `activeVerified` is timestamped configuration evidence. Off requires no unresolved owned changes. Empty selection has no protection to activate. Ownership is one `(profile,key)` cell, only acquired if Benzo changes it. Already-target values are unowned. Preserve immutable session originals and a fresh pre-state for each later operation: failed checkbox edits compensate to that operation's pre-state; final Restore uses session originals. Newly acquired cells need fresh capture. A resolved session permits a new baseline; unresolved originals are never replaced.

**C2 — Scope and capture.** Read unprivileged `/usr/bin/pmset -g custom`, map reported `AC Power`, `Battery Power`, `UPS Power` to `-c`, `-b`, `-u`, and operate on all reported eligible profiles under F3. Do not invent absent profiles. New profiles require explicit new acquisition. Parse spaces/tabs; filter unrelated keys; reject missing required managed values, duplicates, malformed/non-ASCII/oversized integers and unexplained managed-value suffixes. Missing is not zero. A selected feature missing any required profile/key is blocked, not partially labeled enabled. Capability clues from `-g cap`/key presence do not establish hardware outcomes.

**C3 — Durable evidence before mutation.** One unresolved JSON journal stores schema/policy versions, session/operation UUIDs, revision, app/OS versions, timestamp, UID, local host fingerprint, source capture, profile/key originals, ordered preconditions/targets, per-step intent/outcome/readback and conflicts. Preserve raw capture and last valid generation. A checksum detects accidental corruption only, not same-user tampering. Use a 0700 directory/0600 files, reject symlinks/nonregular shapes and provenance/schema/value mismatch. Durability adapter must check writes, synchronization, same-directory atomic rename and directory metadata persistence before authorizing a command. Review the actual macOS/APFS sequence, including `fsync` versus `F_FULLFSYNC`; `.atomic` alone is insufficient and no disk-loss guarantee is promised. No host fingerprint or raw process/device data in default logs. Retention is exactly the current unresolved journal plus its required previous valid generation, and one last resolved receipt; keep unresolved/legacy originals separately until explicit appropriate resolution. Replacing the last successful receipt must not prune the sole unresolved original or retained legacy evidence. No successful-session archive/history product is created.

**C4 — Serialized apply and compensation.** A process-lifetime nonblocking account-local `flock` prevents a second cooperating writer. An explicit operation token prevents actor reentrancy across awaits. Validate the complete operation, origins, targets, policy and persistence before any write. Persist the complete plan/originals, then each write intent before execution. Recheck that each cell still matches expected pre-state. Execute exactly one profile/key/value argv, then read back even after nonzero exit/timeout: an error may have changed state. Stop forward progress on failure. Only when the child is proven stopped, reconcile attempted cells and compensate in reverse order where current still equals last written; verify compensation and retain every unresolved cell. A possibly live child forbids competing rollback. Final readback and successful journal commit precede success UI. **Execution uncertainty is independent of configuration ownership:** before launching any potentially mutating child, durably create a versioned execution fence with kernel boot-session identity, app incarnation, operation identity and launch state. Persist before launch, including the gap before any child PID/identity can be saved. P3 introduces this minimal fence and checked file-store adapter; P4 consumes/migrates it without discarding pending uncertainty. Same-boot uncertain execution blocks new writes, compensation, ownership release (including Keep Current), permission migration/retirement and uninstall. Current values, elapsed timeout, an acquired app lock or a bare/reused PID cannot clear it. A live app may clear only after verified completion of the whole approved foreground execution chain, using documented/tested transport semantics and its retained process ownership; if that proof is unavailable or lost on restart, remain fenced until a **verified later boot** from a kernel-backed boot identity provider. Failure to obtain a trustworthy boot identity stays unknown. A later boot permits fresh read-only reconciliation, never automatic restore/replay. Guidance says an earlier command may still be running and safe control must wait for completion proof or a later owner-managed restart on dedicated hardware; never reboot or kill automatically, and never restart this fleet Mac for testing.

**C5 — Restore and external change.** Current equals original: resolve without write. Current equals last verified Benzo value: restore original and verify. A third value: preserve it and present friendly setting and power-source names, capture time, qualified current-versus-original meaning and the ownership consequence, with raw profile/key/values in details. Offer explicit Keep Current and release ownership, or Restore Recorded Original Anyway only when execution uncertainty is clear. Dismiss/Defer/Escape keeps recovery unresolved and never defaults to overwrite. Read/permission failures remain unresolved. Equality cannot detect ABA/same-value external writes; read/write races remain possible because pmset has no documented compare-and-swap transaction. Benzo coordinates its own clients, not other admins or tools. Do not silently reapply drift.

**C6 — Restart and legacy.** Startup first evaluates the execution fence; same-boot unresolved execution permits observation only, with no configuration ownership release. When quiescence is established, startup performs read-only reconciliation. A prepared intent may have executed without a completion receipt, so reconcile planned/attempted cells; never replay sleep, automatically resume, restore or reapply. A missing journal plus legacy active/interrupted evidence is unknown recovery, not Off. Preserve corrupt/legacy/last-valid evidence. Flat `original-pmset.json` cannot supply per-profile provenance/touched-cell/completion facts. Offer explicit reviewed restoration only where original provenance can be substantiated, or explicit acceptance of the current observed baseline with acknowledgment that historical originals are unknown. Archive evidence; do not call the second choice “restored,” delete the sole original, or silently fan flat values across profiles.

**C7 — Permission model and migration.** F2 recommends one selected controlling admin account, never `%admin`; the persistent grant is usable by any process of that account, not app-specific. Accepted finite domains are hibernatemode `{0,3,25}` and six Boolean keys `{0,1}`: standby, autopoweroff, powernap, tcpkeepalive, proximitywake, womp. These are Benzo's supported values, not all macOS values. Reject an unrestorable original before acquisition. Explicit install/update/remove uses a root-owned validated candidate and checked replacement; never prompt on launch. Use an exact-byte installed-rule inspection and root-owned controller manifest; nonmutating `sudo -n -l` queries are secondary. The chosen bounded design is a strictly read-only ACL for the selected account on the root-owned 0440 rule, with root-owned non-symlink directories and a root-owned manifest binding controlling UID, generation, policy version, canonical rule digest and active/retired status. Inspect actual bytes, owner/mode/ACL/shape and manifest agreement at operation preflight; unreadable, changed, unrecognized or inconsistent installation is unknown and blocks writes. Verify supported macOS sudo/visudo accepts this read-only ACL design on dedicated hardware **before privileged implementation is adopted**; if it does not, stop for a bounded design amendment, not an extra sudo read grant/helper. Cached/unrelated sudo authorization or a receipt/default flag alone is insufficient proof. The privileged installer serializes compare-and-install against the root-owned controller record and rechecks UID inside that boundary. Another admin cannot replace an active/uncertain owner; only explicit verified prior-owner retirement permits handoff. Root/admin edits outside Benzo remain outside this guarantee. Unknown-owner legacy grants block automatic migration: identify the prior controller through the owner, have that account perform reviewed recovery/retirement using its own evidence, then hand off; if prior ownership cannot be substantiated, retain rule/evidence and require a separately reviewed administrator recovery decision. Do not enumerate/read other users’ homes. No glob, argumentless pmset, shell, arbitrary extra pairs or restoredefaults grant. P3 temporarily enumerates exact `-a` literals for compatibility with the existing adapter; it validates all apply/restore data before the first write. An unreadable/out-of-domain legacy original blocks migration while preserving old recovery prerequisites. P4 changes adapter and installed rule together to exact `-b/-c/-u` entries (at most 46 including sleepnow), removes `-a`, and requires its new policy. No public release before P4 and P5 acceptance. The alternative is to disable interim new control until P4 and only prepare final policy in P3. This plan retains the exact -a bridge so each merged PR has coherent existing control/recovery behavior without silently breaking the old adapter; it accepts the cost of a second policy migration and dedicated acceptance. Test direct v0.3.0 legacy → final P4 migration as well as P3 → P4, so users need not install an unpublished bridge. An unmigrated broad rule is a known blocked migration, never successful hardening.

**C8 — Lifecycle/timers.** All mutation callers share C4. Off/Restore/Quit/recovery failure/replacement sleep invalidates scheduled/delayed work immediately, clears countdown and increments generation; check it immediately before side effects. Timer uses frozen explicit intent, is not persisted, revalidates before firing and cancels into needs-user-action when new blockers appear. P5 first delivers the production typed/fresh blocker provider: compare observed assertion identity plus process identity (including reported PID and available incarnation/start evidence), never generated UI UUIDs or names alone; incomplete/unsupported identity, stale/partial/truncated/malformed/failed capture is unknown and cancels. The actual parser/adapter feeds scheduler tests; P6 extends this same provider. Any system sleep, including sleep initiated elsewhere, invalidates pending/queued expiry; wake never fires an overdue timer. P5 also implements the demo’s functional clock/frozen intent/countdown/cancel behavior; P7/P8 polish and reverify it. Never terminate another program's blocker. Remove the arbitrary 0.5-second delay in favor of verified readiness. Persist sleep intent, report “sleep requested,” never replay an ambiguous request. Graceful quit uses AppKit `terminateLater`, settles work, restores/verifies and offers Retry, Stay Open, or explicit Quit Anyway retaining the journal. Forced exit is recovered on next launch, not by a guaranteed callback. Launch-at-login state is OS-readback truth.

**C9 — Bounded diagnostics.** Typed success/empty/partial/failure/unknown states; only owned validated expectations can be verified. Local operation receipts and privacy-conscious structured logs explain failures. No remote collector, custom signal crash handler, automatic export or historical analytics. Hardware/OS coverage is a declared matrix; unknown remains useful and honest.

## Decision Forks

All seven recommended choices were **ratified with their stated conditions** by **Chris Rogers** on 2026-10-25: “OK, proceed with Phase 3 using the recommended F1–F7 choices and their conditions.” Alternatives remain below for decision provenance. F7 rights/channel confirmation and every outward/native gate remain separate prerequisites.

### F1: Product direction and implicit writes

- **Context:** Choose what success promises, not merely which implementation is convenient. **Ratifier:** Chris Rogers.
- **Options:** (a) explicit-action controller promising verified supported configuration/recovery, with physical claims only for observed qualified configurations; (b) retain physical sleep benefit as a required outcome on an owner-named initial hardware/OS/power target, with enforcement choices reviewed separately; (c) read-only/maintenance product after recovering existing users.
- If (b) is selected, name one initial target and its observable success criterion before implementation of the affected features; if dedicated evidence fails that criterion, return to the owner to choose narrower configuration-only scope or read-only retirement. Do not expand into a universal hardware or demand-research project.
- **Lean:** (a), reducing hidden writes while preserving bounded control. Remove automatic blocker termination. **Status: ratified, recommended option (a), with stated conditions; 2026-10-25.**
- **Evidence:** Phase 1 partial-write, stale-drift and broad-pkill findings; hardware benefit/demand still unmeasured.

### F2: Authorization and account boundary

- **Context:** Persistent convenience trades against installed authority and account scope. **Ratifier:** Chris Rogers.
- **Options:** (a) selected admin + finite exact persistent grant; (b) per-action administrator authorization and reduced unattended convenience; (c) signed privileged helper and additional service lifecycle scope.
- **Lean:** (a), with explicit account-wide grant disclosure and C7 migration. Standard/multiple controlling accounts are excluded. **Status: ratified, recommended option (a), with stated conditions; 2026-10-25.**
- **Evidence:** Existing one-time setup model and bounded seven-key controller; wildcard weakness is not arbitrary shell execution.

### F3: Profile and hardware scope

- **Context:** Define eligible profile scope and the evidence behind physical benefit under F1. **Ratifier:** Chris Rogers.
- **Options:** (a) all actually reported eligible profiles with visible scope and conservative unsupported/unknown states; (b) explicit per-profile selection; (c) no new mutation until a narrower hardware/profile product is selected.
- **Lean:** (a) for a configuration/recovery promise; physical claims only for observed declared combinations. If F1(b) is chosen, name its initial target, success criterion and return-to-owner failure rule rather than requiring universal Intel/Apple Silicon/OS/power/dock proof. No universal hibernation/USB claim. **Status: ratified, recommended option (a), with stated conditions; 2026-10-25.**
- **Evidence:** Existing `-a` intent versus flat capture; no dedicated hardware acceptance yet.

### F4: Recovery ownership and legacy resolution

- **Context:** Recovery must respect both recorded originals and external changes. **Ratifier:** Chris Rogers.
- **Options:** (a) touched-cell originals, optimistic conflict choices and explicit legacy acknowledgment; (b) own all managed settings and force whole-snapshot restore; (c) recovery-only retirement of mutation features.
- **Lean:** (a), C1–C6. Unresolved evidence survives failures; user may release ownership after consciously accepting current values. **Status: ratified, recommended option (a), with stated conditions; 2026-10-25.**
- **Evidence:** Stale backups, partial failures and external changes make whole-snapshot default unsafe.

### F5: Timer and quit behavior

- **Context:** Retain bounded scheduling convenience without surprising delayed writes or hidden quit failures. **Ratifier:** Chris Rogers.
- **Options:** (a) nonpersistent frozen timer; cancel on new blockers; Retry/Stay/Quit Anyway on failed graceful restore; (b) persistent timers with restart confirmation and additional product scope; (c) remove timer and allow only synchronous explicit sleep.
- **Lean:** (a), C8. Quit Anyway retains recovery evidence and clearly says settings may remain changed. **Status: ratified, recommended option (a), with stated conditions; 2026-10-25.**
- **Evidence:** Existing timer/delayed callbacks and swallowed quit failures. Forced termination cannot guarantee restoration.

### F6: Distribution acceptance

- **Context:** Choose how much distribution preparation earns its maintenance cost before signed publication is authorized. **Ratifier:** Chris Rogers.
- **Options:** (a) prepare explicit community and Developer ID modes; retain honest community route until exact notarized artifact is separately approved/verified; (b) community-only preparation now, explicitly reject/disable unsupported signed mode and retain signing issues open; (c) require Developer ID distribution before any public artifact; (d) source-only distribution.
- **Lean:** (a), accepting additional script/CI maintenance for a deferred signed-distribution benefit; (b) is a smaller acceptable alternative requiring a bounded P2 scope reduction if chosen. Both remove the current unsafe fallback/notary path. Developer ID is the preferred eventual public trust outcome, but this plan grants no credential use, Apple upload, release, tap or deployment authority. **Status: ratified, recommended option (a), with stated conditions; 2026-10-25.**
- **Evidence:** Build script's silent fallback/invalid submission, incomplete exact-artifact evidence and unavailable tap.

### F7: License and reporting channel

- **Context:** Existing marketing is insufficient evidence of rights or an operational reporting channel. **Ratifier:** Chris Rogers.
- **Options:** (a) formalize existing MIT intent after owner confirms rights, and use an owner-approved private security reporting route; (b) choose another lawful license/reporting route explicitly; (c) withhold license claims/new public distribution until ownership is resolved.
- **Lean:** (a), conditional on rights and channel confirmation; otherwise (c). No paid licensing system. Private vulnerability reporting settings remain a separately approved external action. **Status: ratified, recommended option (a), with stated conditions; 2026-10-25.**
- **Evidence:** README advertises MIT but LICENSE is absent; old monetization roadmap is not a decision.

## Phases

| PR | Deliverable | Group | Size / risk |
|---|---|---|---|
| [P1](01_build-foundation.md) | Safe test seams, site extraction, current dependency and build gates | Structure/build | M / medium |
| [P2](02_distribution-build.md) | Explicit artifact modes and verified packaging contract | Structure/build | M / high |
| [P3](03_command-permissions.md) | Bounded process execution and explicit finite permissions | Structure/build | L / high |
| [P4](04_recovery-engine.md) | Profile-aware recoverable transactions and truthful state | Features | L / high |
| [P5](05_lifecycle-retirement.md) | Lifecycle, timer, login and recovery-aware uninstall | Features | L / high |
| [P6](06_diagnostics.md) | Truthful diagnostics, preflight and local receipts | Features | M / medium |
| [P7](07_native-ux.md) | Readable, accessible native controls and demo parity | UX/UI | M / medium |
| [P8](08_site-trust.md) | Accessible landing page and accurate trust/distribution docs | UX/UI | M / medium |

## Dependencies

Critical path: P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8. P2-before-P3 is the chosen delivery schedule, not a runtime technical dependency of command/recovery safety on packaging. If packaging alone stalls safety work, return a concrete reorder/scope amendment to the owner; do not silently reorder, weaken artifact acceptance or change phase count. This deliberate sequential delivery matches the owner's ordering and avoids overlapping state/UI files on stacked branches. Independent bounded work inside a phase may use `claudna:delegate` with explicit file ownership, contract and acceptance; integration remains one PR. Do not parallelize dependent phase branches.

P2 may merge after real community artifact, script fixtures and required CI pass while Developer ID/notarization/release-specific outcomes stay open; those outward gates do not block P3 recovery work. P3–P5 require their stated dedicated-Mac behavioral evidence for acceptance.

External prerequisites are full Xcode CI, a separately approved dedicated test Mac and hardware matrix, browser policy that permits local checks, and owner decisions F1–F7. They are evidence gates rather than excuses to mutate the always-on host. If a phase cannot meet its required gate, leave its PR/delivery state blocked with precise evidence; do not silently substitute mocks or move to the next phase.

## Implementation Plan

### Dependencies

User approval and recommended F1–F7 ratification received on 2026-10-25. Phase 3 implementation is authorized subject to the retained gates. Native privileged acceptance must use dedicated hardware; ordinary tests must be incapable of affecting this Mac Mini's settings or fleets.

### Blocks

The epic blocks claims that all 56 issues are resolved or that a safe public release exists. Source implementation can prepare external distribution work, but gated outcome issues remain open until their own evidence or explicit owner scope change exists.

### Steps

1. At Phase 3 start, recheck main/issues/PRs/advisories and resolve pending decisions. Inspect Vercel Git integration **before any branch push/PR**: pushes may deploy previews. Obtain explicit approval for that deployment or have the owner disable the trigger. Do not silently alter account settings or add a deploy-ignore workaround. Repeat the deployment check before a user merge that would publish main.
2. Execute P1 through P8 in the linked order, each one `codex/<phase-slug>` feature branch from latest user-merged prerequisite and one PR. Never push main. Source-only build workflows use `contents: read`, no tag/release/tap/deploy step. Do not run the current destructive DMG script on shared paths while replacing it.
3. Each PR includes behavior-specific tests, current-head web/native build evidence, current npm audit and gitleaks, plus independent `claudna:review-work` after final changes. Address material findings and rerun only relevant checks/new concerns. User merges; automation does not.
4. Every native behavior/UI change carries React mockup parity and minimum truthful UI in the same PR. Use the master contracts C1–C9; reject copies of rollback, permission or lifecycle logic in separate callers.
5. Use `Closes` only for fully met scope on owner merge; otherwise `Refs` and an explicit remaining-evidence checklist. Execute the 18 proposed housekeeping closures only after the owner accepts those dispositions in Phase 3. Keep umbrella issues open until every child row below is fixed or explicitly dispositioned with reason.
6. Update this family after each merged PR with actual SHA/PR/check/review/manual receipts, changed assumptions and unresolved acceptance. Do not mark unchecked implementation criteria complete because the plan was reviewed.

## Test Plan

**Ordinary safe lane:** clean `npm ci`, `npm test`, `npm run build`, `npm audit --audit-level=moderate`, gitleaks; full Xcode Debug/Release build and unhosted XCTest on an appropriate runner. Pure injected native tests cover parser/policy/process ownership/journal fault transitions/races/diagnostic interpretation. No production app initialization, sudo install, pmset mutation, sleep, blocker termination or login registration.

**Dedicated native lane:** separately approved isolated Mac, baseline/recovery protocol, exact permission positive/negative tests, profile round-trip/interrupt/restore/quit/login/uninstall, visible native UI/assistive technology and declared hardware outcomes. These are required where phase acceptance says native behavior; fixtures are not substitutes. Universal binary architecture and physical compatibility are separate claims.

**Artifact lane:** safe script fixtures establish argv/error behavior; real approved archives establish effective architecture/signature/runtime; approved Apple submission/staple/Gatekeeper/clean-Mac install establishes trusted distribution for that exact artifact. Source/YAML/fixture success alone cannot close #31/#32/#34/#58/#59.

**Browser lane:** use an authorized local preview and record viewport/interaction/keyboard/reduced-motion/console/network/bundle measurements. Saved browser denial remains open; do not bypass it with another browser/CDP route. No invented field performance or accessibility scores. Production link/image checks require authorized deployment.

## Validation Strategy

Store commands, exit codes, exact commit/artifact hashes, test target identity, observed UI/hardware scope and limitation in each PR and this plan. Keep four claims separate: code complete, safe automated checks passed, native/browser accepted, external distribution accepted. Green CI does not prove unsupported hardware outcomes. Build changes do not authorize release. All implementation acceptance checkboxes start unchecked.

## Verification Checklist

- [x] Owner ratified recommended F1–F7 with conditions and approved Phase 3 on 2026-10-25.
- [ ] All eight PRs follow prerequisite merge, exact-head checks and independent review; user merges each.
- [ ] No fleet-host power/authorization/login/process changes are used for acceptance.
- [ ] Native transaction/lifecycle and exact artifact evidence gates are recorded, not replaced with source assertions.
- [ ] Every native behavioral PR includes equivalent visible demo states.
- [ ] All 56 issue dispositions and 29 original top-level BZ items have receipts or explicit accepted closure reasons.
- [ ] Outward actions, including automatic preview deploys, have their separate scoped authorization.

## Companion Plans

- [Phase 1 evaluation](../00_benzo-evaluation_2026-10-25.md) is the accepted assessment preceding this proposal, not an implementation completion record.
- Historical `documentation/planning/system-review_2026-07-07/00_overview.md` and security audit directory are superseded only for the delivery ordering/scope described here; their unresolved evidence is preserved in the ledger. Do not execute historical filing scripts or revenue tasks.
- Prior-art research confirms March security recommendations were partly superseded by May PRs #14/#15; July PR #50 delivered review documents, not recovery implementation; the Vite major change landed through #19/#89. Recheck current #92–94 rather than assume any open dependency PR is already accepted; #94 updates both React packages while #93 updates React only.

No other active delivery plan was identified. The phase documents link back here and share these contracts.

## Risks

| Risk | Impact | Mitigation / limit |
|---|---|---|
| Legacy originals cannot be reconstructed | Wrong restoration could damage intentional settings | Preserve evidence, explicit acknowledgment/provenance path, no invented defaults. |
| External writer races | Equality can miss ABA and read/write interleaving | Touched ownership, readback, explicit conflicts; no exclusive-control guarantee. |
| Timeout leaves privileged child uncertain | Compensation might race a late write | Track child outcome; unresolved state blocks competing rollback/new writes. |
| Durability implementation overclaims | A journal may not survive actual disk failure | Checked macOS primitives, fault tests, qualified guarantees, dedicated evidence. |
| P3/P4 policy mismatch | Tightened rule prevents recovery | Transitional exact -a policy, complete prevalidation, blocked unsafe migrations, atomic adapter/policy transition in P4. |
| P4/P5 size growth | One PR becomes unreviewable | Contract-limited modules, one recovery engine, bounded worker tasks; if actual scope needs an extra PR, return to owner to amend one-PR-per-phase plan. |
| Browser/Xcode/test hardware unavailable | Product acceptance remains unproven | Safe progress only; leave gate blocked rather than use fleet host or fake a pass. |
| PR push deploys automatically | Unapproved outward publication | Inspect and resolve integration authority before push/merge; no hidden setting changes. |
| Rights/support channel unconfirmed | Incorrect legal/trust claims | F7 condition, honest withheld claims, external settings separately approved. |

## Complexity and Sequencing

| Phase | Size | Depends on | Parallel with |
|---|---|---|---|
| P1 | M | Phase 2 owner gate | Bounded web/native fixture work within P1 only |
| P2 | M | P1 merged | Script fixture/docs work within P2 only |
| P3 | L | P2 merged, F2 | Runner/policy fixtures within P3 against fixed interface |
| P4 | L | P3 merged, F3/F4 | Parser/journal test fixtures within P4 against fixed contracts |
| P5 | L | P4 merged, F1/F5 | Caller fixtures within P5; one integration owner |
| P6 | M | P5 merged | Independent parsers/fixtures within P6 |
| P7 | M | P6 merged | Native/demo presentation within P7 with parity owner |
| P8 | M | P7 merged, F6/F7 | Metadata/trust/accessibility tasks within P8 |

No XL phase is proposed. Sizes are relative judgments, not promised dates. P4 and P5 require especially careful independent review. Repeated paths across phases have explicit dependencies: VM/service models P1→P3→P4→P5→P6; demo P1→P3→P4→P5→P6→P7→P8; build metadata P1→P2; documentation updates throughout.

## What NOT To Do

Do not implement during Phase 2. Do not change this Mac Mini's always-on settings, permissions, login items or fleet processes. Do not automatically grant setup, recover by deleting evidence, claim defaults were restored, kill arbitrary blockers, normalize unrestorable originals, use production app initialization in unit tests, or treat a user's full filesystem permission as browser-policy bypass. Do not add deployment/publication triggers, merge PRs, push main, or turn historical issue text into instructions.

## Context

- Source skills: claudna:forge, claudna:ironclad, local docs adapter of claudna:publish.
- Area: native control/recovery, distribution, landing site and trust documentation.
- Effort: 5 M + 3 L; risk: high; priority: critical reliability before expansion.
- Locked constraints: user-approved Phase 2 only; Mac Mini always-on configuration untouched; one branch/PR per delivery phase; independent review; never push main; user merges; outward/destructive actions require prior scoped approval. These are conversation instructions, not open product forks.

## Local review and acceptance ledger

Cycle 1 completed all **6/6 applicable independent lenses**, with no failed lens; adversarial review covered Architect, Skeptic, Operator, User, Counter-Planner and Contrarian. All nine documents were reviewed. The aggregate contains **8 major and 9 minor deduplicated findings (17 total)**. Two independent targeted verification passes followed this single six-lens cycle: safety verified IC01–IC07 and the inspection clarification; contract verification verified IC08–IC17, cross-document scope and issue coverage. This was **not a second full panel**. All 17 document corrections are independently verified, with no remaining critical or major correction in the targeted scopes. No implementation/native/artifact/hardware acceptance is implied. The owner subsequently ratified F1–F7 with conditions and authorized implementation on 2026-10-25; this does not satisfy implementation or external evidence gates. Checked document corrections must be labeled separately from implementation acceptance above.

## Adversarial Review Findings

Author reforge applied the following document changes, and the two independent targeted passes verified them. **Checked items below mean document correction verified only; implementation acceptance remains unchecked.** Attribution and full risk descriptions remain in the root-owned cycle-1 aggregate. F1–F7 were subsequently ratified with conditions by the owner; implementation acceptance remains separate.

| ID | Severity | Plan scope | Author disposition | Status |
|---|---|---|---|---|
| IC01 | major | P1 | Moved login-item seam/live exclusion and reachable setter fake test into the first phase. | [x] Document correction independently verified |
| IC02 | major | P3 | Bounded total request including EOF/finalization; inherited-descriptor fixture returns incomplete/uncertain outcome. | [x] Document correction independently verified |
| IC03 | major | P5/P6 | Moved real typed/fresh blocker identity parser/provider into P5; P6 extends it. | [x] Document correction independently verified |
| IC04 | major | P3/P4/P5 | Added pre-launch durable execution fence, restart/PID gap rules and verified later-boot escape; ownership/retirement remain blocked while uncertain. | [x] Document correction independently verified |
| IC05 | major | P3/P4/P5 | Root controller UID compare-and-install, refusal/handoff, legacy ownership boundary and concurrent-account acceptance. | [x] Document correction independently verified |
| IC06 | major | P5 | System sleep invalidates timer/queued expiry; wake never fires overdue work. | [x] Document correction independently verified |
| IC07 | major | P4/P7 | Status-item state/accessibility is truthful in P4, with later presentation polish. | [x] Document correction independently verified |
| IC08 | major | P5/P8 | Functional demo clock/frozen intent/countdown/cancel moves to P5. | [x] Document correction independently verified |
| IC09 | minor | P4/P7 | Friendly mixed-profile recovery choices and non-destructive defer/dismiss, with raw detail and ownership meaning. | [x] Document correction independently verified |
| IC10 | minor | P4/P6/P8 | Bounded one resolved receipt plus necessary unresolved generations/legacy evidence; safe pruning and retention disclosure. | [x] Document correction independently verified |
| IC11 | minor | P3/P4 | Compared bridge against interim disable; retained coherent-PR bridge with cost and direct legacy-to-final migration acceptance. | [x] Document correction independently verified |
| IC12 | minor | P2/P3 | Distinguished schedule from runtime dependency; packaging-only block requires owner-approved amendment. | [x] Document correction independently verified |
| IC13 | minor | P7 | Explicit SleepSetting.swift copy ownership and unknown-hardware rendered acceptance. | [x] Document correction independently verified |
| IC14 | minor | F1/F3/P8 | Made configuration/recovery versus named-target physical outcome success promise an explicit owner choice and reconsideration rule. | [x] Document correction independently verified |
| IC15 | minor | F6/P2 | Added community-only smaller alternative; dual-mode recommendation acknowledges deferred benefit/maintenance. | [x] Document correction independently verified |
| IC16 | minor | P5 | Prove Homebrew preflight/abort consumer before adding CLI; preserve evidence and unresolved issue if unsupported. | [x] Document correction independently verified |
| IC17 | minor | P5 | Added per-trigger immediate/next-launch/journal/evidence-lane termination matrix. | [x] Document correction independently verified |

Root-preflight clarifications (outside the 17 finding count): native shorthand path bases and per-fork Context/Ratifier are explicit. Author residual design clarification: P3 now specifies exact installed-rule read-only ACL inspection and a dedicated feasibility prerequisite; an unsupported ACL design blocks privileged implementation for bounded amendment, rather than implying receipt/query proof or silently adding authority. The independent safety pass verified this planning clarification; it remains a future validation gate, not a verified host capability.

- [x] IC01–IC17 document corrections independently verified after one six-lens cycle with six adversarial critics and two targeted verification passes.
- [x] F1–F7 recommended choices ratified with conditions and Phase 3 approved by the owner on 2026-10-25; no implementation completion implied.

## Retained handoff

`/private/tmp/benzo-phase2.QvD6Jx/` is deliberately retained for this active Phase 2 handoff; root `/root` owns it through the owner gate. It contains source research, current issue snapshot, draft family and subsequent review evidence. `/private/tmp/benzo-evaluation.ZF5P4x/` remains the Phase 1 handoff under the same owner. Do not delete during handoff; temporary OS storage is not a permanent archive. This family embeds the actionable contracts and issue scope so implementation does not depend on temporary files surviving.


## Complete issue disposition matrix

There are **38 owned issues and 18 proposed closures = 56**. “Close” means propose closing with the stated reason, never claim fixed. Duplicate closure retains the original useful acceptance in its canonical owner. “Owner” is accountable for the complete issue, including work/evidence in dependent phases; it does not mean that phase alone closes it. Use `Refs`, not an auto-close keyword, for an issue with unmet acceptance.

| Issue | Proposed owner/disposition | Exact scope and closure condition |
|---|---|---|
| #20 package version | P2, re-scope | Old 0.2.1 target is obsolete. Document whether website version is independent; make current manifests/checklist consistent with that policy. Do not invent a new native release or force the old number. Also #82/BZ-052. |
| #21 pink literals | Proposed close: optional cleanup superseded by #22 | No defect requires every distinct alpha/shadow to become a constant. P1 shares values only when extraction needs it, without changing visuals; full mechanical literal eradication is not selected scope. |
| #22 mockup extraction | P1 | Preserve the outside diagnostics/hint caller and current render/interaction state; splitting a file alone is insufficient. Include required visual evidence or record it outstanding. |
| #23 Swift constants | P1, narrowed | Centralize only repeated boundary paths/keys useful to the seams; bundle-derived footer version completed in P2. No mandatory all-constant abstraction. Retain bundle-version item under #82/BZ-044. |
| #24 spacing/type scale | Proposed close: optional cleanup | No demonstrated defect requiring a broad scale. Actual readability/accessibility defects belong to #43/P7; mechanical extraction may share repeated values without adopting the original full refactor. |
| #25 Vite 6→8 | Proposed close: source work complete | Package is already Vite 8/plugin 6 and evaluation build passed. State browser acceptance was blocked; fresh advisories are separate P1 work under #80, not grounds to re-open the completed major-upgrade task. |
| #26 DateFormatter cache | Proposed close: no measured need | Bounded five-session display; no measured slowdown. Reopen on profiling or increased data volume. Do not claim a performance fix. |
| #27 index keys | Proposed close: no current identity defect | Current arrays are fixed-order presentation data; original body explicitly permits leaving justified static indices. Dynamic future rows must use stable IDs as needed. |
| #28 hover rewrite | Proposed close: unsupported generalized claim | No specific rerender/hover failure shown. Keyboard/focus requirements remain in P7, but adding hover state everywhere is not required. Reopen with reproduction. |
| #29 VM size watch-list | Proposed close: superseded | P1/P4/P5/#82 own narrow seams justified by recovery and scheduling behavior; size alone does not require a generic split. |
| #30 justify no tests | Proposed close: superseded by #72 | Original rationale is false for pure parsers/policies and no longer fits observed defects. P1 documents actual fixture strategy instead of copying the no-tests text. |
| #31 trusted notarized distribution | P2, outcome stays gated | Full closure requires approved signing resources, exact accepted notarized artifact, installed signature and clean-Mac evidence. Do not claim zero Gatekeeper dialogs or drop truthful community-build instructions before outcome is achieved. |
| #32 universal build | P2 | Inspect current produced executable, not historical 0.2.1 evidence; require Release architecture check plus declared platform smoke matrix. Source settings alone do not prove a universal shipped binary. |
| #33 Homebrew route | P2 | Either verify supported tap end-to-end with separate authority to publish, or remove unsupported install instructions from all surfaces and use verified DMG route. Keep cask recovery/uninstall work in #75. No assumption loose raw casks work on current Homebrew. |
| #34 release automation | P2, prepare only | An artifact-only/manual build workflow is reviewable in this epic. Original tag→publish→tap criteria remain **open** unless owner explicitly narrows issue or later approves/enables and verifies them. No automatic tag/release/main push. |
| #35 Sparkle | Proposed close: out of selected scope | No updater/appcast/key generation in this epic. Manual verified downloads suffice for scoped plan; reopen if product choice changes. Not completed. |
| #36 interrupted activation | P4, with P5 integration | Durable recovery state plus launch reconciliation. Existing manual Restore exists; do not repeat the unsupported “no in-app way” absolute. Never blindly apply incomplete backup as “defaults.” |
| #37 crash reporting | Proposed close: superseded/re-scoped to #76 | Preserve local diagnostic needs. Explicitly reject remote collector/custom signal-handler implementation in this epic; os.Logger is not proof of crash stack collection. Original synthetic crash/stack acceptance is not claimed satisfied. |
| #38 SwiftLint/CodeQL | Proposed close: optional tooling deferred | Build and focused behavior/security checks are first. No generic lint-cleanup or new analyzer requirement without demonstrated incremental need. |
| #39 custom domain | Proposed close: out of selected scope | No domain purchase/DNS/site settings. Use existing verified origin in metadata. Reopen on owner domain choice. |
| #40 LICENSE and SECURITY | P8, mixed scope | License overlaps #60, but security disclosure scope is distinct. Document supported versions/scope and an approved reachable channel. Original PVR enablement is an external setting action, and original About/cask license details need reconciliation; docs alone do not close full issue. |
| #41 Privacy & Trust | P8 | Describe actual final reads/writes/local storage/permission ownership and recovery-aware uninstall. Distinguish native network behavior from site/font requests. Do not promise “narrow” rule until P3 acceptance or “nothing leaves device” across the website without checking. |
| #42 Developer ID | Proposed close: duplicate #31 | Preserve exact artifact/install proof in #31; correct impossible promise of no Gatekeeper warnings. |
| #43 contrast | P7 native owner, P8 web completion | Canonical native/web legibility issue, including setup disclosure, explanatory text, controls/focus; verify actual colors and rendered text. Do not close before both surfaces are checked. |
| #51 filing test | Proposed close: test artifact | Body is only “test”; no product scope. |
| #52 BZ-001 placeholder | Proposed close: duplicate #53 | Placeholder “Test body”; complete termination scope remains in #53. |
| #53 termination recovery | P5 | Shared graceful-termination policy, visible failures, and next-launch recovery for abrupt termination. No promise to run restoration after SIGKILL or guaranteed shutdown callback. Dedicated-Mac behavior needed. |
| #54 parser and backup | P4 | Whitespace/annotation parsing, source-profile identity, completeness and save/load validation; salvage legacy evidence, no delete/reactivate advice. Source parsing fixtures do not prove privileged restoration. |
| #55 false Off | P4 | Missing/corrupt/incomplete recovery data yields unresolved state with actionable evidence-preserving guidance; do not conflate saved originals and OS defaults. |
| #56 swallowed quit errors | P5 | One Retry / explicit Quit Anyway policy using P4 transaction state; never duplicate “best effort” restore implementation. Native termination acceptance required. |
| #57 partial writes | P4 | Canonical partial-apply/rollback owner; durable touched-key receipt and explicit unresolved rollback state. Include failures during compensation, not just all-or-nothing happy path. |
| #58 build notarization | P2 | Submit supported archive, validate version/signature/effective configuration, inspect rejection data; no signed-mode silent community fallback. Full credentialed path remains unproved until actual approved notarization. |
| #59 hardened runtime | P2 | Verify effective Release runtime/signature; entitlements only as actually required. Empty entitlements file or a setting in source is not notarization proof. |
| #60 license strategy | P8, owner decision | Reconcile advertised license and actual LICENSE after explicit owner selection. No paid-license system or monetization prerequisite. Do not close as duplicate #40 while choice is unresolved. |
| #61 startup/drift truth | P5 | Requested versus observed state at launch/wake, invalidation of stale drift callbacks, durable interrupted operation handling. Do not blindly reapply stored active flag. |
| #62 checkbox failure | P4 | Desired/applied/pending semantics reflect complete or partial result; safe compensation and recovery remain visible. Native + demo update same PR. |
| #63 blocking commands | P3 | Some reads already run off-main; fix demonstrated wait-before-drain hang and blocking mutations with bounded process ownership/cancellation. Synthetic owned-process proof plus native UI responsiveness. |
| #64 unexplained repair | P3 | Explicit repair action, truthful probe permitted by intended rule, visible result/errors, correct cancellation. No privileged launch-time surprise. |
| #65 no selected settings | P4 | Define empty-selection inactive/no-protection semantics; never label Deep Sleep On after no-op. Mirror in demo. |
| #66 stale baseline | P4 | Fresh baseline for new resolved session only; never overwrite unresolved originals. Multi-session/external-change fixtures required. |
| #67 non-admin setup | P3 | Accurately show admin eligibility and permission capability. Standard-account support is not selected scope; don't claim it was added. |
| #68 pending timer | P5 | Deactivate/restore/quit/config changes and system sleep invalidate timer/queued work; wake never fires overdue work. Production blocker identity/failure and functional demo timer land here. Actual exited process cannot retain its timer; race tests use owned mock executor. |
| #69 missing tap | Proposed close: duplicate #33 | Preserve modern Homebrew limitation and correct all documented routes under #33. |
| #70 release automation | Proposed close: duplicate #34 | Preserve original publication/tap scope as blocked or explicitly narrowed, not silently completed by build CI. |
| #71 build CI | P1 | Both frontend and full native project compile gates with current security jobs. A fallback `swiftc` compile is insufficient; repository required-check settings are external acceptance if change is necessary. |
| #72 useful tests | P1 owner through P6 | Start fixture harness/seams in P1; regression cases ship with owning behavior PRs. Close only after parser, backup, sudoers policy, recovery and diagnostics contracts are exercised—not on an empty test target. No arbitrary coverage percentage. |
| #73 social image | P8 | Real correct-size image and valid absolute metadata URL; local asset check establishes repository correctness, production fetch requires approved deployment and remains a separate receipt. |
| #74 shared settings | P5 with P3/P4/P8 | Correct `-a` definition (all power sources); disclose machine-wide policy versus user-local recovery. Define ownership/external-change behavior. Do not add speculative multi-user enumeration. |
| #75 uninstall | P5 | Restore/verify before removing grant, preserve originals on any failure and in zap; direct-DMG cleanup path. Actual Homebrew ordering and macOS permission flow require dedicated acceptance. Never delete cask merely to close it. |
| #76 observability | P6 owner; starts P3/P4 | Local structured errors/receipts with no hidden sensitive data; evidence-preserving guidance, visible diagnostics failures. Remote telemetry/custom crash handlers excluded. Crash-capture coverage remains unclaimed. |
| #77 Sparkle | Proposed close: duplicate/out-of-scope #35 | No updater added. Link reason from #35. |
| #78 diagnostics umbrella | P6 | All five original BZ items below need explicit outcome; log/USB variants remain verification hypotheses until evidence. |
| #79 lifecycle umbrella | P5 owner through P7 | All six original items below plus confirmed stale drift race must resolve or be explicitly closed with a qualified reason. Do not close after timer fix. |
| #80 security umbrella | P3 owner through P4 | Original two items below plus newly observed sudoers wildcard/current advisories. Do not close because old Vite major already landed. |
| #81 landing umbrella | P8 owner; work starts P1 | All seven original items below, with five mockup gaps and three delivery/font/copy subitems separately accounted. Native behavior parity ships continuously; the functional demo timer ships with P5, while P8 owns final presentation/trust acceptance. |
| #82 Swift debt umbrella | P1 owner through P7 | All nine original items below. Narrow proven needs; hypotheses may close with explicit rationale. No broad “debt cleared” claim. |

## Mandatory item-level umbrella ledger

### #78 — five original items

| Item | Owner | Proposed disposition and evidence |
|---|---|---|
| BZ-024 inactive/disabled green verification | P6, depends P4 | Fix confirmed semantics: inactive N/A, disabled/untouched/unknown separate from verified; compare only owned expectations for a validated session. A saved checkbox is not observed state. |
| BZ-029 log parsing | P6 | Add representative supported-format fixtures, unmatched/malformed input and useful parse-failure states. Wider locale/OS failure is a hypothesis; document bounded coverage or close that broader claim with explicit evidence, never assert universal parser support. |
| BZ-030 User wake false positive | P6 | Specific tokens before generic User; regression fixture for UserActivity and power-button labels. |
| BZ-032 Apple Silicon USB panel | P6 | Reproduce against representative profiler output before adding data types. If only USB data is supported, label its scope and unknown/unavailable state honestly; retain hardware coverage gap or close original universal-empty claim with reason. |
| BZ-050 diagnostics errors look empty | P6 | Carry typed failure/partial results through native and demo UI. Genuine empty datasets remain distinguishable. |

### #79 — six original items, plus evaluation-added drift race

| Item | Owner | Proposed disposition and evidence |
|---|---|---|
| BZ-023 delayed sleep | P5/#68 | Cancellable operation identity/generation; deactivate/restore/quit prevents later write. Deterministic delayed-callback regression. |
| BZ-025 missing backup keys | P4/#54/#55 | Missing required touched-key originals block unsafe restore/disable and remain unresolved. No guessed defaults fallback or silent skip. |
| BZ-026 kill all caffeinate | P5 | Proposed explicit-action default: report blockers, don't kill unrelated processes. If selected termination is later wanted, explicit user selection and ownership checks need separate acceptance; merely replacing pkill with guessed PIDs is insufficient. |
| BZ-027 login-item toggle | P5 | Read back OS registration status after success/failure; demo mirrors pending/failure states. Real registration only on approved dedicated Mac. |
| BZ-028 global monitor leak | P7 | Verify reachable alternate close path and nil result; normal close already removes monitor. Bounded callback cleanup if reproduced; otherwise close hypothesis with inspected paths/native observation, not an invented leak fix. |
| BZ-031 Intel/Apple Silicon differences | P6 | Capability matrix can say unknown/unsupported safely. Hardware benefit and compatibility need declared supported OS/chip/dock evidence; do not treat architecture detection or pmset write success as hibernation/power proof. |
| Added: stale drift completion | P5/#61 | Invalidate/read-check operation identity before writes; off/restore/new operation wins over stale callback. Deterministic interleaving fixture. |

### #80 — two original items, with retained new findings

| Item | Owner | Proposed disposition and evidence |
|---|---|---|
| BZ-033 backup permissions | P4 | Verify actual directory/file mode and atomic replacement behavior; owner-only storage is hygiene. Do not imply mode 0600 protects against other code running as the same user. |
| BZ-033 backup integrity | P4 | Validate schema/source/key/value/completeness and safe ownership. Same-user malicious rewriting is not solved by an unkeyed checksum; do not overclaim integrity or invent a secret store. Preserve valid legacy evidence and reject untrustworthy values. |
| BZ-042 env ignore | P1 | Add appropriate env/secret-artifact ignore policy without untracking legitimate templates; verify tracked state separately. No leak was observed and ignore rules are not remediation of a hypothetical past leak. |
| BZ-042 Vite major | Proposed item close: done in source | Retain fresh advisory remediation under P1 and acceptance of the actual resulting lockfile. Old version target is obsolete. |
| Added: current source-map-js/Vite advisories | P1 | Review current dependency PR heads/advisories, choose minimal compatible resolution, build/audit/gitleaks. Never merge automatically. |
| Added: sudoers wildcard | P3 | Exact allowed command/value shape that cannot absorb appended arguments; generated-policy fixtures and approved dedicated-machine verification. Distinguish extra pmset authority from arbitrary shell/root-file access. |

### #81 — seven original items, expanded subitems

| Item | Owner | Proposed disposition and evidence |
|---|---|---|
| BZ-038 monolith | P1/#22 | Mechanical extraction preserving external caller and state; no arbitrary line-count requirement. |
| BZ-039 accessibility | P8 | Semantic controls, keyboard/focus, accessible state, no nested interactive CTA, reduced motion; native behavior parity is already current when this lands. |
| BZ-040 SEO | P8 | Canonical/og:url/robots/sitemap and justified SoftwareApplication metadata using existing verified origin and real version/download facts. No custom domain. |
| BZ-041 OS copy | P8; correct in earlier touching PR if needed | Ventura 13+ or actual current deployment target everywhere; no unsupported Catalina promise. |
| BZ-043(a) Launch at Login | P1 seam / P5 behavior | Demo includes native control/status/failure behavior in same PR as login truth changes. |
| BZ-043(b) first-run/setup | P3 | Demo includes setup/eligibility/permission/repair states in same PR; P7 later polishes readability. |
| BZ-043(c) friendly blocker name | P6 | Demo and native present consistent scoped process labels without hiding useful identity. |
| BZ-043(d) options default | P7 | P1 extraction stays mechanical. P7 explicitly aligns the demo options default with the native initial state and records this intentional parity correction. |
| BZ-043(e) missing womp | P8 | Include actual seven managed keys/labels with Wake-on-LAN meaning, not physical USB-wake prevention. |
| BZ-053 vercel.json | P2 verify / P8 final disposition | Missing file alone is no defect. Inspect actual build assumptions; add config only for a reproducibility need, or close with static Vite/default behavior rationale. No deployment/account setting mutation. |
| BZ-054(a) direct download | P2 artifact contract / P8 link | Only use a stable verified produced/released artifact URL. If release publication is not authorized/completed, honest releases link remains; state original deep-link condition unmet or explicitly narrow. |
| BZ-054(b) fonts | P8 | Self-host existing licensed font assets if practical and allowed; verify request behavior. Otherwise disclose third-party font requests and explicitly close/defer self-hosting with reason. |
| BZ-054(c) notarization copy | P2/P8 | Conditional on exact actual distribution mode. Do not say notarized or remove community guidance because build script was fixed. |
| Related #43 / #73 | P7 / P8 | Contrast and social asset have distinct canonical acceptance; link them without implying all umbrella items resolve together. |

### #82 — nine original items

| Item | Owner | Proposed disposition and evidence |
|---|---|---|
| BZ-037 VM/DI | P1 foundation; P4/P5 focused separation | Inject executor/store/clock as tests actually need; recovery controller and cancellable schedule boundary own their behavior. No full split driven only by line count. |
| BZ-044 footer version | P2/#23 | Bundle version with a safe fallback and consistent release metadata; mirror displayed demo version policy. |
| BZ-045 force unwrap/IUO | P1 verify | Inspect reachable initialization/failure paths; fix a demonstrated crash path or close particular hypothesis with rationale. Do not mandate mechanical replacement of all IUOs. |
| BZ-046 dead code | P1 inspection; P7 native view input | P1 removes the unused web count and retains persisted `capturedAt` for P4 provenance. The native `MasterToggleView.activeCount` input is unused; leave its adjacent view cleanup to P7. `killCaffeinateProcesses` is reachable and its behavioral removal belongs to P5. See the delivery receipt; no broad dead-code completion claim. |
| BZ-047 cancellation catches | P3 | Distinguish actual AppleScript cancellation from status 1/general error; remove unreachable noninteractive cancellation catches, preserve reported operational failure. |
| BZ-048 empty Settings | P7 verify | Confirm native reachability first; remove a genuinely unused/blank scene or provide only a needed existing function. No new settings product surface just to fill it. Close unsupported risk explicitly. |
| BZ-049 icon color | Proposed item close: no observed drift | Current icon color matches theme. Share token only if adjacent theme work earns it; no claim that current visual mismatch exists. |
| BZ-051 plist/build number | P2 | Inspect effective generated plist; one authoritative value, non-colliding release build-number policy without creating release/tag. Duplicate declaration alone need not be a runtime defect. |
| BZ-052 package drift | P2/#20 | Document separate-site versus app version policy, align chosen metadata, replace stale 0.2.1 instruction. |

## Closure blockers and unresolved owner decisions

These are **remaining evidence/scope boundaries**, not reasons to halt safe planning or to ask for repeated approval now:

- **Exact release/signing outcome:** #31, #32, #34, #58, #59; #42 duplicates #31. P2 may produce complete source/workflow changes while these remain open. #33 needs either verified installation route or complete removal of unsupported claims. #81 download/notarization subitems depend on the actual route. Developer enrollment, credential use, publishing, tap creation, release triggers and deployment require scoped outward authority.
- **Full native build/CI:** #71 and fixture execution for #72 require full Xcode/project validation; this host currently had only Command Line Tools in the evaluation. Current security checks must pass again. Runner availability/required-check settings are not inferred from source YAML.
- **Dedicated-Mac privileged/lifecycle acceptance:** #36, #53–#57, #61–#68, #74, #75, and #79's timer/login/hibernation coverage cannot be described as fully accepted from mocks alone. #63 can prove the synthetic pipe hang fixed safely, but native responsiveness still needs observed app behavior. No setup grant, pmset write, sleep, blocker kill, login registration or uninstall experiment on the always-on fleet host.
- **Hardware/OS fixture limits:** #54's profile round-trip and #78/#79's log, USB, Intel/Apple-Silicon capability claims require representative data or narrowed support claims. Unknown remains a valid product state. Universal architecture does not prove universal sleep behavior.
- **Browser/native UX:** #22, #43, #81 and reached native Settings/popover hypotheses in #82 need rendered/interaction evidence; browser saved-policy refusal and native accessibility timeouts are not passes. Production #73 asset availability requires the later approved deployment, not just a local file.
- **Owner choices:** license under #60/#40, approved security-reporting route/PVR under #40; controller direction and Off/Restore/Quit/competing-change ownership under #36/#54/#55/#57/#61/#66/#74; supported hardware scope and unrelated-blocker policy under #79. The plan can recommend conservative defaults, but it must label them as proposed until accepted. No paid licensing, updater, domain or remote crash product is added.

## Count check

Primary owners: P1 5; P2 7; P3 4; P4 7; P5 7; P6 2; P7 1; P8 5 = **38**.

Proposed issue closures: **#21, #24, #25, #26, #27, #28, #29, #30, #35, #37, #38, #39, #42, #51, #52, #69, #70, #77** = **18**.

The five umbrellas contain **29 original top-level BZ items** (5 + 6 + 2 + 7 + 9), all covered above; multi-part BZ-033, BZ-042, BZ-043 and BZ-054 are expanded so no subitem disappears. Added evaluation findings have separate owners rather than being mistaken for original issue wording.
