# Benzo Open Work

## Complete engineering before paid enrollment — November 13, 2026

Owner clarified: finish the installable app and all engineering possible without
Apple Developer enrollment, signing credentials or notarization. Those remaining
distribution steps must not block source integration, packaging or ordinary tests.
This amendment integrates the existing draft work into the current recovery PR;
it does not open another dependent phase or modify the original worktrees.

- [x] Integrate manual update checker #103 and accessibility #105 with helper setup
  and recovery, preserving their tested behavior and active browser parity.
- [x] Adapt packaging #102 for a clearly labeled development DMG; validate both
  executable architectures, embedded daemon/plist, signatures and bundle metadata.
- [x] Prepare separate Developer ID signing and explicit notarization commands;
  no credential required or Apple upload during development packaging.
- [ ] Run local web/packaging checks, independent review, full-Xcode CI and real
  development-DMG verification. Record exact source and artifact hashes.
- [x] Document install/setup/update/removal behavior, deferred signed acceptance,
  and a portable continuation before the eventual separately authorized reset.

No relaxed helper identity check, automatic installer, public release, service
registration, enrollment purchase or host permission/power change is part of this
pre-enrollment work. The final signed artifact still needs native acceptance.

Review corrected a quit-admission race, guarded registration from read-only
distribution volumes, and made failed Git provenance inspection stop packaging.
Local evidence: 62 stubbed packaging checks, app source typechecking, and an
earlier 117-test web/build/audit pass. Final scroll/action-label changes and quit
regressions require the new combined CI run. Source typechecking and injected
fixtures are not XCTest or native acceptance. The native fixture review also
caught and corrected recursive `@Published` preference rollback before push.

## Lasting helper permission — November 13, 2026

- [x] Owner approved SMAppService direction and only the account completing setup
  (artemis on this Mac); enrollment in Apple Developer Program deferred.
- [x] Archive and remove the abandoned persistent-AppleScript prototype; retain
  the accepted recovery baseline and historical probe results.
- [x] Record scope, account policy and reset handoff requirements in
  [08_helper-authorization.md](../documentation/planning/tech_debt/benzo-remediation_2026-11-02/08_helper-authorization.md).
- [x] Implement and review authenticated helper enrollment, bounded operations,
  root-owned admission evidence, setup UX and active web parity.
- [x] Helper checkpoint 4f40b3b passed native/web tests, app/helper builds and security CI.
- [ ] Integrate packaging, update checker and native accessibility now; validate
  the signed artifact on approved hardware after credentials become available.
- [ ] Verify remote source, accepted release assets and portable handoff before
  the user's later, separately performed factory reset.

## Website trust follow-through — 2026-11-04

- [x] Owner selected implementation of unowned website accessibility/trust work.
- [x] Isolate from main; exclude native/demo accessibility, updater, recovery and release owners.
- [x] Complete the [bounded website work](../documentation/planning/benzo-web-accessibility-trust_2026-11-04.md), including owner-approved MIT licensing and private reports to contact@benzo.work with best-effort handling.
- [x] Record independent review and local evidence. Owner subsequently authorized consolidation/merge through PR #98; its final checks, merge state and matching website deployment record delivery. No native execution or unrelated issue closures.

## Historical containment checkpoint — 2026-11-02

The pending-merge/check states in the two checkpoints below are historical.
P1/#95 and containment/reads/diagnostics #99–101 are merged. The
[current reconciliation](../documentation/planning/tech_debt/benzo-remediation_2026-11-02/07_backlog-reconciliation.md)
supersedes their queue: recovery/packaging/native acceptance remain with the
existing #104/#102 owner, update/installation with #103, and native/demo
accessibility with its separate session. This session's delivery is PR #98.

- [x] YAGNI scope amended and independently reviewed; user requested implementation.
- [x] Implement plan 03 on `implement/benzo-containment`, from `eed0a969b097142042dc4412424fbc71a04d2c0d`.
- [x] Verify web behavior, inspect native changes and complete independent review; fix dangling-parent evidence finding.
- [ ] Full-Xcode native checks and exact-head security CI; no native acceptance on this host.
- [x] Owner approved branch push, draft PR and automatic Vercel preview on 2026-11-03; merge/release remain held.

The current order is **03 → 01 → 04 → conditional 02**, as recorded in
`documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md`.
Later dependent phases wait for user merge. This amendment supersedes the old
queue below; remaining manual recovery defects prevent an intermediate native release.

## Historical gated checkpoint — 2026-10-25

