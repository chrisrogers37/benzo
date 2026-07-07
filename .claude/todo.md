# Benzo Open Work

Source of truth: `documentation/planning/system-review_2026-07-07/`
(`01_issue-tracker.md` for triaged issues BZ-001…BZ-054, `02_roadmap-to-revenue.md`
for the milestone plan).

## Milestone 1 — Make the safety promise true

- [ ] BZ-002 Robust pmset parsing + validate backup at save time
- [ ] BZ-020 Unit-test target with pmset fixture tests
- [ ] BZ-001 Restore on all termination paths + launch reconciliation
- [ ] BZ-004 quit() surfaces restore failures (no `try?`)
- [ ] BZ-003 Deactivate refuses to fake success without backup
- [ ] BZ-005 Rollback on partial pmset apply
- [ ] BZ-009 / BZ-014 / BZ-016 / BZ-010 / BZ-013 Settings-lifecycle fixes
- [ ] BZ-011 Shell calls off the main thread
- [ ] Kill-matrix verification (Cmd+Q, Force Quit, kill -9, logout, restart, crash)

## Milestone 2 — Frictionless, trustworthy install

- [ ] Apple Developer Program membership ($99/yr)
- [ ] BZ-007 Hardened runtime + entitlements
- [ ] BZ-006 Fix build-dmg.sh signing/notarization path
- [ ] BZ-019 CI compiles Swift + landing page on PRs
- [ ] BZ-018 Release automation (tag → notarized DMG → release → cask bump)
- [ ] BZ-017 Create homebrew-benzo tap (or fix README install docs)
- [ ] BZ-015 / BZ-012 / BZ-022 Setup-flow correctness
- [ ] BZ-054(c) Retire "isn't notarized" copy everywhere

## Milestone 3 — Monetization

- [ ] BZ-008 License decision (recommendation: open-core MIT + paid signed builds)
- [ ] Merchant of record (Paddle / Lemon Squeezy) + offline license keys
- [ ] Trial + license UI (reuse BZ-048 Settings scene)
- [ ] BZ-036 Sparkle auto-update via release workflow
- [ ] BZ-035 Logging + opt-in crash reporting
- [ ] BZ-034 Clean uninstall flow
- [ ] Landing page: pricing, buy CTA, BZ-021 og-image, BZ-040 SEO, BZ-041 OS copy, BZ-039 a11y
- [ ] Privacy policy + terms page
- [ ] Privacy-friendly site analytics

## Backlog (P2/P3 burn-down)

See `01_issue-tracker.md` — BZ-023…BZ-054 (diagnostics correctness, DI refactor,
landing-page decomposition, mockup sync pass, dead code, doc drift).
