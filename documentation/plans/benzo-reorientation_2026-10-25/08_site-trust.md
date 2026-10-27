---
title: "[plan] P8 — Accessible landing page and accurate trust documentation"
type: plan
status: partially-complete
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-27
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size M, risk medium. Complete site interaction/accessibility and make installation, privacy, support, licensing and hardware claims match the actual product and distribution evidence. One PR on `codex/benzo-site-trust`; local source acceptance is distinct from public deployment and production-link acceptance.

The owner-authorized [design remediation supplement](../benzo-design-remediation_2026-10-26/00_overview.md) is now shipped, not awaiting design review. [PR #97](https://github.com/chrisrogers37/benzo/pull/97) merged as `eed0a969b097142042dc4412424fbc71a04d2c0d` on October 27. The public page uses `src/landing/BenzoLanding.jsx`, both draft paths redirect to `/`, and Git-based Vercel production serves this commit at https://benzo.work/. All post-merge web/native/audit/Gitleaks checks passed.

## Completed site subset

- [x] Approved hierarchy/copy/system fonts and shared `src/design/` presentation module.
- [x] One demo state drives master switch, page theme, settings/timers/setup/restore/quit/restart; 33 web tests pass.
- [x] Responsive copy/spacing and demo controls checked at 1440, 768, 375 and 320px; measured marketing text/CTA/focus colors pass.
- [x] Removed unsupported physical promises, external font dependency and nonexistent social-image references from the public page; retained current-product caveats.
- [x] Releases/contact links, public canonical/og:url, draft/www redirects, owner review, PR merge and live deployment verified.

## Remaining P8 acceptance

Keep the full verification checklist below open until its complete scope is met. Remaining work is final P2–P7 product/artifact reconciliation; native-panel contrast and native reference comparison; reduced-motion preference, zoom/large text, screen-reader and full focus/state checks; a reproducible performance trace; social image/remaining metadata; privacy, rights/license, security-reporting and final support/recovery documentation; and item-level issue reconciliation. Website publication does not establish an accepted native artifact, successful install, physical sleep benefit or conversion gain.

## Evidence

Historical audit at `a0c12f1` (not the current public route): `src/BenzoHybrid.jsx` contained click-only controls, a hard-coded countdown, misleading OS/physical claims and a command recipe omitting womp. The evaluation measured 2.323:1 body/link and 3.098:1 CTA combinations requiring contextual correction. `index.html:13,19` refers to an absent social image; site requests Google Fonts. README advertises MIT while no LICENSE exists. Missing vercel.json alone does not prove broken deployment.

## Implementation Plan

### Dependencies

For final P8 completion: P7 merged. The separately approved site subset above is already published and does not waive this dependency. F6/F7 accepted or claims explicitly withheld while outcome issues stay open. Browser policy must permit local acceptance; do not bypass a saved denial. Deployment authority remains separate, including automatic PR previews/main deploys.

### Blocks

Final web/trust acceptance and closure of #43/#81. Epic completion still depends on remaining dedicated native/artifact/outward evidence, not just eight merged PRs.

### Steps

1. **Own files:** `src/landing/`, `src/design/`, demo/components/state/fixtures/tests; `src/BenzoHybrid.jsx` only as historical compatibility requires, `src/App.jsx` only as necessary, `index.html`, `public/` metadata/social assets, README, new `SECURITY.md`, `PRIVACY.md`, conditional `LICENSE`, build/recovery/support docs and capability matrix; `Casks/benzo.rb` description/license metadata only if verified; native About/license surface only if needed to fulfill #40 without adding a new product surface. No framework migration.
2. Replace click-only noninteractive elements with native semantic buttons/toggles/links, meaningful accessible names/state, visible keyboard focus, Escape/return focus behavior for dialogs and no nested interactive download CTA. Preserve P7 state parity. Preserve and reverify P5’s injected-clock selected-duration/frozen-intent/countdown/cancel/system-sleep behavior; do not introduce it for the first time here or restore a hard-coded 04:32 display. Mark simulation as demonstration, not actual Mac control.
3. Apply measured contrast corrections, reduced-motion behavior and responsive layout at 375px phone, 768px tablet and 1440px desktop plus narrow/large-text overflow checks. Validate keyboard and screen-reader semantics in a real authorized browser; automated DOM checks supplement them. Capture baseline production bundle/network and a reproducible throttled local performance trace before optimizing. Change blur/animation/font loading only for observed costs; no arbitrary memoization, code splitting or unsupported field scores.
4. Align OS copy with the actual deployment target (currently macOS 13+); make sleep/USB/network claims conditional on declared capability evidence. Explain requested versus observed configuration and restore scope. Remove the unsupported exact command recipe or generate its seven-key content from a single presentation policy fixture; if retained, womp means Wake-on-LAN, not guaranteed USB wake prevention. Keep tcpkeepalive opt-in consequences clear. The site must not say arbitrary blocker termination remains a feature. Follow the owner-ratified F1/F3 success promise: configuration/recovery claims alone unless physical benefit has been observed on the named qualified target; failed required physical acceptance returns to the owner for the specified narrower-scope decision.
5. Use existing verified origin for canonical/og:url/robots/sitemap and justified SoftwareApplication metadata. Add a real correct-size local social image, correct absolute URLs, MIME/asset checks and alt text where rendered. No new domain. Local build asset correctness does not prove production image availability. Use a verified released direct artifact only when it exists; otherwise a truthful Releases link, not a guessed version URL. Signing/notarization wording derives from the exact accepted distribution mode, not repaired script source.
6. Document native local reads, system writes, user-local recovery files, persistent account grant, shared-machine consequences, recovery limits and uninstall path. Explain pending execution uncertainty, the verified-later-boot recovery limit without promising an automatic restart, and one-controller retirement/handoff refusal. State retention precisely: current unresolved journal plus required previous valid generation, one last resolved receipt, and preserved unresolved/legacy originals until explicit appropriate resolution; no history archive or automatic evidence deletion. Distinguish native network behavior from website/font requests. Prefer self-hosting existing font assets only if licensing and practical evidence support it; otherwise disclose external requests and record BZ-054(b)'s explicit deferral/closure reason. No blanket “nothing leaves the device” claim across both surfaces.
7. Under F7, add MIT only after owner confirms rights/intent; otherwise remove unsupported license claims and leave #60 unresolved. SECURITY.md states supported versions/scope and an approved reachable private reporting route. Enabling repository private vulnerability reporting is an external setting change requiring separate approval; docs alone do not close #40. Reconcile About/cask license subitems against actual available surfaces. Do not implement monetization or infer relicensing rights from README.
8. Reconcile every #81 subitem and remaining issue ledger row. For BZ-053 inspect actual Vite/Vercel build assumptions: add vercel.json only for a demonstrated reproducibility requirement, otherwise record why defaults suffice. Preserve real deployment/account state. Update support and development docs to final verified commands and limits, and mark historical plans as context rather than active implementation instructions.

## Test Plan

Run web interaction/state/accessibility-semantic tests, `npm run build`, audit/gitleaks and retained native/core checks. Authorized browser acceptance covers keyboard-only navigation, focus, semantic names/states, dialogs/timer/recovery demo, reduced motion, contrast, viewport overflow, console/network failures and local metadata assets. Record trace conditions/bundle sizes; field performance remains unmeasured.

Actual production download/image/metadata and private-reporting-setting checks happen only after separately approved deployment/settings actions. Native About/license UI changes require dedicated-Mac presentation acceptance. Legal/rights confirmation is owner evidence, not a unit test.

## Verification Checklist

- [ ] All selected demo states/timer interactions are semantic, keyboard accessible and consistent with native behavior.
- [ ] Measured contrast/responsive/reduced-motion/browser checks pass; performance statements name measurement scope.
- [ ] OS, physical outcome, command, download and signing claims match current evidence; unsupported claims are removed.
- [ ] Social metadata references a valid built image; production receipt remains separate until deployment is approved/observed.
- [ ] Privacy/support/license/reporting statements have owner/source evidence; #40/#60 retain any unresolved rights or external-setting condition.
- [ ] #43/#81 rows and all issue dispositions are reconciled; current-head tests/build/security and independent review pass; user merges.

## What NOT To Do

Do not deploy to obtain a screenshot without authority, buy a domain, enable PVR silently, add analytics, invent license rights, claim notarization from source changes, or report missing configuration as a defect without evidence. Do not call eight merged source PRs full product acceptance while artifact/native/outward issue gates remain open.

## Context

- Source: claudna:forge; area: landing accessibility/trust/docs; effort M; risk medium; priority medium.
- Primary issues: #40, #41, #60, #73, #81. Completes web scope of #43 and distribution-linked copy conditional on P2 receipts.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC08:** Functional demo clock/frozen intent/countdown/cancel moves to P5. Document correction independently verified.
- [x] **IC10:** Bounded one resolved receipt plus necessary unresolved generations/legacy evidence; safe pruning and retention disclosure. Document correction independently verified.
- [x] **IC14:** Made configuration/recovery versus named-target physical outcome success promise an explicit owner choice and reconsideration rule. Document correction independently verified.
