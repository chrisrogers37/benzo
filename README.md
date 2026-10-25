# Benzo

**The anti-[Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12) for macOS.** Force true deep sleep — even with your dock plugged in.

Benzo sets `hibernatemode 25` and kills Power Nap, TCP keep-alive, proximity wake, and network wake. Your Mac writes RAM to disk, powers off completely, and USB ports go dark. No fan, no heat, no battery drain.

## Install

**Download** the latest `.dmg` from [Releases](https://github.com/chrisrogers37/benzo/releases).

Since Benzo isn't notarized yet, macOS will block it on first launch. Either:
- Right-click the app → **Open**
- Or run: `xattr -d com.apple.quarantine /Applications/Benzo.app`

**Homebrew** (personal tap):
```
brew tap chrisrogers37/benzo
brew install --cask benzo
```

## What it does

Benzo lives in your menubar. Toggle it on and it applies six `pmset` commands that Apple should have put in System Settings years ago:

```
sudo pmset -a hibernatemode 25
sudo pmset -a powernap 0
sudo pmset -a standby 0
sudo pmset -a autopoweroff 0
sudo pmset -a tcpkeepalive 0
sudo pmset -a proximitywake 0
```

Toggle it off (or quit) and your original settings are restored.

### Features

- **True hibernation** — `hibernatemode 25` writes RAM to disk and fully powers off
- **Dock-friendly** — CalDigit, OWC, Anker — leave it all plugged in
- **Granular control** — pick exactly which protections you want
- **One-click revert** — original pmset values backed up and restored on deactivate or quit
- **Sleep Now** — apply settings and sleep immediately
- **Diagnostics** — Option-click the menubar icon to see sleep sessions, wake reasons, USB devices, and settings verification

## Requirements

- macOS Ventura (13.0) or later
- Intel or Apple Silicon
- Admin privileges (one-time setup installs a sudoers rule for passwordless `pmset`)

## Build from source

Native builds require macOS and full Xcode; Command Line Tools alone cannot build
the project or its XCTest bundle. These commands compile the app without launching
it, then run the unhosted core tests with injected fakes:

```sh
export BENZO_TEST_DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/benzo-derived.XXXXXX")"
xcodebuild -version
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Release -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Benzo/Benzo.xcodeproj -scheme BenzoCoreTests -destination 'platform=macOS' -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO test
```

`BenzoCoreTests` does not host or launch the app. Its source list excludes the live
command, diagnostic and login adapters. Tests use in-memory preferences, fake
commands and clocks, and task-owned temporary backup files. Do not run the
production app or privileged/lifecycle acceptance on an always-on fleet host.
Physical sleep, permissions and recovery acceptance require a separately approved
test Mac; a successful build or fake-based test does not prove those outcomes.

## Landing page

[benzo-gules.vercel.app](https://benzo-gules.vercel.app) — built with React/Vite, includes an interactive mockup of the app.

Use Node 24 LTS (24.15.0 or newer in the 24.x line); `.nvmrc` pins the version used
in CI. With nvm installed, run `nvm install` and `nvm use` first.

```sh
npm ci
npm test
npm run build
npm audit --audit-level=moderate
npm run dev
```

`npm test` runs Vitest, React Testing Library and jsdom interaction tests. The
marketing wrapper owns shared demo state; `src/components/BenzoMockup.jsx` renders
the mockup using `src/demo/state.js` and `src/demo/fixtures.js`. Native UI changes
must preserve matching demo behavior.

The `build` workflow runs web tests/build and full-Xcode Debug/Release/core tests.
The separate `security` workflow retains npm audit and Gitleaks. Neither workflow
publishes artifacts. The connected Vercel Git integration can deploy previews on
branch pushes and the site on main; inspect and authorize deployment before push.

The approved delivery order and outstanding acceptance are recorded in
[the re-orientation plan](documentation/plans/benzo-reorientation_2026-10-25/00_overview.md)
and [run log](documentation/plans/benzo-reorientation_2026-10-25/RUN_LOG.md).

## License

MIT
