# Benzo — Product Requirements Document

**Version:** 0.1.0 (Draft)
**Author:** Chris
**Date:** March 5, 2026
**Status:** Pre-development

---

## Overview

Benzo is a free, open-source macOS menubar utility that forces true deep sleep (hibernation) on MacBooks — even when USB-C docks, hubs, and peripherals are connected. It is a GUI wrapper around Apple's `pmset` command-line tool, solving a long-standing pain point that Apple has never addressed with a native toggle.

**Tagline:** The anti-Amphetamine for macOS.

**Positioning:** Amphetamine and Caffeine keep your Mac awake. Benzo puts it to sleep properly. Where those tools prevent sleep, Benzo enforces it — cutting USB power, disabling wake triggers, and switching to full hibernation so your battery stays exactly where you left it.

---

## Problem Statement

macOS keeps USB-C ports powered during sleep (hibernatemode 3), which causes significant battery drain when laptops are left connected to docks, hubs, monitors, or adapters. This is a widespread, well-documented problem across both Intel and Apple Silicon MacBooks:

- Intel MacBook Pro (2019/2020) users report warm laptops and drained batteries overnight when docked.
- M1 MacBook owners report 50%+ battery drain over 10 hours with a Satechi dock connected, vs. 0% drain with nothing connected.
- M2 MacBook Air owners report USB-C ports continue providing power during sleep, draining the battery through connected adapters.
- Even a bare USB-C to Ethernet adapter (no cable attached) drains ~1% per hour on M1.
- The problem spans dock brands: CalDigit, OWC, Anker, Satechi, Plugable, and generic USB-C hubs all exhibit the same behavior.

The only existing solutions are:

1. Physically unplugging the dock before sleep (defeats the purpose of a desk setup).
2. Running `pmset` commands in Terminal (inaccessible to most users).
3. No third-party GUI app currently addresses this specific problem.

Apple has not added a native toggle for USB power management during sleep in any version of macOS, on either Intel or Apple Silicon.

---

## Solution

Benzo provides a single menubar toggle that switches the Mac into true hibernation mode and disables all unnecessary wake triggers. Under the hood, it runs six `pmset` commands:

```
sudo pmset -a hibernatemode 25
sudo pmset -a powernap 0
sudo pmset -a standby 0
sudo pmset -a autopoweroff 0
sudo pmset -a tcpkeepalive 0
sudo pmset -a proximitywake 0
```

**What these do:**

| Command | Effect | Trade-off |
|---|---|---|
| `hibernatemode 25` | Writes RAM to disk, fully powers off (including USB ports) | Wake takes ~10-30 seconds instead of instant |
| `powernap 0` | Disables background email, Time Machine, iCloud sync during sleep | No background syncing while asleep |
| `standby 0` | Disables timed transition to standby | None meaningful |
| `autopoweroff 0` | Disables auto power-off timer | None meaningful |
| `tcpkeepalive 0` | Disables network wake / TCP connections during sleep | Find My Mac cannot locate the device while asleep |
| `proximitywake 0` | Disables wake from iPhone/Apple Watch proximity | Handoff and AirDrop proximity features won't wake the machine |

All changes are fully reversible. Benzo saves the user's original `pmset` values on first activation so they can be restored with one click.

---

## Target Users

**Primary:** MacBook owners who use USB-C docks or hubs as part of a desktop setup and experience battery drain during sleep. This includes both Intel (2015–2020) and Apple Silicon (M1–M4) users.

**Secondary:** Power users and developers who are aware of the `pmset` problem but want a cleaner solution than shell scripts or manual Terminal commands.

**Persona:** Someone with a CalDigit/OWC dock on their desk, an external monitor, keyboard, and mouse all connected via USB-C. They close the lid at the end of the day expecting their MacBook to sleep. Instead, it drains 30-50% overnight and is warm to the touch the next morning.

---

## Platform & Compatibility

