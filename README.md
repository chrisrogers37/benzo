# Benzo

**The anti-Amphetamine for macOS.** Force true deep sleep — even with your dock plugged in.

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

```
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Release build
```

## Landing page

[benzo-gules.vercel.app](https://benzo-gules.vercel.app) — built with React/Vite, includes an interactive mockup of the app.

```
npm install
npm run dev
```

## License

MIT
