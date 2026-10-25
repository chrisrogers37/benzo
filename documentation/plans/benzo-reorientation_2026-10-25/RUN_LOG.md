---
title: Benzo re-orientation delivery run
type: plan
status: active
owner: claudna:build-all
created: 2026-10-25
updated: 2026-10-25
tags: [reliability, security]
repos: chrisrogers37/benzo
---

# Delivery run

Epic: [approved re-orientation](00_overview.md). User ratified recommended F1–F7 with their conditions and authorized Phase 3 on 2026-10-25. User merges; no push to main. Goal: all eight ordered PRs accepted with their specified tests, build, independent review and outcome evidence; issue dispositions recorded honestly. The goal is not yet met.

## Kickoff gates

| Gate | Disposition |
|---|---|
| Phase 3 / F1–F7 | Passed: explicit user approval; F7 rights/channel conditions and all outward gates remain. |
| Source base | Passed: fetched origin/main at a0c12f1ddde45a36be2b89e603d3a4ae080871cd. 56 open issues; dependency PRs #92–94 remain open. |
| Host safety | Binding: do not launch production Benzo or change power settings, permission rules, login registration, blockers or fleet processes. |
| Full Xcode | Blocked locally: xcodebuild reports CommandLineTools, no installed Xcode app. P1 adds full-Xcode CI; no installation/system developer-path change implied. |
| Browser visual parity | Blocked: authorized retry of http://127.0.0.1:4173 rejected by saved browser security policy. No alternate surface or policy bypass. Temporary baseline server stopped. |
| Push / automatic preview | Passed for P1: user explicitly approved the automatic Vercel preview, branch push and PR. Integration rechecked before publication. Releases and production/main deployment remain separately gated. |
| Dedicated native acceptance | Not invoked in P1; separately approved isolated hardware required for later privileged/lifecycle acceptance. |

## Invariant registry

| Invariant | Check and failure action |
|---|---|
| Always-on host untouched | Review commands and test composition; no production App target in test source/build dependencies, no live adapters linked. Stop if a test can reach host mutation. |
| Native/demo behavior parity | Behavioral changes carry matching demo states in same PR; P1 mechanical extraction keeps existing defaults and interactions. Browser denial leaves visual acceptance blocked. |
| No premature issue closure | Compare PR keywords/ledger to epic issue and umbrella matrix; use Refs until all scope/evidence is met. |
| Sequential independent PRs | git merge-base and diff against fresh origin/main; start each phase only after user's predecessor merge. |
| Current checks and review | Capture tested source/commit and exact checks; changed runtime inputs invalidate affected evidence. |
| Outward actions scoped | Recheck deployment integration before push/merge; no release, Apple upload, tap publish or deployment without explicit approval. |

## Merge topology

Single repo, no stacked branches. P1 uses codex/benzo-build-foundation in the attached worktree; P2–P8 each branch from fresh main after the user merges the predecessor. User selects merge method; either squash or merge works with this topology. Never merge or push main from the agent.

## Phase results

| Phase | Plan | Issues | State | PR / CI |
|---|---|---|---|---|
| P1 | [Foundation](01_build-foundation.md) | #22 #23 #71; partial #72 #82 | Local implementation reviewed; acceptance blocked | No push or PR yet |
| P2 | [Distribution](02_distribution-build.md) | Per epic | Queued on P1 merge | — |
| P3 | [Commands](03_command-permissions.md) | Per epic | Queued on P2 merge | — |
| P4 | [Recovery](04_recovery-engine.md) | Per epic | Queued on P3 merge | — |
| P5 | [Lifecycle](05_lifecycle-retirement.md) | Per epic | Queued on P4 merge | — |
| P6 | [Diagnostics](06_diagnostics.md) | Per epic | Queued on P5 merge | — |
| P7 | [Native UX](07_native-ux.md) | Per epic | Queued on P6 merge | — |
| P8 | [Site](08_site-trust.md) | Per epic | Queued on P7 merge | — |

## P1 entry

Composition: build-all bounded decomposition, with claudna:delegate for mechanical web extraction and same-host native work after delegate exit; verify, simplify and independent review run once for the integrated phase. Task scratch /private/tmp/benzo-p1.Anb1ib is retained through this active handoff. Approved planning documents accompany the first implementation PR because they were previously local-only.

