# Benzo Open Work

## Current gated work — 2026-10-25

- [x] Phase 1 evaluation: `documentation/plans/00_benzo-evaluation_2026-10-25.md`.
- [x] Phase 2 plan and ironclad hardening: `documentation/plans/benzo-reorientation_2026-10-25/00_overview.md`; document corrections independently verified; recommended F1–F7 and Phase 3 approved with conditions on 2026-10-25.
- [ ] Phase 3 delivery: P1 published as draft PR #95 on `codex/benzo-build-foundation`; native/web/security CI passed at eb85cf3. Claude simplification and independent Sonnet/Opus reviews are complete; the resulting one-assertion test strengthening needs CI at its new head. Required-check policy is applied; browser evidence remains pending and P2 waits for user merge. See `documentation/plans/benzo-reorientation_2026-10-25/RUN_LOG.md`; one feature branch/PR per phase, user merges.

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
