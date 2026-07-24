# GitHub Issue Filing Plan — System Review 2026-07-07

How the 54 tracker items ([`01_issue-tracker.md`](01_issue-tracker.md)) map onto
GitHub issues, and how to file them in one command.

## Division of responsibility

- **This folder (repo docs)** — permanent archive: the review analysis, the roadmap,
  and this mapping. Never becomes a live checklist.
- **GitHub issues** — the live tracker. PRs close them with `Fixes #N`, milestones
  give a "what's left before we can charge money" view, and agents can be pointed at
  issue numbers.
- After filing, GitHub becomes canonical: the tracker gets a "filed" header and
  `.claude/todo.md` switches to issue numbers.

## What gets filed

**30 issues total** — every P0/P1 individually, the three P2 items the roadmap's
Milestone 3 depends on individually, and the remaining P2/P3 items as five umbrella
issues so the backlog stays legible.

### Individual issues (25)

| Tracker ID | Milestone |
|------------|-----------|
| BZ-001, BZ-002, BZ-003, BZ-004, BZ-005 (P0 safety) | M1 — Safety promise |
| BZ-009, BZ-010, BZ-011, BZ-013, BZ-014, BZ-016, BZ-020 (P1 lifecycle/testing) | M1 — Safety promise |
| BZ-006, BZ-007 (P0 build/notarization) | M2 — Frictionless install |
| BZ-012, BZ-015, BZ-017, BZ-018, BZ-019, BZ-022 (P1 setup/CI/distribution) | M2 — Frictionless install |
| BZ-008 (P0 license decision) | M3 — Monetization |
| BZ-021 (P1 og-image) | M3 — Monetization |
| BZ-034, BZ-035, BZ-036 (P2, but M3 deliverables: uninstall, logging, Sparkle) | M3 — Monetization |

### Umbrella issues (5)

| Umbrella | Covers | Milestone |
|----------|--------|-----------|
| Diagnostics correctness pass | BZ-024, BZ-029, BZ-030, BZ-032, BZ-050 | backlog |
| Sleep lifecycle & app behavior fixes | BZ-023, BZ-025, BZ-026, BZ-027, BZ-028, BZ-031 | backlog (note: BZ-023 pairs with BZ-016 in M1) |
| Security hardening follow-ups | BZ-033, BZ-042 | backlog |
| Landing page quality pass | BZ-038, BZ-039, BZ-040, BZ-041, BZ-043, BZ-053, BZ-054 | M3 — Monetization |
| Swift codebase debt burn-down | BZ-037, BZ-044–BZ-049, BZ-051, BZ-052 | backlog |

## Status

**Filed 2026-07-22.** Issues [#53–#82](04_github-issue-index.md) created on GitHub.
See [`04_github-issue-index.md`](04_github-issue-index.md) for the full BZ→issue map.

Cloud-agent token could create issues but not labels/milestones — labels were mapped to
existing repo labels; milestone assignments are in each issue body. Close test issues
[#51](https://github.com/chrisrogers37/benzo/issues/51) and
[#52](https://github.com/chrisrogers37/benzo/issues/52) manually.

## How to run (historical)

The original script (`file-issues.sh`) creates custom labels + milestones — use from a
machine with full repo admin if re-filing. What was actually run:

```sh
./documentation/planning/system-review_2026-07-07/file-issues-mapped.sh
```
