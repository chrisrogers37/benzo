# Roadmap: Benzo as a Revenue-Generating Download

Companion to [`01_issue-tracker.md`](01_issue-tracker.md). Milestones are ordered by
dependency, not calendar time. Each milestone has a hard exit criterion — do not start
charging money before Milestone 3's criteria are met.

## Where we are

A real `Benzo-0.3.0.dmg` exists on GitHub Releases with a working direct-install cask.
But it's unsigned (Gatekeeper friction on every install), the "we always restore your
settings" promise has known holes, there are zero tests and no release automation, and
nothing collects a cent. The product concept is sound and differentiated ("the
anti-Amphetamine" — force true hibernation), the niche is real (dock-plugged MacBook
users with battery drain / hot-bag problems), and the pmset pain point is unaddressed
by Apple. What stands between here and revenue is trust: an app that asks for root and
changes firmware-adjacent sleep settings must be visibly safe.

## Milestone 1 — Make the safety promise true

**Goal:** under no realistic termination or failure path does Benzo leave the user's
pmset settings modified without telling them.

Issues, roughly in order:
1. **BZ-002** — robust `pmset -g` parsing + validate backup at save time (foundation
   for everything else; corrupt backups poison all restore paths)
2. **BZ-020** — unit-test target with parser fixtures (lands with BZ-002)
3. **BZ-001** — restore on all termination paths (`applicationShouldTerminate`,
   power-off notification, launch-time reconciliation)
4. **BZ-004** — quit surfaces restore failures instead of `try?`
5. **BZ-003** — deactivate refuses to lie when backup is missing; explicit
   "restore macOS defaults" fallback
6. **BZ-005** — rollback on partial apply
7. **BZ-009 / BZ-014 / BZ-016 / BZ-010 / BZ-013** — state reconciliation at launch,
   fresh backup per activation, timer cancellation, toggle revert, no empty activation
8. **BZ-011** — shell calls off the main thread (safety fixes touch these paths anyway)

**Exit criterion:** a written kill-matrix test (Cmd+Q, Force Quit, `kill -9`, logout,
restart, crash-simulated) where every row ends with either restored settings or an
explicit user-facing warning at next launch. Parser fixtures pass for Intel + Apple
Silicon `pmset` output.

## Milestone 2 — Frictionless, trustworthy install

**Goal:** download → open → works. No right-click-Open ritual, no xattr commands.

1. **Buy the Apple Developer Program membership ($99/yr)** — this is the one hard
   external dependency for revenue. Everything about "unidentified developer" friction
   and half the Gatekeeper tray on the landing page disappears with it.
2. **BZ-007** — hardened runtime + entitlements
3. **BZ-006** — fix `build-dmg.sh` signing/notarization path (staple, verify, zip
   submit, SHA256SUMS, Applications-symlink DMG layout)
4. **BZ-019** — CI compiles Swift + landing page on every PR
5. **BZ-018** — release automation: tag → macOS runner → signed+notarized DMG →
   GitHub release → cask sha256 bump
6. **BZ-017** — create the `homebrew-benzo` tap repo (or fix README)
7. **BZ-015 / BZ-012 / BZ-022** — setup-flow correctness (admin check, no surprise
   privilege prompts, multi-user disclosure) — first-run experience is the trust moment
8. **BZ-054(c)** — retire "isn't notarized" copy from README/landing/Gatekeeper tray

**Exit criterion:** a fresh Mac (or clean VM/macOS user) can download the DMG from the
landing page, drag to Applications, open with zero Gatekeeper dialogs, complete setup,
and toggle deep sleep. Release is produced entirely by CI from a git tag.

## Milestone 3 — Monetization layer

**Goal:** a payment path exists and the license question is settled (**BZ-008** is the
gate).

### Recommended model: paid app with free trial, sold via the landing page

For a single-purpose menubar utility in this niche, the proven pattern is a **one-time
purchase in the $10–20 range with a 7–14 day full-featured trial** (the AlDente /
Bartender / Ice-adjacent market). Subscriptions are hostile for a utility this small;
donations underprice it.

- **Payments/licensing:** use a merchant-of-record so there is no tax/VAT handling:
  **Paddle** or **Lemon Squeezy** (both have license-key APIs and are standard for
  indie Mac apps). Stripe Payment Links work but leave tax compliance to you.
