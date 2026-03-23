# Security Audit — Benzo

**Audit date:** 2026-03-21
**Scope:** Full codebase — macOS menubar app (Swift), landing page (React/Vite), build scripts, Homebrew cask, CI/distribution config
**Version audited:** 0.2.1

---

## Findings

| # | Severity | Category | Finding | Location |
|---|----------|----------|---------|----------|
| 1 | MEDIUM | Command injection (defense-in-depth) | Backup values from JSON file interpolated into shell commands without validation | `PMSetService.swift:59-60`, `ShellExecutor.swift:38-51` |
| 2 | MEDIUM | Sudoers scope | NOPASSWD rule covers ALL pmset subcommands for ALL admin users | `ShellExecutor.swift:27` |
| 3 | LOW | Env hygiene | `.gitignore` missing `.env` entry — no protection against accidental secret commit | `.gitignore` |
| 4 | LOW | Dependency freshness | vite 6.4.1 -> 8.0.1, @vitejs/plugin-react 4.7.0 -> 6.0.1 (2 major versions behind, 0 CVEs) | `package.json` |

**Clean categories:** Secret detection, XSS, SQL injection, deserialization, auth/authz (N/A), transport security, exposed endpoints, npm audit (0 vulns)

---

## Remediation Priority

1. **Phase 01** — Input validation for shell commands + sudoers tightening (findings #1, #2) — MEDIUM
2. **Phase 02** — Env hygiene + dependency updates (findings #3, #4) — LOW

---

## Grouping Rationale

- **Phase 01**: Both findings relate to the privilege escalation surface — shell command construction and the sudoers rule that enables it. Fixing them together ensures the entire `pmset` execution path is hardened.
- **Phase 02**: Independent hygiene items that can ship as a single cleanup PR.

---

## Dependency Matrix

Phases are independent — no ordering dependency. Phase 01 is prioritized by severity.
