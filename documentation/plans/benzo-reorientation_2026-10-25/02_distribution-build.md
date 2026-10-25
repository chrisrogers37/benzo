---
title: "[plan] P2 — Deterministic distribution build contract"
type: plan
status: draft
owner: claudna:forge
created: 2026-10-25
updated: 2026-10-25
tags: [enhancement, security, reliability]
repos: chrisrogers37/benzo
---

## Summary

Part of the [epic](00_overview.md). Size M, risk high. Make build mode, architecture, version and signing claims explicit and mechanically checked. One PR on `codex/benzo-distribution-build` prepares artifacts and safe build CI; releases, notarization uploads, tap creation and deployments remain separately gated.

## Evidence

`scripts/build-dmg.sh:10` parses version through an unvalidated pipeline; `:19` deletes shared `build/`; `:54` silently falls back from export failure; `:63` submits `.app` directly. `project.pbxproj:326,336,350,360` repeats build/marketing versions; `FooterView.swift:25` hardcodes v0.3.0; `package.json:4` is 0.1.0. `Casks/benzo.rb:5` describes a release URL, not proof a supported tap exists. No current exact-artifact architecture/signature acceptance was collected.

## Implementation Plan

### Dependencies

P1 merged by user. F6 distribution recommendation accepted/corrected before corresponding mode assumptions. P2 → P3 is scheduling, not a technical runtime dependency; if packaging alone blocks safety work, return a concrete owner-approved ordering/scope amendment rather than silently proceeding or lowering acceptance. Current signing credentials, Apple uploads or publishing are not authorized by implementation approval alone.

### Blocks

P3 and trustworthy P8 installation/signing copy. No public release before P4 and P5 native recovery/lifecycle acceptance, regardless of P2 script success.

### Steps

1. **Own files:** `scripts/build-dmg.sh`; new `scripts/tests/build-dmg-test.sh` and `scripts/tests/fixtures/`; new `.github/workflows/artifact-build.yml`; `Benzo/Benzo.xcodeproj/project.pbxproj`, `Benzo/Benzo/Info.plist`, new `Benzo/Benzo/Models/AppVersion.swift`, `Views/FooterView.swift`; `README.md`, `CLAUDE.md`, `Casks/benzo.rb` only for metadata/truthful route (uninstall behavior P5); extracted demo fixture/version display; website install copy touched only to remove a false route.
2. F6 also offers community-only preparation: produce/verify that real artifact, explicitly reject or disable developer-id mode, remove the unsafe fallback/notary path, and retain signing issues open. Dual-mode preparation remains the recommendation, with additional maintenance despite deferred signed benefit; implement only the ratified branch. For the recommended branch, replace implicit fallback with required CLI mode: `scripts/build-dmg.sh --mode community|developer-id --output-dir <new-dir> [--build-number <positive-integer>] [--notary-profile <approved-profile>]`. No mode is an error. Reject existing/non-task output targets, unsafe/ambiguous versions, missing tools and contradictory signing inputs before archive. Use `mktemp -d` for work; do not `rm -rf build`, erase existing output, print secrets or automatically publish. Script uses exact argv, not command construction from untrusted version text.
3. `community` archives explicitly without Developer ID assumptions, applies/checks deliberate ad-hoc signing as needed and labels output “not notarized.” `developer-id` requires the selected valid identity/team and approved notary profile, enables/inspects hardened runtime and fails on export/signature/notarization failure. It never becomes a community artifact on failure. Source compilation and mocked credentials do not satisfy this mode's acceptance.
4. Archive Release for `arm64 x86_64` with `ONLY_ACTIVE_ARCH=NO`; inspect the actual exported executable using `lipo -archs` and fail if expected slices are absent. Validate effective plist versions and signature via `codesign --verify --deep --strict`, `codesign -dv --verbose=4` and appropriate assessment; record exact output artifact hash. Avoid entitlements merely to make a nonempty file: add only justified runtime requirements. Stage a supported zip with `ditto -c -k --keepParent`, submit that container if authorized, staple the app, create the DMG, then verify/submit/staple the final container as the chosen notarization path requires. Record that each submission is an outward action requiring scoped approval.
5. Choose native `MARKETING_VERSION` as the app/display version authority; `AppVersion` reads bundle short/build versions with a safe “unknown” fallback. The private site package version is independent build metadata, not a second app release version; document this policy and remove obsolete 0.2.1 requirements. Supply a positive monotonically allocated build number for release candidates; verify generated Info.plist rather than assuming duplicate source declarations change runtime. No tag/release is created to bump metadata.
6. Artifact workflow uses `contents: read`, explicit manual trigger and community mode by default, no tag-publish/tap/deploy stage and no signing secret exposure. Script fixtures inject an isolated tool directory to capture argv, emulate failures and verify fail-closed behavior. Public workflow/artifact execution is not automatically authorized; run only within the approved CI/push boundary.
7. Inspect advertised Homebrew route with current official behavior during implementation. The selected minimal plan removes unverified `brew install` instructions consistently and retains a truthful GitHub Releases link until a verified direct artifact exists. Do not publish a tap or delete the maintained cask. Update build/trust instructions for mode-specific Gatekeeper expectations; no “zero warnings” guarantee.

