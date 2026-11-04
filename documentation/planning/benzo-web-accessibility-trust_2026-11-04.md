---
title: "Benzo website accessibility and trust follow-through"
status: source-complete
created: 2026-11-04
---

The owner approved implementing the **unowned website accessibility/trust work**
on November 4. This is the bounded follow-through to P8 and issues
[#40](https://github.com/chrisrogers37/benzo/issues/40),
[#41](https://github.com/chrisrogers37/benzo/issues/41),
[#60](https://github.com/chrisrogers37/benzo/issues/60), and
[#81](https://github.com/chrisrogers37/benzo/issues/81).
Base: `c3a9070b16c602c48b833a6e338fb40930ae4b04`.

## Scope and decisions

Preserve the [November 2 YAGNI amendment](tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md).
Native accessibility and matching demo controls, focus and colors belong to the
separate native-accessibility session. Recovery/packaging/release and
update-checker/installation remain with their existing owners. Do not edit those
surfaces, cask metadata, or README installation/recovery/build instructions here.
The owner subsequently authorized consolidating and merging this session through
[PR #98](https://github.com/chrisrogers37/benzo/pull/98), including its automatic
website deployment. Native execution/release and unrelated issue closures remain
outside this session.

| Base-source gap | Bounded response |
| --- | --- |
| Active page already has skip/main/navigation, semantic FAQ disclosures, focus and reduced-motion CSS. Source review found no specific marketing-page failure. | Check the rendered page; fix only observed failures outside the owned demo. Do not claim complete assistive-technology acceptance. |
| README has a six-command recipe, old homepage and an MIT assertion without a LICENSE file. | Replace the recipe with factual system-wide write scope, correct the homepage and add the owner-approved MIT license. |
| No precise data-handling disclosure exists. Native originals/preferences persist locally; demo state is in memory; no analytics/upload path exists in reviewed source. | Add concise source-qualified privacy documentation and discoverable FAQ/footer links using existing components. Separate website hosting and external links from native behavior. |
| GitHub private reporting is disabled. No security-response policy exists. | Use the owner-approved contact@benzo.work route with best-effort handling and no supported-release or response-time promise. No settings change is needed. |

Reuse the existing FAQ and link renderer; no new router, dependency, privacy
service or consent widget is needed. The source-based disclosure must not make
claims about the v0.3.0 artifact or future updater network behavior. Preserve the
unreleased-demo/download caveat. Diagnostics are transient in Benzo, but this does
not establish macOS log retention. Original settings are recovery evidence, not
disposable analytics data.

### Approved policy completion — November 4

The owner explicitly selected `contact@benzo.work` for private security reports
with best-effort handling and no response-time guarantee, and selected **Add MIT
LICENSE**. Use the standard [MIT license text](https://opensource.org/license/mit)
with `Copyright (c) 2026 Christopher Rogers`, consistent with repository author
history (initial source commit `b2352c5`, March 7, 2026). Dependency licenses remain
separate; do not add a corporate attribution or alter third-party notices.

Add root `SECURITY.md` covering the native menubar app, legacy permission rule,
recovery boundary and website. Accept reports about current source and published
releases on a best-effort basis; promise no supported release line, backport,
response deadline or resolution deadline. Ask for version/commit, macOS/hardware,
impact and minimal reproduction with redacted evidence, never secrets or full
private logs. Keep vulnerability details out of public issues. Document the
email route without enabling GitHub private reporting or claiming delivery proof.
Current native source remains unreleased with known recovery limits; native
publication and acceptance stay with R. Link the policy from README and the privacy notes;
change README's license paragraph to link LICENSE. No app suites are needed for
this documentation-only continuation.

## Implementation Plan

1. [x] Isolate from current remote main and confirm source facts with a read-only
   cheaper explorer. Preserve the reconciliation worktree for PR #98 separately.
2. [x] Delegate mechanical README/privacy/FAQ/footer edits to Claude Haiku in this
   clean worktree. Parent reviews every change and records acceptance.
3. [x] Apply the owner's MIT and private-contact decisions in LICENSE, SECURITY.md
   and README/privacy links. Keep native artifact acceptance with its owner.
4. [x] Verify the rendered marketing page with keyboard, zoom/narrow layout and
   reduced-motion evidence where available. Leave native/demo findings with their owner.
5. [x] Run existing Node 24 web tests/build/audit, check links and diff, and obtain
   independent review. Record source, CI and deployment evidence separately.

## Evidence and handoff

Implemented locally at `0dcc696`: four product/doc files, 57 additions and 14
deletions. No CSS, demo state, native code, dependency, installation or recovery
changes. Node 24.22.1 clean install, 45/45 existing tests, production build and
moderate audit (zero vulnerabilities) passed. Local links/anchors and the diff
were checked. No new tests pin prose. Native suites were not rerun for this web
slice; no native execution or acceptance is claimed.

Chrome on the isolated localhost preview confirmed the visible skip link and Tab
destination, 200% hero reflow, and 320px privacy FAQ/footer wrapping. Space toggles
the FAQ; Tab reaches its link and the footer Privacy link with visible focus.
The same FAQ interaction passed with DevTools `prefers-reduced-motion: reduce`
selected. No additional marketing-page defect was observed. Full screen-reader,
cross-browser and native/demo acceptance remain unverified; no CSS fix was needed.
Console errors were limited to the existing missing `favicon.ico`; new artwork
is deferred. Evidence choice: no media deliverable for copy/link changes; browser
observations supplemented the existing checks. No preview was published.

Claude Haiku job `c21a96f9-e731-4d32-8ac6-d17221bf4a22` completed with exit 0 and
no permission denials. Parent corrected overly broad wording, inspected all
changes and accepted the result after its own checks; launcher cleanup is complete.
Independent `gpt-6-luna` reviewer `/root/web_trust_review` returned NO FINDINGS,
including reuse, simplification, efficiency and responsibility-boundary lenses
in one review pass. No further simplification was justified.

Policy completion is local at `e5cc56c`: [LICENSE](../../LICENSE),
[SECURITY.md](../../SECURITY.md) and their README/privacy links implement the
owner's decisions. The MIT text matches the canonical template, 11 local policy
links/anchors resolve, and `git diff --check` passed. Independent review found no
text defects and requested verification of the private-reporting setting; the
parent resolved that question with GitHub's API returning `enabled: false`.
The email route is approved, not a claim of mailbox delivery or a response SLA.
No further license or parallel reporting-channel task is needed.

Claude Haiku job `bd1d620c-a72a-49b3-b976-9f26cf19440f` exited 0 with no permission
denials. The parent reviewed and accepted the corrected four-file result;
launcher cleanup is complete. Runtime/build inputs are unchanged from the tested
web slice, so no application suites were rerun for these policy documents.
All scoped source work is complete. Delivery and later recovery/updater facts
remain separate; draft #103's eventual network behavior must update the
source-qualified disclosure when accepted. About/cask license subitems remain
with the native/installation owners; no native surface was added here.

This slice does not close #40, #41, #43, #60 or #81. The owner authorized combining
the reviewed website and reconciliation changes in PR #98. Its final checks and
merge state are the delivery record; the website deployment must independently
match the resulting main SHA. No separate competing PR is needed. The original
worktrees and their unrelated changes are preserved. The earlier task-owned
server was stopped, browser emulation restored and preview tab closed.

Final status review returned NO FINDINGS. All 15 local documentation links/anchors
in this branch's changed files resolve; the complete diff passes whitespace checks.

## Consolidation and completion gate

The reviewed website head `2107cf0` and reconciliation head `dc02a68` are combined
in an isolated checkout descended from #98, with refreshed main `c3a9070`. Runtime
files match the reviewed website branch. The original October design supplements
remain in commit `90b78a4`; their useful receipts stay in the canonical run log.
Fresh web checks, documentation links, independent integration review, required
PR-head CI and production deployment readback gate the authorized merge/closeout.
GitHub issue edits remain proposals; other sessions retain native, recovery,
packaging, updater and installation ownership.

Fresh integration verification on Node 24.22.1: clean `npm ci`, 45/45 web tests,
production build and moderate audit (zero vulnerabilities) passed. All 79 local
documentation links and three pinned source paths resolve; all 54 open issues
are represented. The final product delta spans 16 files, with only two website
copy/link source files and no native/build/dependency changes. Required CI and
production verification remain separately recorded on PR #98 and its deployment.

Independent integration review confirmed runtime identity and unchanged native/CI/
dependency scope. Its stale-current-tracker finding was corrected by explicitly
marking old checkpoints historical; focused re-review confirmed no remainder.
