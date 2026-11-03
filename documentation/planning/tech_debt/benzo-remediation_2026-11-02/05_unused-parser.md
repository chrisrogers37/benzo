---
title: "[tech-debt] Retire the standalone unused-parser cleanup"
type: decision
status: ratified
owner: claudna:audit
created: 2026-11-02
tags: [tech-debt, "priority:low"]
repos: chrisrogers37/benzo
---

## Decision

The accepted 2026-11-02 YAGNI rescope retires F6 as a standalone phase/PR. An unused private helper does not justify its own planning, validation or release sequence. No active phase, native release or P8 milestone depends on this cleanup.

## Evidence

At pinned main `eed0a969b097142042dc4412424fbc71a04d2c0d`, `Benzo/Benzo/Services/DiagnosticService.swift:176–183` defines private `extractAssertionName(from:)`. A source-wide search finds its declaration and two historical documentation mentions, with zero callers; `fetchSleepBlockers()` instead uses `extractProcessName(from:)` at lines 103 and 168. This observation must be refreshed before any later deletion.

## Adjacent maintenance only

If an already-justified change touches `DiagnosticService.swift`, its owner may run a fresh repository-wide `rg -n --hidden -g '!.git/**' -g '!node_modules/**' -g '!dist/**' 'extractAssertionName' .` and classify all matches. With zero callers, deletion of only this helper and its attached comment is optional adjacent cleanup; no imports or neighboring parser behavior change. If a caller exists, reachability is uncertain, or the helper is already gone, leave it alone and close the unused-helper observation without a new PR.

Reuse the containing change's required checks and review. Add no deletion-specific test, compiler/browser sweep, harness or standalone acceptance project. Preserve intentional historical web source/tests; unbundled does not mean unused. Existing diagnostic correctness belongs to [04_diagnostics.md](04_diagnostics.md), not this record.

## Consequences

No source change or test execution is authorized or claimed by this planning record. The small possible deletion remains available when adjacent work makes it worthwhile; no ongoing backlog gate or P8 wait is created. See [00_TECH_DEBT.md](00_TECH_DEBT.md) for the active execution order.

## Review of the YAGNI revision

On November 2, 2026, two independent subagents performed targeted safety and YAGNI verification of all seven revised documents against the accepted scope and source snapshot `eed0a969b097142042dc4412424fbc71a04d2c0d`. Both returned **NO FINDINGS**. This follows the earlier five-angle review that recommended narrowing; it is not a new broad audit.

The verification confirmed that this is a no-standalone-PR decision. Optional adjacent deletion still requires a fresh caller search and proportionate checks.

This verdict concerns the revised documents. Implementation, authorization feasibility, native acceptance and release remain unverified; the unchecked implementation gates remain open. No application tests, native actions or network operations were performed by these two reviewers.
