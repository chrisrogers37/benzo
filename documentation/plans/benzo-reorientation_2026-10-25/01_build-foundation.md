---
title: "[plan] P1 — Safe build and test foundation"
type: plan
status: active
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-26
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size M, risk medium. Establish reproducible native/site builds and useful test seams, resolve current dependency advisories, and extract the web demo without changing behavior. This is one PR on `codex/benzo-build-foundation`; it creates the verification foundation for later changes, not a broad MVVM rewrite.

## Evidence

`package.json:6` has only dev/build/preview; `.github/workflows/security.yml:20` uses Node 20 and gates audit/gitleaks but no build/test. `src/BenzoHybrid.jsx:6–18` owns the demo state and marketing wrapper together. `BenzoViewModel.swift:36–66` directly reads production preferences/permissions on initialization. The evaluation's native fallback compile does not validate project resources or Xcode targets. The actual locked Vite toolchain requires a Node version satisfying `^20.19.0 || >=22.12.0`; do not copy stale Vite 6 instructions.

## Implementation Plan

### Dependencies

Phase 3 owner approval; accepted issue dispositions/product forks as relevant. Resolve Vercel automatic preview deployment authority before the first remote push. No predecessor PR.

### Blocks

P2–P8. #72/#82 remain open for behavior/ledger completion in later phases.

### Steps

1. **Own files:** `package.json`, `package-lock.json`, `.gitignore`, `.github/workflows/security.yml`; new `.github/workflows/build.yml`; `Benzo/Benzo.xcodeproj/project.pbxproj` and shared schemes; new `Benzo/BenzoTests/`; `src/BenzoHybrid.jsx`; new `src/components/BenzoMockup.jsx`, `src/demo/state.js`, `src/demo/fixtures.js`, `src/components/BenzoMockup.test.jsx`; `CLAUDE.md`, `AGENTS.md`, README setup/tests and `.claude/todo.md`. Native seams are limited to `BenzoViewModel.swift`, `PMSetService.swift`, `BackupService.swift`, `ShellExecutor.swift` plus new `Services/BenzoDependencies.swift`, `Services/LoginItemClient.swift` and separate `Services/LiveLoginItemClient.swift`. Later phases intentionally revisit these paths after merge.
2. Review current #92–94 heads and advisory details; choose minimal compatible dependency resolution. Do not automatically merge Dependabot, pin vulnerable overrides, or silence audit. Select one currently supported Node line satisfying the resulting lockfile; record it consistently in CI and local setup. Add ignore entries for `.env`, `.env.*`, local secret/export artifacts while explicitly allowing legitimate `.env.example` templates. Inspect tracked files separately; no observed leak is claimed and nothing is untracked blindly.
3. Use Vitest + React Testing Library and jsdom as the single minimal web behavior harness, with `"test": "vitest run"`. Verify compatible current releases during implementation. Extract JSX and state so `BenzoHybrid` remains the marketing wrapper and explicit owner of shared demo state needed by outside hint/CTA consumers. Proposed shape:
   ```jsx
   const [demo, dispatch] = useReducer(demoReducer, initialDemoState);
   <BenzoMockup state={demo} dispatch={dispatch} />
   <DemoHint diagnosticsOpen={demo.showDiagnostics} />
   ```
   Move the relevant React import to `import { useReducer } from "react"` only if no `useState` call remains in that file. Define `initialDemoState`, pure `demoReducer(state, action)` and fixture exports in `src/demo/`; keep unrelated marketing state local. Preserve initial state, visuals, event behavior and outside diagnostics caller. **Do not change the options default here**; BZ-043(d) belongs to P7.
4. Introduce small protocol-backed dependencies without replacing business algorithms. Proposed test seam skeleton in `BenzoDependencies.swift`: `CommandRunning`, `BackupStoring`, `PreferenceStoring`, `BenzoClock`, `LoginItemClient`; production adapters wrap existing functions. The ViewModel initializer takes dependencies and an explicit startup policy; composition in `AppDelegate` supplies live adapters. Test initialization receives fakes and `.manual`, never implicitly falling back to live defaults. Make accidental production composition in the test target impossible by excluding `App/` sources and supplying no production factory default. Route the reachable launch-at-login property observer through the injected `LoginItemClient` now; keep its live `SMAppService` adapter in `LiveLoginItemClient.swift`, excluded from the core test target. Require a fake in test composition and exercise the setter to prove no real registration path is reachable. P5 retains login readback/error/UI behavior changes.
5. Add an **unhosted XCTest bundle** and shared `BenzoCoreTests` scheme in the existing Xcode project. Compile the narrow production models/services/seams needed by tests as test-target sources; no `TEST_HOST`, `BUNDLE_LOADER`, `AppDelegate` or `BenzoApp` dependency. Do not add a second production SwiftPM graph. Start with valid parser input, scratch backup round-trip/read failure, dependency error propagation, the ViewModel login setter calling only its fake and web toggle/outside-hint behavior; known broken cases are added with their owning fixes, not permanently blessed as correct.
6. Preserve security jobs. Build workflow uses `contents: read`; clean Linux web install/test/build and macOS full-Xcode Debug/Release builds plus unhosted tests. Record Xcode version and exact target selection. Document current support/commands and replace the no-tests rationale; prepend a plan pointer to `.claude/todo.md` while preserving historical roadmap as unratified history. Inspect #82 IUO/dead-code hypotheses and record concrete reachable fixes or reasons; do not manufacture cleanup. `capturedAt` is reserved for recovery provenance.

