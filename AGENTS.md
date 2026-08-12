# AGENTS.md

Project-specific guidance for AI coding agents. See `CLAUDE.md` for the full
architecture overview, commands reference, and code conventions.

## Cursor Cloud specific instructions

Benzo has two parts:

- **Native macOS menubar app** (`Benzo/`, Swift/SwiftUI, built with `xcodebuild`).
  This **cannot be built or run in the Cursor Cloud Linux VM** — it requires macOS
  and Xcode. Treat Swift changes as review-only here; validate the mockup parity on
  the landing page instead (any native UI/behavior change must also be reflected in
  `src/BenzoHybrid.jsx`, per `CLAUDE.md`).
- **Landing page** (React 19 + Vite 6, repo root). This is the only runnable/testable
  product in the cloud VM.

Landing page notes:

- Standard commands live in `package.json`: `npm run dev` (Vite dev server, serves on
  `http://localhost:5173/`), `npm run build`, `npm run preview`. Node 20+ is required
  (Vite 6); the VM's Node 22 works.
- There is **no lint script and no automated test suite**. The CI check that gates PRs
  is `npm audit --audit-level=moderate` plus a gitleaks secret scan (see
  `.github/workflows/security.yml`). Run `npm audit --audit-level=moderate` locally to
  mirror the security gate.
- The dev server is a long-running process; start it in a background/tmux session, not
  a blocking foreground call.