- [x] Phase 1 evaluation: `documentation/plans/00_benzo-evaluation_2026-10-25.md`.
- [x] Phase 2 plan and ironclad hardening: `documentation/plans/benzo-reorientation_2026-10-25/00_overview.md`; document corrections independently verified; recommended F1–F7 and Phase 3 approved with conditions on 2026-10-25.
- [ ] Phase 3 delivery: P1 PR #95 on `codex/benzo-build-foundation` has independent reviews and passing native/web/security CI at 0409b790, including the strengthened timer assertion. On October 26 the owner passed the manual visual/interaction check and explicitly waived before/after screenshots. This accepts regression parity, not conversion/design optimization. Required-check policy is applied; this documentation-only update still requires green PR-head checks, then user merge. P2 waits for that merge. See `documentation/plans/benzo-reorientation_2026-10-25/RUN_LOG.md`; one feature branch/PR per phase, user merges.

The Mac Mini is an always-on fleet host. Leave power settings, permission rules, login items and fleet processes untouched. Privileged/physical acceptance requires a separately approved test Mac. Outward and destructive actions retain their explicit approval gates.

## Historical backlog snapshot

The list below is retained as context. Its monetization, updater, release and hardware claims are not current authorization; the new plan records proposed issue dispositions.

Live tracker: **GitHub issues [#53–#82](https://github.com/chrisrogers37/benzo/issues?q=is%3Aissue+is%3Aopen+BZ-)**.
Archive + cross-reference: `documentation/planning/system-review_2026-07-07/04_github-issue-index.md`.

## Milestone 1 — Make the safety promise true

- [ ] #53 BZ-001 Restore on all termination paths
- [ ] #54 BZ-002 Robust pmset parsing + validate backup at save
- [ ] #72 BZ-020 Unit-test target with pmset fixtures
- [ ] #55 BZ-003 Deactivate refuses to fake success without backup
- [ ] #56 BZ-004 quit() surfaces restore failures
- [ ] #57 BZ-005 Rollback on partial pmset apply
- [ ] #61 #62 #63 #65 #66 #68 BZ-009/010/011/013/014/016 Settings-lifecycle fixes
- [ ] Kill-matrix verification (Cmd+Q, Force Quit, kill -9, logout, restart, crash)

## Milestone 2 — Frictionless, trustworthy install

- [ ] Apple Developer Program membership ($99/yr)
- [ ] #59 BZ-007 Hardened runtime + entitlements
- [ ] #58 BZ-006 Fix build-dmg.sh signing/notarization
- [ ] #71 BZ-019 CI compiles Swift + landing page
- [ ] #70 BZ-018 Release automation
- [ ] #69 BZ-017 Homebrew tap (or fix README)
- [ ] #64 #67 #74 BZ-012/015/022 Setup-flow correctness
- [ ] Retire "isn't notarized" copy (part of #81 umbrella)

## Milestone 3 — Monetization

- [ ] #60 BZ-008 License decision
- [ ] Merchant of record + offline license keys
- [ ] Trial + license UI
- [ ] #77 BZ-036 Sparkle auto-update
- [ ] #76 BZ-035 Logging + opt-in crash reporting
- [ ] #75 BZ-034 Clean uninstall flow
- [ ] #81 Landing page quality pass (includes #73 og-image, SEO, a11y)
- [ ] Privacy policy + terms page

## Backlog (umbrella issues)

- [ ] #78 Diagnostics correctness (BZ-024, 029, 030, 032, 050)
- [ ] #79 Sleep lifecycle & behavior (BZ-023, 025–028, 031)
- [ ] #80 Security hardening (BZ-033, 042)
- [ ] #82 Swift codebase debt (BZ-037, 044–049, 051, 052)

## Cleanup

- [ ] Close duplicate test issues #51, #52

## Recovery release continuation — November 3

- [x] Independently review and merge containment PR #99; merged-head build/security checks pass.
- [x] 01: PR #100 merged after independent review; full Xcode builds, 44 native tests, 39 web tests and security CI passed.
- [ ] 04: implementation, local checks, browser parity and independent review complete on `implement/benzo-diagnostics` from `a763f95`; full Xcode/required CI and merge pending.
- [ ] 02: settle dedicated target/authorization gates, implement recovery/quit, and verify on approved test hardware.
- [ ] Publish the native installer only after recovery fixes and native acceptance pass.

Owner requested reviewed merge then release and selected completing recovery fixes first. This supersedes earlier no-merge authority for this work; fleet host restrictions remain.
