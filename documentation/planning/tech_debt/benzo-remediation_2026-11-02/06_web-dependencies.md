---
title: "[tech-debt] Use routine dependency maintenance instead of a version-bump phase"
type: decision
status: ratified
owner: claudna:audit
created: 2026-11-02
tags: [tech-debt, "priority:low"]
repos: chrisrogers37/benzo
---

## Decision

The accepted 2026-11-02 YAGNI rescope retires F7's planned two-package version-bump PR. Use the existing Dependabot workflow for routine updates; create additional maintenance only for a concrete advisory, reproducible bug or supported-runtime compatibility requirement. This work has no P8 predecessor and blocks no safety phase or native release.

## Evidence

At pinned main `eed0a969b097142042dc4412424fbc71a04d2c0d`, `.github/dependabot.yml:3–10` already schedules weekly npm updates grouped for development dependencies; lines 12–15 schedule monthly GitHub Actions updates. `.github/workflows/security.yml` already runs the moderate-level npm audit weekly and on PRs, alongside the required PR Gitleaks check.

`package.json:18–21` permits `@vitejs/plugin-react` `^6.1.2` and `vitest` `^5.0.5`; `package-lock.json:666–667,1717–1718` locks 6.1.2 and 5.0.5. The earlier audit's newer-version observation is historical and does not establish a defect or a present upgrade target. No registry lookup is required to retire a version-chasing task.

Historical receipt: the prior audit reported Node 24.22.1 install, 33 web tests, build and `npm audit --audit-level=moderate` passing with zero vulnerabilities. Those checks were not rerun for this revision and are not a current security or future-PR acceptance claim.

## Triggered maintenance

For an existing Dependabot PR, assess its current diff and required checks normally. For an additional update, identify the actual affected dependency/resolution, advisory or reproduced failure, and the smallest compatible fix before changing the lockfile. Refresh source/official package evidence at that time; do not retain old target versions as instructions or pursue “latest” without a concrete need.

Use the repository's current `.nvmrc` and engine policy. Run the existing required `npm ci`, `npm test`, `npm run build` and `npm audit --audit-level=moderate` checks plus required CI; inspect generated lockfile changes. A new test is warranted only for an actual regression, not to assert a version number. No dependency-specific harness, mandatory duplicate before/after suite, native launch or new browser matrix is created by this record.

Do not use blanket `npm update`, `npm audit fix --force`, peer-resolution bypasses or unrelated framework/runtime upgrades. Do not change Dependabot schedules or weaken existing gates. A source/config migration must be scoped to its actual compatibility problem; merge, push/preview and deployment retain the project's existing authority rules.

## Consequences

No package change, network lookup, test execution or PR is part of this planning pass. Routine maintenance continues through existing automation; the active safety sequence in [00_TECH_DEBT.md](00_TECH_DEBT.md) has no dependency on this record.

## Review of the YAGNI revision

On November 2, 2026, two independent subagents performed targeted safety and YAGNI verification of all seven revised documents against the accepted scope and source snapshot `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both returned **NO FINDINGS**. This follows the earlier five-angle review that recommended narrowing; it is not a new broad audit.

The verification confirmed that routine maintenance uses existing Dependabot and concrete advisory, bug or compatibility triggers, with no native phase dependency or dedicated upgrade project.

This verdict concerns the revised documents. Implementation, authorization feasibility, native acceptance and release remain unverified; the unchecked implementation gates remain open. No application tests, native actions or network operations were performed by these two reviewers.