Runtime selection: Node 24.22.1, verified from official Node distribution checksums in task scratch; host Node is unchanged. npm registry current metadata confirms the selected Vite/Vitest/jsdom releases support Node 24. No blanket audit suppression or dependency override.

## Review rounds

The integrated source and four simplification lenses are complete. Independent review found no actionable source defects; required full-Xcode and browser acceptance remain blocked. Exact checks, scope, reviewers and dispositions are recorded below.

## Owner-decision queue

1. P1 automatic preview/push/PR approved by the user. Observe its actual deployment and CI outcome; this does not authorize production deployment or a merge.
2. Resolve saved local-browser denial for required visual acceptance; user authorization already exists but tool policy still denies.
3. User merges each verified PR in order. No successor branch before that merge.
4. Future dedicated native, exact signed artifacts, release/deployment and F7 rights/reporting prerequisites remain as recorded in the epic.

## P1 implementation and verification receipt

Local preparation snapshot: `codex/benzo-build-foundation` from `a0c12f1ddde45a36be2b89e603d3a4ae080871cd` in the attached worktree. At that snapshot no commit, remote push, PR, deployment, issue closure or merge had occurred. User subsequently approved the P1 push, PR and automatic preview; publication receipts follow below. Runtime source is frozen in `pre-review-manifest.json` (41 owned staged paths; manifest SHA-256 `7cef98900f5f182fb856dab2f076ce27a97ec1af2761d10dbe24e07757009e4d`). Final receipt edits are documentation-only and tracked separately. The original checkout is preserved.

### Delivered locally

- Native dependencies require explicit commands, backup storage, preferences, clock, login and asynchronous callbacks. Live composition remains in AppDelegate. The unhosted test bundle is configured to compile 13 explicit sources, including two test files; application composition, shell execution, live diagnostics and the live login adapter are excluded. No test host, app target dependency or implicit app build is configured.
- The web marketing wrapper owns shared demo state, the extracted component renders it, and fixtures/reducer are separate. Initial options and the existing mock countdown remain unchanged; functional timing belongs to P5. Unrelated Gatekeeper state stays local.
- Node 24.22.1 and the resulting compatible Vite/Vitest/React testing dependencies are recorded consistently. Source-only CI adds clean web tests/build plus full-Xcode Debug/Release/core tests. Existing npm-audit/Gitleaks checks remain.
- Ignore policy covers environment/credential/output artifacts while allowing templates. Tracked-path inspection found no matching secret artifact; no claim about hypothetical past leaks is made. README, CLAUDE, AGENTS and the work pointer describe the actual commands and host boundary.

### Evidence

| Check | Result and limit |
|---|---|
| Clean `npm ci` | Exit 0 with task-local Node 24.22.1 and task-local npm cache. Shared Node/cache were not repaired or replaced. |
| Web tests | 17/17 passed, exit 0; independent review reran and passed. Tests exercise reducer immutability and rendered interactions/shared callers. |
| Production site build | Exit 0, Vite 8.3.5; 20 transformed modules; JS 241.30 kB / 74.15 kB gzip. Independent build passed. No deployed/field performance claim. |
| npm audit | Zero vulnerabilities at moderate threshold, independently repeated. Initial lockfile had two high packages; no advisory suppression or vulnerable override. |
| Gitleaks | Verified task-local v8.30.1: all 48 local-history commits and the staged changes passed. An initial prose-only generic-api-key match was resolved by rewording a phrase in P6's plan; no allowlist/ignore was added. |
| Workflow/project metadata | Both workflow YAML files parsed; Xcode plist and scheme XML passed. Exact 13-source core membership and exclusion of all live sources were independently reviewed. Source validation does not prove CI execution. |
| Swift compile-only checks | All 24 app sources typechecked with Swift 5 language mode/macOS 13 arm64 target. The 11 core production sources plus test doubles typechecked. Exit 0. This is not a full Xcode build or XCTest execution. |
| Full Xcode / XCTest | Blocked locally: only Command Line Tools installed, XCTest module unavailable. Debug/Release/core-test CI must pass at the eventual PR head. No host installation or developer-path changes. |
| Browser parity | Blocked by explicit saved-policy denial of the authorized localhost retry. No browser route was substituted. DOM tests and delegated static render comparison do not fulfill screenshot acceptance. |
| Host safety | No production app/native test launch; no real power/auth/login/blocker/fleet mutation. The task-owned preview was stopped after denial. No host settings need restoration from P1. |

