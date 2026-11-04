# Adversarial review — Benzo update experience

Reviewed November 4, 2026 against remote main c3a9070 and the saved plan. Single consolidated seven-lens review, with an additional fresh-context technical challenger. The challenger returned NO FINDINGS after reading the source and plan. Subsequent implementation and acceptance evidence is recorded below; no native release has been made.

## Pre-mortem

Five concrete ways this could fail: a stalled/oversized response defeats the UI bounds; a stale completion reports current after a newer request; metadata or a link is mistaken for installation safety; the new footer leaks Restore/Quit into permission panels; updater work conflicts with packaging/recovery changes.

## Assessment and disposition

No implementation blocker for A/B. The following implementation risks have explicit mitigations:

| Risk | Evidence | Resolution |
|---|---|---|
| An after-download size check would not bound network/memory consumption; inactivity timeout alone is not a total deadline. | Plan section 2 promises 15 seconds / 1 MiB. | Enforce a total URLSession resource timeout and the byte limit during receipt; cancel on overflow. Test the boundary with injected bytes, not a live service. |
| Popover closure or a second check can leave stale state. | `AppDelegate.swift:124–152` controls closure; existing diagnostics use generations in `BenzoViewModel.swift:127–155`. | One owned request, explicit cancel/invalidation, generation guard; closing or leaving the normal panel cancels. No polling or persistent last-check store. |
| Shared native ownership with release/recovery. | Separately owned draft [PR #102](https://github.com/chrisrogers37/benzo/pull/102), head `6d3478606fd72ec131ce99ed9065676e44179bfd`, now includes universal-artifact CI. Recovery 02 is absent on main. | Leave packaging and recovery unchanged; A/B uses a separate update model. C remains separately owned native-release preparation, and D is conditional, not queued. |
| Verification could overstate native readiness. | Local CLT checks are distinct from full-Xcode CI and native UI acceptance. | Full-Xcode CI now passes at the PR head. Record scoped UI acceptance separately; neither proves installed-release compatibility or privileged recovery. |

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

Implemented on isolated branch `implement/benzo-update-checker`, based on c3a9070; primary checkout preserved. Draft [PR #103](https://github.com/chrisrogers37/benzo/pull/103) remains unmerged and unreleased. Implementation head `38ea13ded6235a7efaab98d9548000d7ad2152fb` passed all reported checks; the subsequent acceptance-record change is documentation only. No packaging/recovery implementation was adopted. Redirect policy rejects all redirects at the fixed endpoint; no custom metadata or install path was added. Also updated `src/design/README.md` to explain simulated update-response timing.

- Node 24.22.1: 52/52 Vitest tests passed; production Vite build passed; moderate npm audit returned zero vulnerabilities. The seven new UI cases first failed against the prior implementation, then passed.
- All native app sources passed macOS 13-target CLT typechecking, with the pre-existing non-Sendable `runOnMain` warning. Xcode project plist lint and diff whitespace checks passed.
- A task-local synthetic Swift executable exercised the real injected version/checker/ViewModel types: numeric and invalid versions, fixed page construction, byte cap and separate check/open actions. A canceled-loader case first reproduced a stuck Checking state; after correction it passed. This is not XCTest or installed-app acceptance.
- Nine focused XCTest methods were added. [Build run 41880417986](https://github.com/chrisrogers37/benzo/actions/runs/41880417986) at `38ea13d` passed Xcode 16.4 Debug/Release builds and all 64 unhosted XCTest tests; its web job passed 52 tests. Native, web, npm-audit, Gitleaks and all other reported PR checks succeeded.
- Privacy review reported zero findings in tracked-tree and history Gitleaks scans. Both outgoing commits now use public GitHub no-reply authorship: `fe9e25d` → `c3be354`, `e0ea820` → `38ea13d`. Direct diffs confirm identical file trees for both rewritten pairs; this metadata correction changed no source.
- Browser acceptance used the supported native Chrome controls. The 320px panels showed current, available, long-version, offline, unavailable and unknown-version results without clipping. A temporary fixture reused the actual component and hook, then was removed. Shift-Tab reached Check for Updates, Space activated it, and the next Tab reached View Releases; its click produced the demo-only notice. Full keyboard activation of the release action was not established because a later key sequence opened an unexpected browser dialog, which was dismissed without saving.

## Independent implementation review

Fresh reviewer inspected implementation head `fe9e25d` against `c3a9070`, including the plan, diff, target membership and whitespace. **NO FINDINGS**: no Critical, Important or Minor defects, no revisions requested. The corresponding rewritten implementation commit `c3be354` has the identical file tree. Reported test receipts were not rerun by the reviewer. This is source-review acceptance of A/B, not a merge or native-release approval.

Acceptance status and remaining boundaries:

- Full-Xcode Debug/Release and XCTest passed at `38ea13d`; CLT compilation and synthetic fixtures remain supplementary evidence.
- Browser state layouts and partial keyboard navigation passed; native current/available states and both live browser destinations passed in the temporary window driver below. Full VoiceOver and production-popover interaction remain unverified; do not equate accessibility-tree labels with spoken screen-reader acceptance.
- Live URLSession timeouts/redirect refusal were source-reviewed; injected tests exercise parser/state/byte bounds, not the production adapter. Current-Mac UI/browser testing is explicitly authorized for this task. Record any production-adapter observations separately; untested timeout/redirect behavior remains a limitation, not an implied pass.
- Recovery, artifact signatures/compatibility, packaging PR102 and public release remain separately owned, held work. Check/link adds no installation or termination route; it cannot make external replacement safe.

No deferred code-review findings. The implementation kept the table-shaped plan with a small progress ledger rather than adding task-runner scaffolding; the cost is manual bookkeeping only. Primary-checkout preservation check covered all 19 previously recorded work files with zero changes. Remote main was rechecked at c3a9070. PR #103 remains draft, unmerged and unreleased.

## Scoped native UI acceptance

The owner explicitly authorized native UI, keyboard/VoiceOver and browser testing on the current Mac. Acceptance uses a task-owned temporary ad-hoc bundle with isolated preferences; this is not an installed release or Developer ID/notarization receipt. Power, grants, login items and fleet mutations remain outside scope. The exception applies to these checks, not the separate recovery or installer acceptance program.

- On macOS 26.1 / Apple Silicon, CLT compiled the branch Swift sources into a task-local ad-hoc bundle with a separate preference identity. The automation tool could not reliably attach to the menu-bar-only app or retain the popover after Back. A temporary composition driver therefore hosted the unchanged native views and live update adapter in an ordinary 320-point window. This verifies those views/adapter, not production popover positioning or a packaged distribution artifact.
- The live explicit check showed Checking and then current for test version 0.3.0. A separate View Releases click opened the fixed official releases index. Changing only the task bundle version to 0.2.0 produced available 0.3.0, compatibility/recovery guidance without clipping, and a separate View Release click opened the exact official v0.3.0 page. No download or installation was invoked.
- Native accessibility inspection exposed the check action, result and release action. Tab did not move focus under the current host configuration. VoiceOver did not start through either the system-shortcut attempt or the app-launch tool; no spoken-output or native keyboard pass is claimed. [Apple's VoiceOver guide](https://support.apple.com/guide/voiceover/turn-voiceover-on-or-off-vo2682/mac) documents the screen reader and its controls. These are remaining manual acceptance checks, not a requirement to acquire another Mac.
- The temporary app quit while inactive; its process count was verified zero. Task browser tabs and Vite were closed, temporary repository fixtures removed, and all 19 protected primary-checkout files matched their recorded hashes. No power, grant, login-item or fleet operation was performed. No native screenshots or private browser context were added to the PR.

**Disposition:** A/B implementation and automated validation are complete. Remaining acceptance limits are the production-popover interaction, native keyboard/VoiceOver, complete browser keyboard activation, and live timeout/redirect failure injection. C is separately owned release/recovery preparation; D remains conditional and is not queued. No public native release is authorized by this result.

## Delegated simplify and PR review follow-up

Claude Haiku 5.5 invoked the bundled `simplify` skill; its reuse, simplification, efficiency and abstraction lenses ran inline because the delegate launcher disallows nested agents. Claude Sonnet 5.5 invoked `review-pr`. Native session records confirmed both skills and models. Both workers were read-only and completed without permission denials. Sonnet disclosed that it omitted the plan and web-test detail and could not query CI because of a TLS error; the parent and independent inexpensive explorer covered those reads, and the parent verified all checks green at `4393df8`. These are bounded review receipts, not a claim that either worker independently completed acceptance.

No blocking correctness, security or recovery finding remained. The parent resolved one UX suggestion: completed results previously survived panel closure and could appear fresh on a later visit. Native cancellation now clears the result and browser error; web close/diagnostics navigation does the same. Reopening stays idle and never checks automatically. The demo also derives the simulated version from its existing presentation value. Keep the early transport rejection, independent checker validation and multiple cancellation entry points: they serve distinct boundaries. Build metadata remains part of the accepted AppVersion contract. GitHub's [current API-version documentation](https://docs.github.com/en/rest/about-the-rest-api/api-versions) confirms `2026-03-10`; no header downgrade is needed.

Focused web regression failed before the fix and all 53 web tests passed afterward. A synthetic CLT executable reproduced the completed-result issue with the old native ViewModel and passed with the fix; it is not XCTest. A new native XCTest covers completed current/available results, browser-error cleanup and no extra request. The PR's native CI check records full-Xcode validation for the follow-up. Independent review of the small fix returned **NO FINDINGS**. The production-popover, keyboard/VoiceOver and live transport-failure acceptance limits above remain unchanged.