## Test Plan

Safe script fixtures exercise invalid version/output/mode, failed export, missing slice, failed signature, rejected notary, staple error and no credential-output behavior. These use stub tools only and must not invoke Apple, hdiutil against user disks, signing identities or release endpoints. Run P1 gates and `bash scripts/tests/build-dmg-test.sh`.

On a separately approved full-Xcode build host, produce a real community artifact and inspect version/slices/signature. Developer ID acceptance requires actual approved identity/profile, exact notarized/stapled DMG and clean-Mac install/launch; Intel and Apple Silicon smoke checks remain distinct. A source setting or fixture cannot replace these receipts.

## Verification Checklist

- [ ] Script fixtures and all current-head build/security gates pass; output-path/credential safety is checked.
- [ ] No signed-mode failure can fall through to a mislabeled community artifact.
- [ ] Real community artifact has matching declared architecture/version/signature evidence; release mode is clearly labeled.
- [ ] Unverified Homebrew instructions are removed from every advertised surface or independently verified with separate authority.
- [ ] #20/#33 closure uses actual scope; #31/#32/#58/#59 retain unmet real-artifact acceptance; #34 remains open for original publication/tap scope unless owner explicitly narrows it.
- [ ] Independent review completed and user merges; no public release, tap, Apple submission or deployment occurs without scoped authority.

## What NOT To Do

Do not submit an app directory to notarytool, assume an archived app is ad-hoc signed, silently downgrade trust, use current host credentials because they exist, delete shared build paths, or close release automation merely because an artifact workflow was added. No actual notarization is required to write/test the preparation code; its outcome remains gated.

## Context

- Source: claudna:forge; area: packaging/distribution; effort M; risk high; priority high.
- Primary issues: #20, #31, #32, #33, #34, #58, #59. Cross-items: #23, #81/BZ-053/BZ-054, #82/BZ-044/BZ-051/BZ-052.

## Adversarial Review Findings

The applicable document corrections were **independently verified** in the two targeted passes after one six-lens cycle with six adversarial critics; this was not a second full panel. Checked items below mark document correction only, not implementation/test completion. Implementation acceptance remains separate. The owner ratified recommended F1–F7 with their conditions and approved Phase 3 on 2026-10-25; required implementation/native/browser/artifact gates remain.

- [x] **IC12:** Distinguished schedule from runtime dependency; packaging-only block requires owner-approved amendment. Document correction independently verified.
- [x] **IC15:** Added community-only smaller alternative; dual-mode recommendation acknowledges deferred benefit/maintenance. Document correction independently verified.