### Bounded delegation

`claudna:delegate` ran native Claude for the five-file mechanical web extraction. Actual parent session: `codex/01a17187-3b96-70f0-b5ec-63e95dfb9b6e`; delegate job `37e98901-1884-4e66-8fd8-f0cba1edb114`; child session `79269eb7-086c-4d3b-8bed-f5f76145a030`. The child exited 0, reported no permission denials and completed cleanup. Parent checked its exact scope, built/retested, refined the tests, and settled it accepted for the bounded extraction only. The child's test-count/static-render statements were not used as full P1 acceptance. Native work then used a same-host worker with ownership limited to the native seams, target and tests; parent reviewed its source membership and independently typechecked.

### Independent reviews and dispositions

Four independent simplification lenses ran with capacity-bounded concurrency: `/root/p1_simplify_reuse`, `/root/p1_simplify_complexity`, `/root/p1_simplify_efficiency`, `/root/p1_simplify_altitude`. All checked the frozen file hashes. Complexity, efficiency and altitude had no findings. Reuse raised only optional Minor R1: the enabled-setting loop appears in both `PMSetService.applySettings` and `applySettingsWithRestore`. The parent confirmed both copies predate P1 and declined the optional cleanup because this phase is a mechanical seam change; P4 owns replacement of that operation policy. No simplification source edits or reverts occurred. Reports are retained in task scratch.

Independent `claudna:review-work changes` ran as `/root/p1_review_work` with no inherited working context. It found no actionable Critical, Important or Minor source defects. The reviewer independently passed 17 web tests, build, audit, staged Gitleaks, app source typecheck, test syntax and project/scheme boundary checks; all 41 source/index hashes matched. Full Xcode and screenshots remain Important acceptance blockers, distinct from source findings. The final report is retained as `review-work.md` in task scratch. Subsequent edits only update these delivery receipts and issue dispositions; runtime source stays unchanged.

### Issue outcomes and remaining work

| Issue/item | P1 result | Remaining evidence / owner |
|---|---|---|
| #22 / #81 BZ-038 | Component/state/fixture extraction and shared-caller behavior tests complete locally. | Required browser parity; keep open. |
| #23 | Repeated boundary paths and preference strings centralized without changing persisted values. | P2 bundle-derived footer/version policy; keep open. |
| #71 | Web/native build workflow and shared schemes prepared. | Actual full-Xcode/remote security/build results at PR head; required-check configuration only if separately needed. |
| #72 / #82 BZ-037 | Explicit dependency seams, fake-only test target and useful starting cases prepared. | XCTest execution plus parser/policy/recovery/diagnostic regression scope in P3–P6; no umbrella closure. |
| #80 BZ-042 env | Ignore rules and tracked-path inspection complete locally; templates remain eligible. | Owner-merged implementation receipt; umbrella includes other items. |
| #82 BZ-045 | Replaced the content-controller force unwrap with one optional binding. `statusItem`/`popover` are assigned before their callbacks are registered; no reachable nil crash was established for those IUOs. Existing Application Support `.first!` assumption was moved to app composition, not introduced or proven safe for every hypothetical environment. | Do not claim every IUO removed or an observed crash fixed. No speculative fallback directory that could lose originals. |
| #82 BZ-046 | Removed the extracted web demo's unused `activeCount`; retained native `capturedAt` as persisted recovery provenance, covered by a round-trip test awaiting XCTest execution. `killCaffeinateProcesses` is reachable, so it is not dead code; removing that behavior belongs to P5. Native `MasterToggleView.activeCount` is an unused input spanning untouched view files. | P7 may remove that native input during the owned UI change; no broad dead-code-complete claim. |

P1 is not accepted or ready to merge. Full Xcode and browser evidence remain; the user approved P1 preview publication. P2–P8 remain queued behind their predecessor merges.

### Authorized publication

User replied “Yes” to the explicit request to allow P1's automatic Vercel preview, push the branch and open its PR. Fresh `origin/main` remains `a0c12f1ddde45a36be2b89e603d3a4ae080871cd`; all 41 final files matched their recorded hashes before documentation-only authorization updates. Publish a draft while full-Xcode CI and screenshots are pending. No production/main deployment, release, merge or host change is authorized by this publication approval.
