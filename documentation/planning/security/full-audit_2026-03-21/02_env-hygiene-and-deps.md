# Phase 02: Environment Hygiene & Dependency Updates

**PR title:** `chore: add .env to gitignore, update vite dependencies`
**Severity:** LOW
**Effort:** Trivial (< 15 min)
**Findings addressed:** #3 (.env not gitignored), #4 (outdated dev dependencies)

---

## Files Modified

- `.gitignore`
- `package.json`
- `package-lock.json` (auto-updated by npm)

---

## Dependencies

None — this phase can be implemented independently.

---

## Detailed Implementation Plan

### Finding #3: Add .env to .gitignore

**Problem:** The `.gitignore` does not include `.env` patterns. While no `.env` files exist today, there's no guardrail if someone creates one (e.g., for local Vercel dev, Apple notarization creds, etc.).

**Fix:** Add `.env` patterns to `.gitignore`:

```gitignore
# After existing entries, add:
.env
.env.*
!.env.example
```

The `!.env.example` exception allows committing a template file if needed in the future.

### Finding #4: Update dev dependencies

**Problem:** Both vite and @vitejs/plugin-react are 2 major versions behind:
- `vite`: 6.4.1 -> 8.0.1
- `@vitejs/plugin-react`: 4.7.0 -> 6.0.1

No known CVEs, but staying current with dev tooling reduces exposure window for future vulnerabilities.

**Fix:**

```bash
npm install --save-dev vite@latest @vitejs/plugin-react@latest
```

After updating:
1. Run `npm run build` to verify the landing page still builds
2. Run `npm run dev` and visually verify the landing page renders correctly
3. Check for any breaking changes in the Vite 7/8 and plugin-react 5/6 changelogs (primarily ESM/config changes)

**Note:** Major version bumps may require config changes in `vite.config.js`. The current config is minimal (just the react plugin and `base: '/'`), so breakage is unlikely but should be verified.

---

## Verification Checklist

- [ ] Verify `.env` is in `.gitignore`: `echo "TEST=1" > .env && git status` should NOT show `.env` as untracked, then `rm .env`
- [ ] `npm run build` succeeds
- [ ] `npm run dev` — landing page renders correctly (mockup interactive, fonts load, pink accent visible)
- [ ] `npm audit` still reports 0 vulnerabilities after update

---

## What NOT To Do

- **Don't pin exact versions** in package.json — the caret ranges (`^`) are appropriate for a landing page with no downstream consumers.
- **Don't update React** in this PR — React 19 is current and unrelated to the security findings. Keep this PR scoped.
- **Don't remove `package-lock.json`** and regenerate — this risks changing transitive dependency versions unnecessarily. Let `npm install` update it incrementally.
