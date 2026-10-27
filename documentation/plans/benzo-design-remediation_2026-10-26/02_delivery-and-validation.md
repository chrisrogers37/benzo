# Ordered remediation and validation

The approved design and regression fix are shipped at https://benzo.work/ and merged in PR #97. This owner-authorized site release is a partial P8 contribution; it does not turn proposed native behavior into shipped claims or change the remaining [approved phase order](../benzo-reorientation_2026-10-25/00_overview.md). P1 is merged; P2 is next. As P3–P7 change the product, update the shared demo in the same behavioral phase, then complete P8 trust/accessibility acceptance against the accepted P7 product state.

## Dependencies and factual gates

| Existing phase | Required output for the site | Wording/acceptance gate |
|---|---|---|
| P2 — Distribution/build | Exact supported artifact, version, minimum OS, architectures, signing/notarization mode and install instructions. | macOS deployment target is source evidence; chip support, signatures and first-launch success need the actual artifact. Do not claim notarization from a build script, invent a direct asset URL or turn a repository cask into proof of a working tap. |
| P3 — Commands/permissions | Accepted persistent account-scoped permission model and install/repair/removal disclosure. | Current permission behavior must be described as current. Future narrower grants cannot be advertised until delivered and verified. Never imply the rule is exclusive to Benzo if other programs for the authorized account can use it. |
| P4 — Recovery | Verified changed-cell originals, visible unresolved states and explicit restore results. | Restore means previous recorded settings Benzo changed, not guessed defaults. No guaranteed restore-on-quit/crash claim; describe known current limits until the new contract passes. |
| P5 — Lifecycle | Accepted timer cancellation, sleep request, quit, login, uninstall and recovery paths. | The demo mirrors the delivered contract. A successful request is not physical sleep proof; an exited process is not proof recovery succeeded. |
| P6 — Diagnostics | Distinct empty/error/partial/unknown results, capability evidence and bounded local receipts. | Present reported blockers and observed configuration honestly. Keep hardware/OS/power-source/dock qualification separate from setting-readback evidence. |
| P7 — Native UX | Truthful native labels, accessible states and approved presentation evidence. | Resolve misleading native option descriptions, including categorical USB behavior. Compare web panel to the final native UI; source matching alone is not “100% visual parity”. |
| P8 — Site/trust | Design/core-module/production work is complete; reconcile final product copy/docs, finish accessibility/social assets and exact artifact acceptance. | Rights, security-reporting, privacy and native/artifact gates remain. Site deployment is verified; a working CTA is not a successful install. |

Use the existing phase documents for implementation mechanics; this supplement does not duplicate their recovery or permission designs. Distribution and product limitations are product work, not landing-page conversion bugs.

## P8 package: delivered and remaining

Delivered: core module and chosen hierarchy, copy cleanup, interactive demo regression fix, responsive spacing, public metadata/canonical URL, Releases/support links, draft redirects, owner review, PR merge and Git-based production deployment. Reuse these; do not rebuild the page. The numbered items below describe final product reconciliation and the remaining package.

1. Reuse the core web design module and accepted preview hierarchy: clear purpose + download, interactive native-matching demo, compact dock/display/audio explanation, install steps, trust/compatibility FAQ, final CTA and origin line.
2. Update marketing, native-matching presentation, README/support copy and static metadata against the same accepted product facts. Preserve a visible simulation disclosure and all interactive controls.
3. Publish exact compatibility/signing/recovery guidance only when its phase evidence exists. Keep the working Releases route if a direct supported artifact is still unavailable.
4. Complete P8's existing metadata/social asset, privacy, licensing and security-reporting work. Verify rights before adding MIT; distinguish the website's requests from native network behavior; do not represent a document as proof an external reporting setting exists.
5. Run local browser/test/build/security acceptance and independent review. Record any native or outward verification gap. Existing site deployment and CI are verified. Exact native artifact download/install acceptance and any future release/settings actions remain separately gated.

Defer decorative motion, new illustrations, large font families, elaborate testimonials, analytics and additional frameworks. Preserve compactness, the capsule/pink identity, the approved tagline and the useful interactive demonstration. Remove duplicate slogans, unsupported physical promises and unhelpful terminal-command recipes unless maintained from a verified policy source.

## Lightweight validation

Use three to five volunteer Mac owners, including someone who uses a dock or audio setup. The owner can arrange this later; this plan does not authorize messaging people. Show the published page without a leading introduction. A historical comparison is optional and must be labeled as such. This is qualitative feedback, not a statistically powered conversion experiment.

Ask them to perform these tasks and record confusion, completion and time manually:

- After a brief look, explain what Benzo does, who it is for and what it does **not** guarantee.
- Find the download; say where it goes and whether their Mac is supported.
- Use the demo's master switch and explain the relationship between its state and the page. Find one setting, the timer and diagnostics without being coached.
- Explain the permission request and what to do if restoration is unresolved.
- Describe the next step after download and where they would seek help.

An optional clean-Mac install/first-use session follows only after the appropriate artifact/native gates and separate host approval. Never run it on the fleet Mac to fill an evidence gap. Include both Intel and Apple Silicon evidence for claims that cover both; forum reports establish that a problem occurs, not Benzo efficacy on all models.

## Keep outcome measures separate

| Measure | What it can establish | What it cannot establish |
|---|---|---|
| Visitor comprehension/task observation | Whether a small sample can understand and navigate the page. | A percentage lift in site conversion or population preference. |
| Download CTA click | Intent to visit Releases or request an artifact, if actually observed. | A completed artifact download, install or active user. |
| Release asset download count | Artifact requests recorded by the host, subject to repeat/bot activity. | Unique people, successful installs or use. |
| Observed completed install and first launch | Success for the named artifact, Mac and macOS session. | Repeat active use, hardware-wide compatibility or physical sleep benefit. |
| Voluntary follow-up after real use | Whether that participant continued using Benzo and why. | A reliable active-user total or retention rate without a defined measurement method. |

No analytics installation is required for this plan. Start with manual observations and support feedback. If traffic later justifies measurement, propose the event definitions and privacy choices separately; do not claim a conversion gain from a visual preference, screenshots, test count or regression pass.