- **macOS versions:** Catalina (10.15) and later
- **Hardware:** Intel MacBook Pro/Air (2015–2020), Apple Silicon MacBook Pro/Air (M1, M2, M3, M4)
- **Privileges:** Requires admin/sudo access for `pmset` commands
- **Distribution:** Direct download (.dmg), GitHub releases, Homebrew cask (no App Store — sandboxing restrictions would prevent `pmset` access)

---

## Feature Specification

### F1: Master Toggle — Deep Sleep Mode

The primary interaction. A single on/off toggle in the menubar dropdown that activates all default protections.

**Default-on protections when toggled:**
- Hibernate Mode 25 (always on by default)
- Disable Power Nap (on by default)
- Disable Proximity Wake (on by default)
- Disable USB Wake (on by default)

**Default-off protections (opt-in):**
- Disable TCP Keep-Alive (off by default because it disables Find My)

**Behavior:**
- ON: Runs the selected `pmset` commands with sudo.
- OFF: Restores all values to the user's original `pmset` configuration (captured on first activation).

### F2: Granular Setting Overrides

Individual checkboxes for each `pmset` parameter, visible when the master toggle is ON. Each checkbox has a label and a short description explaining the trade-off.

Users can customize which protections they want. For example: enable everything except TCP Keep-Alive to maintain Find My Mac functionality.

### F3: Original Settings Backup & Restore

On first activation, Benzo captures the current output of `pmset -g` and stores it locally. The "Revert to Defaults" action restores these exact values.

**Storage:** `~/Library/Application Support/Benzo/original-pmset.json`

**Backup should capture at minimum:**
- hibernatemode
- powernap
- standby
- autopoweroff
- tcpkeepalive
- proximitywake

### F4: Menubar Icon & Status Indicator

A persistent menubar icon (pill emoji 💊 or custom icon) with a small status dot:

- **Pink dot / glow:** Benzo is active, deep sleep protections engaged.
- **Gray dot:** Benzo is inactive, macOS defaults in effect.

### F5: Launch at Login

Option to start Benzo automatically at login so protections are always active without user intervention.

### F6: Current Status Display

The dropdown should show the current state of each `pmset` value so the user can verify their settings are applied. This builds trust and transparency.

---

## Features Explicitly Out of Scope (v0.1)

- Scheduling (e.g., "activate Benzo after 6pm")
- Dock/device detection triggers (e.g., "activate when CalDigit is connected")
- Battery health monitoring
- Sleep/wake logging or analytics
- iOS companion app
- App Store distribution
- Automatic updates (can add in v0.2 via Sparkle framework)

---

## Technical Architecture

### Language & Framework

- **Swift** with **SwiftUI** for the menubar popover UI
- **NSStatusItem** for menubar presence
- **SMAppService** for launch-at-login (macOS 13+) or legacy `LSSharedFileList` for older versions
- **Process** (Foundation) to execute `pmset` commands via shell

### Key Technical Considerations

**sudo access:** `pmset` requires root privileges. Options:

1. Use `osascript -e 'do shell script "pmset ..." with administrator privileges'` — triggers a native macOS password prompt. Simplest approach for v0.1.
2. Install a privileged helper tool via `SMJobBless` — more seamless but significantly more complex. Consider for v0.2.

**Reading current state:** Parse `pmset -g` output to determine current values and display accurate toggle states on app launch.

**Persistence:** Store user preferences (which protections are enabled) and original pmset backup in `~/Library/Application Support/Benzo/`.

**macOS version differences:** `pmset` parameters and behavior differ slightly between Intel and Apple Silicon. The app should detect the chip architecture and adjust any parameter defaults or warnings accordingly. Specifically:
- `hibernatemode 25` behaves slightly differently on Apple Silicon (which manages power more aggressively by default).
- Some parameters may not be available or may have different effects on different macOS versions.
- The app should gracefully handle `pmset` returning unexpected values or errors.

**Error handling:** If a `pmset` command fails (e.g., permission denied, unsupported parameter), the app should surface a clear error rather than silently failing.

---

## UI/UX Design

### Visual Direction: Clinical + Sedation

The design language is "pharmaceutical clinical" — clean white/light gray surfaces, uppercase spaced lettering for the wordmark, minimal UI — with a pink/rose "sedation" effect that activates when Benzo is enabled.

