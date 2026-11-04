---
title: "[plan] P8 — Remaining website accessibility and trust"
type: plan
status: partially-complete
owner: claudna:forge
created: 2026-10-25
updated: 2026-11-04
tags: [enhancement, reliability]
repos: chrisrogers37/benzo
---

## Current scope and completed subset

The approved landing page shipped in [#97](https://github.com/chrisrogers37/benzo/pull/97), following P1/#95 and contact #96. The active route is `src/landing/BenzoLanding.jsx`, with one demo state, shared design/copy, semantic controls, system fonts, qualified claims, Releases/contact links, canonical metadata and draft redirects. #99–101 subsequently mirrored containment, permission observation and diagnostics. The [November 4 reconciliation](../../planning/tech_debt/benzo-remediation_2026-11-02/07_backlog-reconciliation.md) verifies current-main CI and website deployment separately from native artifact/acceptance.

The [accepted YAGNI amendment](../../planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md) controls remaining scope. Do not rebuild the site or execute old P2–P8 requirements unchanged. Existing browser/design receipts are useful but do not establish full keyboard/VoiceOver, zoom, motion-preference or native/demo contrast acceptance. Keep #43 and #81 partial.

## Bounded accessibility brief

November 4 follow-through: the owner authorized unowned website work separately.
Local `implement/benzo-web-accessibility-trust` commit `0dcc696` adds source-qualified
privacy FAQ/footer documentation and corrects README claims, with 45 web tests,
build/audit, scoped Chrome checks and independent review passed. The owner subsequently authorized its consolidation and merge through #98;
PR-head checks and matching production readback are the delivery gates. Local
`e5cc56c` completes the owner-approved MIT license and private
security-reporting policy at `contact@benzo.work`, with best-effort handling and no
response-time or supported-release promise. The separate native-accessibility
session owns native/demo colors, semantics and focus; do not duplicate that work.
All scoped unowned website work is complete locally; #40/#41/#43/#60/#81 are not
closed by this slice.

Reuse [#81/BZ-039](https://github.com/chrisrogers37/benzo/issues/81) and the web portion of [#43](https://github.com/chrisrogers37/benzo/issues/43).

**Evidence:** `NativeAppDemo.jsx:46–68` already uses semantic controls/state and notices; `BenzoLanding.jsx:16–23` has skip/main/navigation structure; `src/design/primitives.jsx:38–40` uses one download anchor. Focus and reduced-motion CSS exist. However, native-reference faint colors remain in `tokens.js:37–38` and `app-demo.css`, and view replacement/quit removes focused controls without demonstrated focus-return acceptance. This justifies a bounded rendered check, not a declaration that every transition is broken.

**Ownership:** the unowned marketing-page check is complete locally, including keyboard, 200% zoom, 320px wrapping and actual reduced-motion preference. No further marketing defect was demonstrated. Native/demo colors, labels and focus remain with the separate [P7](07_native-ux.md) accessibility session; update/footer behavior remains with U. Preserve historical `BenzoHybrid`/`BenzoMockup` and their tests.

**Acceptance:** observe keyboard and screen-reader names/state, First launch and permission Back, diagnostics Back, quit/restart and any delivered update controls; inspect focus after controls disappear. Check measured contrast, zoom/large-text reflow at narrow/desktop widths and actual reduced-motion preference. Fix only observed failures; use existing checks for changed behavior and retain browser receipts. These checks do not require native execution or a product redesign.

## Bounded trust brief

Reuse [#40](https://github.com/chrisrogers37/benzo/issues/40), [#41](https://github.com/chrisrogers37/benzo/issues/41) and [#60](https://github.com/chrisrogers37/benzo/issues/60), with #81's artifact-linked copy.

**Evidence:** main `c3a9070` explains legacy permissions, recovery limitations and qualified hardware behavior but lacks the root trust policies. Local `0dcc696` removes README's stale command recipe, corrects its homepage and adds source-qualified privacy documentation with FAQ/footer links. Local `e5cc56c` adds the owner-approved MIT LICENSE and SECURITY.md, linked from README/privacy. The cask's old homepage and physical promise remain with U/R; local documentation is not public delivery.

**Own:** concise site/README/privacy/security/license text and homepage/description metadata, coordinated with R/U's shared README and cask ownership. Document verified reads, system-wide writes, user-local originals, retention/recovery limitations, and native versus website network behavior separately. Distinguish current source from the downloadable v0.3.0. Any updater network description must come from its owner's delivered behavior, not an assumed future capability.

**Dependencies:** R owns recovery/retirement, signing, exact artifact and native acceptance; U owns installation/update behavior. Consume their accepted facts without designing those flows here. Keep the truthful Releases link and unreleased-demo caveat until native publication evidence changes. Do not publish a guessed direct asset, safe-uninstall promise or notarization claim from green packaging CI.

**Acceptance:** local copy, standard MIT text, links and independent reviews passed. The owner approved `contact@benzo.work` for private reports with best-effort handling; no supported-release line, response deadline or fix guarantee is promised. GitHub's API confirms private reporting remains disabled; the email choice needs no parallel reporting channel. No mailbox-delivery claim is made. About/cask license subitems remain with native/installation owners, and publication is separate. No further local license/privacy/security task, monetization prerequisite or external setting change is needed.

## Explicit no-work and deferred items

- The broken social-image reference (#73) is removed in source and live HTML. No further 404 repair is needed; new artwork is optional, deferred absent a demonstrated sharing need.
- Canonical/OG metadata, macOS 13+ wording, system fonts and required draft redirects are delivered. No new domain, font hosting or generic Vercel configuration is needed. Robots/sitemap/schema additions are deferred absent a demonstrated indexing requirement.
- Old demo gaps are addressed or obsolete: login/setup controls exist, First launch matches collapsed native options, womp is present, and blocker/timer UI was intentionally removed. Do not restore it.
- A generic performance trace/optimization campaign, volunteer conversion study, telemetry or monetization is not a completion gate. Reopen only for a concrete need; no conversion or installation gain is claimed.

Use the existing implementation checks when these bounded tasks are executed. For this documentation-only reconciliation, check links and the diff; do not rerun application suites. Keep native source, CI, website deployment, native publication and physical acceptance distinct, and keep umbrellas open for their actual remainder. [PR #98's historical site receipts](https://github.com/chrisrogers37/benzo/commit/90b78a476179086001eafe00ab0c790803b9a27b) and the [original P8 design/review record](https://github.com/chrisrogers37/benzo/blob/c3a9070b16c602c48b833a6e338fb40930ae4b04/documentation/plans/benzo-reorientation_2026-10-25/08_site-trust.md) remain evidence, not a second execution queue.
