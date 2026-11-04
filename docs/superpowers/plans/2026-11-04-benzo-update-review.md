# Adversarial review — Benzo update experience

Reviewed November 4, 2026 against remote main c3a9070 and the saved plan. Single consolidated seven-lens review, with an additional fresh-context technical challenger. The challenger returned NO FINDINGS after reading the source and plan. No release or host actions were taken.

## Pre-mortem

Five concrete ways this could fail: a stalled/oversized response defeats the UI bounds; a stale completion reports current after a newer request; metadata or a link is mistaken for installation safety; the new footer leaks Restore/Quit into permission panels; updater work conflicts with packaging/recovery changes.

## Assessment and disposition

No implementation blocker for A/B. The following implementation risks have explicit mitigations:

| Risk | Evidence | Resolution |
|---|---|---|
| An after-download size check would not bound network/memory consumption; inactivity timeout alone is not a total deadline. | Plan section 2 promises 15 seconds / 1 MiB. | Enforce a total URLSession resource timeout and the byte limit during receipt; cancel on overflow. Test the boundary with injected bytes, not a live service. |
| Popover closure or a second check can leave stale state. | `AppDelegate.swift:124–152` controls closure; existing diagnostics use generations in `BenzoViewModel.swift:127–155`. | One owned request, explicit cancel/invalidation, generation guard; closing or leaving the normal panel cancels. No polling or persistent last-check store. |
| Shared native ownership with release/recovery. | Open PR #102 changes scripts/workflow/README/CLAUDE only; no AppVersion or footer changes. Recovery 02 is absent on main. | Start from current main, leave packaging and recovery unchanged, use a separate update model; append small documentation sections to reduce merge conflicts. |
| Verification could overstate native readiness. | This host has CLT, no Xcode/XCTest module. | Author focused XCTest cases, perform available CLT compilation/synthetic checks and web tests; retain full-Xcode/native acceptance as pending. No signing or installed-app claims. |

## Seven lenses

1. **First principles:** People need to discover a published release from the app. A manual metadata check plus link solves that without introducing installer authority. Remove background activity, custom feeds and a downloader.
2. **Gaps/assumptions:** GitHub availability is low-confidence/high-impact for a check but has a visible error and fixed release-index fallback. Recovery independence is high-confidence/high-impact and enforced by no privileged dependencies. User demand is medium-confidence/low-cost; no analytics project is warranted. Compatibility is deliberately unknown.
3. **Edges:** No release, missing assets, malformed/local prerelease versions, large payloads, denied redirects, throttling, cancellation and repeated clicks remain non-success; no downgrade or arbitrary URL navigation.
4. **Alternatives:** A plain View Releases link is cheaper and remains the fallback; doing nothing preserves today's manual hunt; Sparkle carries installation obligations that are disproportionate now.
5. **Implementation risk/reference class:** #99 containment, #100 read boundaries and #101 diagnostics demonstrate existing injected XCTest/web patterns and separate hardware acceptance. No duration estimates exist to support a time claim. Reuse those patterns, not their privileged transports.
6. **Press release test:** Benzo can check for a newer published stable release when you ask. You can review it in your browser without changing the current session.
7. **Counter-plan:** Ship only View Releases, relying entirely on the browser and release notes. It removes parsing/network maintenance but never answers whether a newer release exists. Synthesis: retain it as fallback while implementing the bounded explicit comparison the owner requested.

## Calibration

After a second pass seeking a credible blocker, none remains within A/B. The main risks are implementation mistakes at the request lifecycle and boundaries; focused tests and a final independent code review address them. This verdict does not approve Sparkle, packaging/recovery changes, publishing or native release.

## Implementation validation (A/B)

Implemented on isolated branch `implement/benzo-update-checker`, based on c3a9070; primary checkout preserved. No packaging/recovery implementation or release actions. Redirect policy rejects all redirects at the fixed endpoint; no custom metadata or install path was added. Also updated `src/design/README.md` to explain simulated update-response timing.

- Node 24.22.1: 52/52 Vitest tests passed; production Vite build passed; moderate npm audit returned zero vulnerabilities. The seven new UI cases first failed against the prior implementation, then passed.
- All native app sources passed macOS 13-target CLT typechecking, with the pre-existing non-Sendable `runOnMain` warning. Xcode project plist lint and diff whitespace checks passed.
- A task-local synthetic Swift executable exercised the real injected version/checker/ViewModel types: numeric and invalid versions, fixed page construction, byte cap and separate check/open actions. A canceled-loader case first reproduced a stuck Checking state; after correction it passed. This is not XCTest or installed-app acceptance.
- Nine focused XCTest methods were added. Full-Xcode Debug/Release and XCTest remain pending: the installed toolchain is CLT only. Gitleaks/CI and dedicated-Mac acceptance remain pending. No app was launched.
- Local browser verification was attempted through the supported Chrome interface, but tab binding/navigation failed inside the browser tool before page interaction. Do not infer rendered visual acceptance from jsdom/build results.