- **License enforcement:** offline-verifiable signed license keys (Ed25519 signature
  over email+order-id, public key embedded in app). No account system, no server
  beyond the MoR's API. Trial state in Application Support (accept that determined
  users can reset it — enforcement effort beyond "honest people pay" is wasted here).
- **License decision (BZ-008):** two coherent options —
  - **Open-core / source-available:** keep the repo public (it is already, and it's
    good marketing + trust for an app requesting root), commit the MIT license for the
    core, and make the *convenience* paid: signed+notarized builds, auto-updates,
    support. Free riders who build from source were never customers.
  - **Relicense to source-available-non-commercial or close the repo** before adding
    the payment code. Cleaner paywall, but loses the trust/audit story that genuinely
    matters for a sudo-wielding utility.
  - **Recommendation:** open-core. The moat is polish + trust + zero-friction builds,
    not secret code. Keep the license-check module minimal so it isn't a maintenance
    tax on the open repo.
- **App Store:** not an option (root/pmset, sandbox-incompatible — already documented).
  SetApp is a plausible *additional* channel later; it requires notarization (done
  after Milestone 2) and their review.

### Product work in this milestone

1. Trial + license-key entry UI (Settings scene — repurposes BZ-048's empty window)
2. **BZ-036** — Sparkle auto-update fed by the release workflow (paid users must get
   fixes without visiting GitHub)
3. **BZ-035** — structured logging + opt-in crash reporting (support burden control)
4. **BZ-034** — clean uninstall flow (paid apps get held to a higher standard;
   "it left a sudoers file behind" is a refund/1-star trigger)
5. Landing page: pricing section, buy button (MoR checkout overlay), trial download
   CTA, **BZ-021** og-image, **BZ-040** SEO, **BZ-041** correct OS requirement,
   **BZ-039** accessibility
6. Privacy policy + terms page (required by MoRs; also the analytics disclosure)
7. Analytics: privacy-friendly page analytics (Plausible/Vercel Analytics) for
   download-conversion measurement — no telemetry in the app itself beyond opt-in
   crash reports (telemetry in a root-privileged utility would poison trust)

**Exit criterion:** a stranger can pay, receive a key by email, activate, and get an
auto-update. Refund path documented.

## Milestone 4 — Growth and durability (post-launch, ongoing)

- **Distribution:** submit the cask to the official `homebrew-cask` tap (now possible:
  notarized DMG), Product Hunt / Hacker News "Show HN" launch, target the specific
  search intents that already convert ("macbook drains battery in bag closed lid",
  "clamshell mode battery drain", "hibernatemode 25") with landing-page content
- **SetApp application** as a second revenue channel
- **Support surface:** GitHub issues template + a support email; diagnostics view
  already exists — add an "export diagnostics" button to make bug reports useful
- **Platform coverage (BZ-031):** explicit Apple Silicon vs Intel behavior matrix,
  tested per macOS release — this is where paid-user support tickets will come from
- **Codebase durability:** BZ-037 (view-model split + DI), BZ-038 (landing page
  decomposition), remaining P2/P3 debt burn-down
- **Feature ideas with willingness-to-pay** (only after the above): scheduled
  hibernation windows ("always hibernate between 11pm–7am"), low-battery auto-
  hibernate threshold, Shortcuts/CLI integration, per-power-source profiles

## Pricing sanity check

At $15 one-time via a MoR (~5% + fees), roughly ~$13.50 net per sale. Apple Developer
Program is $99/yr; landing page hosting is free-tier. Break-even is ~8 sales/year —
everything past that is margin. Comparable single-purpose Mac utilities (AlDente Pro
€27, Lungo/One Switch $5–10, Bartender $20) suggest $12–18 is defensible given Benzo
does something none of them do.

## What NOT to do

- Don't add features before Milestone 1 — every new code path multiplies the restore-
  lifecycle surface that is currently the product's biggest liability.
- Don't build accounts, servers, or subscription infrastructure — a signed license key
  and a merchant-of-record cover everything this product needs.
- Don't add in-app telemetry — a utility that asks for root and phones home is a
  Hacker-News-comment-section death sentence.
- Don't chase the Mac App Store — architecturally impossible and already documented.