## Test Plan

Run `npm ci`, `npm test`, `npm run build`, `npm audit --audit-level=moderate` and gitleaks against this commit. On a full-Xcode runner:

```sh
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Release -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Benzo/Benzo.xcodeproj -scheme BenzoCoreTests -destination 'platform=macOS' -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO test
```

Set `BENZO_TEST_DERIVED` to a newly created task-owned temporary directory, not a shared build directory. Check test target metadata excludes the app host and live login adapter, and fake logs contain no real pmset/sudo/login calls. The original extraction check required authorized browser before/after screenshots at the same viewport plus interactions. On October 26 the owner explicitly accepted their manual check instead and waived screenshots; see the delivery receipt. This P1 waiver does not waive later browser/design acceptance. No arbitrary coverage target.

## Verification Checklist

- [ ] Clean installation, web behavior/build/security jobs and full-Xcode Debug/Release/core tests pass at PR head.
- [x] Unit-test composition excludes production startup/live adapters; fake-boundary cases passed in unhosted XCTest at 776c08d.
- [x] Extracted demo parity accepted by owner manual visual/interaction check at 0409b790; screenshot requirement explicitly waived. No conversion/design approval is implied.
- [x] Current advisories resolved; local and remote audit at 776c08d pass without suppression.
- [ ] #22/#23/#71 scopes have evidence; #72/#82 partial rows use `Refs`, not premature closure.
- [ ] Independent `claudna:review-work` findings addressed; plan receipts updated; user merges.

## Delivery receipt — 2026-10-25

Implementation and independent `claudna:review-work` are complete with no actionable source defects. Draft [PR #95](https://github.com/chrisrogers37/benzo/pull/95) is published with explicit approval for its automatic Vercel preview. At implementation SHA `776c08d99077d33f25a39462517fe12bd3d66139`, remote clean install, 17 web tests/build, audit, Gitleaks, full-Xcode Debug/Release and all 11 unhosted XCTest cases passed. Xcode was 16.4 (16F6) on macos-15; no production app or native test was run on the fleet Mac. Delivery-only follow-up commits require green checks at their resulting PR head.

The owner-approved ruleset requires native, web, npm-audit and gitleaks checks from GitHub Actions, with an up-to-date branch; existing protections and bypass settings were verified unchanged. #71 remains open until owner merge. The October 26 Claude simplification and Sonnet/Opus reviews found no Critical/Important defects; the strengthened native timer test passed in CI at 0409b790 along with all other checks. The owner then reported “That all seems to work!” after the manual visual/interaction checklist and explicitly answered “Yes—use my manual check” to accepting it in place of before/after screenshots. No screenshots were captured or supplied; agent browser policy remains unchanged. Acceptance covers P1 regression parity, not design optimization or improved download conversion. This documentation-only update must retain green PR-head checks before owner merge. See [RUN_LOG](RUN_LOG.md) for exact checks/review identities, deployment, issue/#82 dispositions and limitations. P2 remains queued on the owner's P1 merge.

## What NOT To Do

Do not run the production app to reach tests, install full Xcode by assumption, normalize the UI while extracting, add blanket snapshot/constant tests, require arbitrary coverage, or call fallback swiftc a passing Xcode build. Do not push until the deployment trigger gate is resolved.

## Context

- Source: claudna:forge; area: build/test seams and demo structure; effort M; risk medium; priority high.
- Primary issues: #22, #23, #71, #72, #82. Shared #80/BZ-042 and #81/BZ-038; exact item closure is in the epic ledger.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC01:** Moved login-item seam/live exclusion and reachable setter fake test into the first phase. Document correction independently verified.