**Inactive state:** Pure black and white. Sterile and clean.

**Active state:** Pink (#d4749c) bleeds into interactive elements:
- Toggle switches turn pink with a soft glow (box-shadow)
- Checkboxes turn pink with a subtle glow
- Status dot glows pink
- The dropdown shadow picks up a faint pink cast
- Hover states on settings rows tint pink

This creates the metaphor of sedation kicking in — the clinical environment gets a warm, drowsy haze when Benzo is active.

### Color Palette

| Token | Value | Usage |
|---|---|---|
| Background | #f6f5f3 | Landing page / app background |
| Surface | #ffffff | Cards, dropdowns, inputs |
| Text | #1a1a1a | Primary text |
| Text Muted | #999999 | Secondary text |
| Text Faint | #cccccc | Tertiary text, labels |
| Accent (active) | #d4749c | Toggles, checkboxes, glows, CTA |
| Accent soft | rgba(212,116,156,0.08) | Hover backgrounds, pills |
| Accent glow | 0 0 20px rgba(212,116,156,0.2) | Active toggle/checkbox shadow |
| Accent (inactive) | #1a1a1a | Download button, icon when off |
| Border | rgba(0,0,0,0.06) | Card and dropdown borders |

### Typography

- **Wordmark:** Uppercase, letter-spacing 0.08em, weight 600
- **Headings:** Weight 300 (light), tight letter-spacing
- **Body:** Weight 400, color #999
- **Monospace (code):** IBM Plex Mono or SF Mono
- **Font stack:** Instrument Sans → SF Pro Display → system

### Menubar Dropdown Layout

```
┌──────────────────────────────────┐
│  Deep Sleep Mode          [TOGGLE] │
│  4 protections active              │
├──────────────────────────────────┤
│  ✓  Hibernate Mode                 │
│     Full power-off, USB disabled   │
│                                    │
│  ✓  Disable Power Nap             │
│     No background syncing          │
│                                    │
│  ☐  Disable TCP Keep-Alive        │
│     No network wake — no Find My   │
│                                    │
│  ✓  Disable Proximity Wake        │
│     iPhone/Watch won't wake Mac    │
│                                    │
│  ✓  Disable USB Wake              │
│     Only power button wakes Mac    │
├──────────────────────────────────┤
│  v0.1.0    Revert to Defaults Quit │
└──────────────────────────────────┘
```

---

## Distribution Strategy

### Primary: GitHub + Direct Download

- GitHub repository with comprehensive README (the landing page copy serves as the basis)
- GitHub Releases with signed `.dmg` files
- Clear installation instructions

### Secondary: Homebrew

```
brew install --cask benzo
```

Submit a Homebrew cask formula once the app is stable.

### Landing Page

A single-page site (hosted on GitHub Pages, Vercel, or Netlify) at a domain TBD (e.g., `getbenzo.app`, `benzo.dev`). The React mockup from the design phase serves as the foundation. Key sections:

1. Hero with tagline ("The anti-Amphetamine for macOS")
2. Interactive menubar mockup showing the UI
3. Feature grid (6 cards)
4. "Under the hood" code block showing the pmset commands
5. Compatibility info
6. Download CTA + GitHub link

### Pricing

Free. MIT license. Optional tip jar / sponsor link.

---

## Marketing & Discovery

The name "Benzo" and the "anti-Amphetamine" positioning are the primary marketing hooks. Expected organic discovery channels:

1. **Hacker News** — "Show HN: Benzo – the anti-Amphetamine for macOS" (the technical transparency + irreverent name is HN catnip)
2. **Reddit** — r/mac, r/macapps, r/macbookpro (these communities are full of dock battery drain complaints)
3. **Mac utility roundup blogs** — The name makes it inherently shareable in "best Mac utilities" listicles
4. **Apple Support Community threads** — Dozens of active threads about dock sleep drain with no good solution. Benzo can be linked as an answer.
5. **Twitter/X and Mastodon** — The interactive sedation UI effect is screenshot-worthy

### App Store Considerations

Benzo will NOT be distributed via the Mac App Store because:

1. App Store sandboxing would prevent execution of `pmset` commands requiring sudo.
2. Apple has previously removed apps for drug-related naming (Amphetamine was temporarily pulled in 2020). Without an established user base, fighting a removal would be difficult.
3. Direct distribution gives full control over the update cycle and user relationship.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `pmset` behavior changes in a future macOS update | Medium | High | Pin to known-good macOS versions, test on betas, document compatibility |
| Apple adds a native USB power toggle, eliminating the need | Low | High | Would be a win for users; Benzo can sunset gracefully |
| `hibernatemode 25` causes issues on specific hardware | Low | Medium | Thorough testing on Intel and Apple Silicon; clear compatibility docs; "Revert to Defaults" as safety net |
| Users forget Benzo is active and are confused by slower wake times | Medium | Low | Clear status indicator in menubar; first-run explanation of what hibernatemode 25 means |
| sudo password prompts are annoying | Medium | Medium | v0.1 uses osascript prompt; v0.2 can explore privileged helper via SMJobBless |

---

## Success Metrics

For a free utility, success is measured by adoption and community reception:

- GitHub stars (target: 500+ in first 3 months)
- Homebrew install count
- Mentions in Mac utility roundup articles
- Reduction in personal MacBook battery degradation (the original motivation)

---

## Development Roadmap

### Phase 1 — MVP (v0.1.0)

Build the core menubar app for personal use.

- Master toggle (Deep Sleep Mode on/off)
- Individual setting checkboxes with descriptions
- Original pmset backup and restore
- Menubar icon with active/inactive status indicator
- Launch at login option
- Tested on Intel MacBook Pro (2019/2020)

### Phase 2 — Public Release (v0.2.0)

Prepare for community distribution.

- Tested on Apple Silicon (M1–M4)
- Signed and notarized .dmg for Gatekeeper
- GitHub repo with README, LICENSE (MIT), and releases
- Homebrew cask formula
- Landing page deployed
- Sparkle framework for auto-updates

### Phase 3 — Polish (v0.3.0+)

Based on community feedback.

- Privileged helper tool (SMJobBless) to eliminate repeated sudo prompts
- Dock/hub detection triggers (auto-activate when a specific USB device is connected)
- Schedule-based activation (e.g., "enable after 6pm on weekdays")
- Sleep/wake event logging (show what woke your Mac and when)
- Localization if demand warrants

---

## References

- `pmset` man page: https://ss64.com/mac/pmset.html
- macOS hibernatemode values: mode 3 (default laptop, RAM + disk), mode 25 (full hibernate, disk only)
- Amphetamine (anti-pattern reference): https://apps.apple.com/us/app/amphetamine/id937984704
- Sleep Aid (prior art for sleep diagnostics): https://ohanaware.com/sleepaid/
- Apple Support threads documenting the USB sleep drain problem across M1/M2/Intel

---

## Appendix: Name Selection

The name "Benzo" was selected after extensive collision-checking against existing Mac software, App Store listings, and related products. The following names were evaluated and rejected:

- **Melatonin** — Existing Mac sleep utility + popular Steam game
- **Yawn** — Existing App Store sleep sounds app
- **Drift** — Major B2B SaaS platform with Mac desktop app
- **Lullaby** — Existing Mac App Store shutdown timer
- **Pillow** — Major sleep tracker app (NYT, Forbes, WaPo coverage)
- **Tuck/Tucked** — Existing Mac window management utility
- **Nightcap** — Existing iOS photography app
- **Decaf** — Existing Mac sleep control app (nearly identical product)
- **Aurora** — Crowded namespace (alarm clock, HDR editor, IDE, VPN, media player)
- **Hibernate** — Existing Mac hibernation utility
- **Drowsy** — Clean and available, but lacked personality
- **Briar** — Unique Sleeping Beauty reference, but didn't communicate function

"Benzo" was chosen for: zero product collisions, instant recognition as the pharmacological inverse of Amphetamine, memorability, shareability, and personality. Distribution will be direct (not App Store) to avoid potential drug-name policy conflicts.
