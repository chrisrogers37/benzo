---
title: "Benzo design remediation: shipped site and remaining work"
status: partially-complete
created: 2026-10-26
updated: 2026-10-27
---

# Purpose and current status

Make Benzo easier to understand, trust, download and begin using while preserving its compact, playful identity. The owner reviewed the hosted design, approved publication, and merged [PR #97](https://github.com/chrisrogers37/benzo/pull/97). The approved site is live at [benzo.work](https://benzo.work/) from main commit `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both `/draft` and `/draft/` redirect to `/`; the old page remains only as unbundled historical source.

This is a completed site release and a partial contribution to P8, **not completion of the native/product acceptance plan**. The remaining [P2–P8 delivery order](../benzo-reorientation_2026-10-25/00_overview.md) is unchanged. P1 is merged in [PR #95](https://github.com/chrisrogers37/benzo/pull/95); **P2 is the next product phase**.

The approved origin line remains:

> Built because I wanted my Mac to sleep when I do.

## Complete as of October 27

- [x] Owner-approved hero, section hierarchy, direct copy, system fonts and pink capsule identity.
- [x] Core web design module for tokens, typography, layout, copy, metadata, links and native-reference presentation.
- [x] Full master-switch/page reactivity through one demo state, including restore, setup, sleep, quit and restart.
- [x] Interactive settings, timers, diagnostics and footer controls checked on desktop/mobile; 320px timer clipping corrected.
- [x] Copy and spacing passes, compact demo guidance, and docks/displays/audio gear folded into the explanation.
- [x] Truthful Releases CTA, installation/permission/recovery caveats, existing contact link, canonical metadata and draft redirects.
- [x] Branch pushed, PR #97 owner-merged, Git production deployment verified and all post-merge CI checks green.

Evidence: 33 web tests and local build passed. Layouts were observed at 1440, 768, 375 and 320px. Marketing contrast measurements pass for the recorded text/CTA/focus colors; native-panel exceptions remain. [Post-merge build CI](https://github.com/chrisrogers37/benzo/actions/runs/40542235848) passed web plus full-Xcode Debug/Release and unhosted native tests. [Security CI](https://github.com/chrisrogers37/benzo/actions/runs/40542235661) passed npm audit and Gitleaks. Vercel production `dpl_4dmJ6tesPWax2tzv7i5eU5E2cXAG` serves the merged commit at the public domain. Anonymous page/assets returned 200; draft/www redirects returned 308.

## What remains, in delivery order

| Order | Remaining work | Completion evidence |
|---|---|---|
| P2 | Reproducible packaging, explicit signing modes, exact compatibility and installation guidance. | Accepted artifact, script checks, signing/notarization for the selected mode and approved clean-Mac install. |
| P3 | Bounded command execution and explicit, finite, account-scoped permissions. | Runner/policy fixtures and dedicated-Mac permission acceptance. |
| P4 | Profile-aware originals, durable recovery, truthful unresolved states and safe restore. | Recovery/readback/failure tests plus dedicated-Mac round trips. |
| P5 | Timer cancellation, sleep requests, quit, login and uninstall/retirement. | Accepted native lifecycle/recovery contract and matching demo states. |
| P6 | Diagnostics that distinguish empty, error, partial and unknown results. | Parser/provider checks and qualified hardware/OS evidence. |
| P7 | Truthful native labels, legible contrast and native accessibility. | Approved native presentation/runtime evidence; refresh demo parity afterward. |
| P8 remainder | Final product/artifact copy, privacy/license/security/support docs, social asset, full accessibility/performance checks and issue reconciliation. | P2–P7 evidence, owner rights/reporting decisions, browser checks and exact artifact/link receipts. |
| Outcome validation | Three to five volunteer comprehension sessions; later approved install/first-use sessions. | Manual observations; separate clicks, downloads, completed installs and active use. |

Remaining browser work includes reduced-motion preference emulation, zoom/large text, screen-reader checks and a reproducible performance trace. Native pixel parity, physical-phone touch and Intel/Apple Silicon sleep/recovery outcomes remain unobserved. No P2–P7 implementation or conversion lift is claimed by the site release.

## Priorities from the audit

| Priority | Evidence at audit | Remediation | Likely impact / confidence / effort |
|---|---|---|---|
| 1. Explain the purpose and next action | The original page places its large download CTA below the demo and explanatory sections; the first draft adds several slogan-like headings. | State the menu-bar sleep-control purpose directly, retain the dock/display/audio context, and put a truthful Mac download link near the hero and at the end. | High / high / small |
| 2. Restore useful interaction | `NativeAppDemo.jsx` owns its state internally; the draft wrapper stays visually active when its master switch is off. The original wrapper responds through `isActive`. | One demo state must drive the panel, background treatment and download treatment. Test the whole page, including return to On. | High / high / small–medium |
| 3. Remove conflicting trust claims | `index.html` promises no heat, fan or battery wear; current native option copy includes physical USB claims. Setup uses a persistent administrator permission rule; current restoration has failure paths. | Centralize verified marketing facts and qualify current limits. Route native wording and distribution guarantees through their existing phase owners. | High / high / small for copy; native/distribution work is separate |
| 4. Make the page easier to read | The draft uses an oversized tightly spaced headline, italic pink emphasis, tiny uppercase monospace labels and repeated decorative numbering. Audit contrast findings also apply to the older site. | Use a restrained system sans hierarchy and readable body copy. Preserve the pink pill and native panel typography. Measure contrast rather than assuming a font change fixes it. | Medium–high / high for readability, medium for preference / small |
| 5. Reduce repeated sources of truth | Web colors, copy and native presentation are spread across inline styles, draft CSS, demo components, fixtures and metadata. | Use a small core web design module with explicit marketing/native boundaries and one exported demo interface. Add integration checks at that boundary. | Medium / high / medium |

These are design hypotheses, not measured conversion gains. No click, download, installation or active-user lift has been established.

## Delivery documents

- [Implementation and acceptance](01_local-preview.md): shipped design, module/state ownership, observed checks and remaining limits.
- [Ordered remediation and validation](02_delivery-and-validation.md): dependencies, public-claim gates and lightweight outcome validation.
- [Delivery log](../benzo-reorientation_2026-10-25/RUN_LOG.md): merged PRs, CI and deployment receipts.

## Boundaries

Later owner approvals authorized hosted previews, site publication, branch push and PR #97; those actions are complete. They do not authorize a native release, purchases, analytics, new frameworks or changes to repository security settings. Do not launch native Benzo or change this Mac Mini's power, sleep, lock, login, permission or fleet state. Native runtime, install and physical sleep acceptance require separate authorization on a suitable test Mac.
