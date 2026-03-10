# Benzo

macOS menubar app that forces true hibernation (hibernatemode 25). Landing page built with React/Vite, deployed on Vercel.

**Version**: 0.2.0

## Build

- **App**: `xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug build`
- **Landing page**: `npm run dev` (Vite)
- **Release DMG**: `./scripts/build-dmg.sh` (requires `APPLE_ID`, `APPLE_TEAM_ID`, `APP_PASSWORD` env vars for notarization; builds without them but DMG won't be notarized)
- Deploys landing page automatically via Vercel on push to `main`

## Architecture

- `Benzo/Benzo/` — Swift macOS menubar app
  - `App/BenzoApp.swift` — SwiftUI entry point, creates AppDelegate
  - `App/AppDelegate.swift` — NSStatusItem, popover management, ⌥-click detection for diagnostics, dynamic icon rendering (pink when active)
  - `Models/SleepSetting.swift` — enum of all pmset settings with keys, labels, defaults
  - `Models/PMSetState.swift` — parses `pmset -g` output into key-value pairs
  - `Models/OriginalSettingsBackup.swift` — Codable struct for persisted backup
  - `Models/SleepSession.swift` — sleep/wake event with duration, battery delta, wake reason
  - `Models/USBDevice.swift` — USB device name and power draw
  - `Services/PMSetService.swift` — runs pmset commands via ShellExecutor
  - `Services/ShellExecutor.swift` — sudo via sudoers rule (post-setup) or osascript (first run)
  - `Services/BackupService.swift` — save/load original pmset values to `~/Library/Application Support/Benzo/`
  - `Services/DiagnosticService.swift` — parses pmset logs, system_profiler, verifies settings
  - `ViewModels/BenzoViewModel.swift` — all state management: activate/deactivate, sleepNow, quit (restores defaults), diagnostics loading
  - `Views/PopoverContentView.swift` — main layout, switches between setup/normal/diagnostic views
  - `Views/MasterToggleView.swift` — "Deep Sleep is On/Off" header with toggle
  - `Views/SleepNowButton.swift` — pink capsule button, activates settings then sleeps
  - `Views/SettingRowView.swift` — individual setting checkbox row
  - `Views/FooterView.swift` — launch at login, version, restore defaults, quit
  - `Views/SetupView.swift` — first-run permission grant screen
  - `Views/DiagnosticView.swift` — ⌥-click view: sleep sessions, wake reason, USB devices, settings verification
  - `Theme/BenzoTheme.swift` — colors (accent: #d4749c)
- `src/BenzoHybrid.jsx` — landing page with interactive mockup, diagnostics panel (Alt+click), and Gatekeeper info tray
  - **IMPORTANT**: Any UI or behavioral change to the native app must also be reflected in the landing page mockup. They must stay in sync.
- `scripts/build-dmg.sh` — archive, sign, notarize, and package as DMG for distribution
- `Casks/benzo.rb` — Homebrew cask formula (`brew install --cask benzo`)

## Quit behavior

Quitting Benzo while active restores all original pmset settings from backup before terminating. Users won't be left with modified system settings after closing the app.

## Adding new files to Xcode project

New `.swift` files must be registered in `Benzo/Benzo.xcodeproj/project.pbxproj` in 4 places:
1. `PBXBuildFile` section — build file entry
2. `PBXFileReference` section — file reference entry
3. `PBXGroup` section — add to the appropriate group (Views, Models, etc.)
4. `PBXSourcesBuildPhase` section — add to Sources files list

## pmset learnings

- `womp` = Wake-on-LAN (network wake), NOT physical USB device wake. Labeled "Disable Network Wake" in the app.
- There is no pmset key to disable physical USB wake during normal sleep. Protection comes from hibernatemode 25 cutting power to USB ports after hibernation completes.
- Between `pmset sleepnow` and full hibernation, there's a brief window where the Mac is in normal sleep and USB devices could still wake it.
- The sudoers rule (`/etc/sudoers.d/benzo`) grants passwordless access to all `pmset` subcommands including `sleepnow`.

## Distribution

Not on the Mac App Store — Benzo requires root access for pmset, which is incompatible with App Store sandboxing. Distributed via:
- **GitHub Releases** — signed `.dmg` (notarized when Apple Developer credentials are available)
- **Homebrew** — `brew install --cask benzo` (requires notarized DMG for official homebrew-cask tap; works as personal tap without)
- Users without notarized builds: right-click → Open, or `xattr -d com.apple.quarantine /Applications/Benzo.app`
