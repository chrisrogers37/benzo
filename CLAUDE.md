# Benzo

macOS menubar app that forces true hibernation (hibernatemode 25). Landing page built with React/Vite, deployed on Vercel.

## Build

- **App**: `xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug build`
- **Landing page**: `npm run dev` (Vite)
- Deploys automatically via Vercel on push to `main`

## Architecture

- `Benzo/Benzo/` — Swift macOS menubar app
  - `Models/SleepSetting.swift` — enum of all pmset settings with keys, labels, defaults
  - `Services/PMSetService.swift` — runs pmset commands via ShellExecutor
  - `Services/ShellExecutor.swift` — sudo via sudoers rule (post-setup) or osascript (first run)
  - `ViewModels/BenzoViewModel.swift` — all state management, activate/deactivate/sleepNow
  - `Views/` — SwiftUI views (PopoverContentView is the main layout)
  - `Theme/BenzoTheme.swift` — colors (accent: #d4749c)
- `src/BenzoHybrid.jsx` — landing page with interactive mockup
  - **IMPORTANT**: Any UI or behavioral change to the native app must also be reflected in the landing page mockup. They must stay in sync.

## Adding new files to Xcode project

New `.swift` files must be registered in `Benzo/Benzo.xcodeproj/project.pbxproj` in 3 places:
1. `PBXBuildFile` section — build file entry
2. `PBXFileReference` section — file reference entry
3. `PBXGroup` section — add to the appropriate group (Views, Models, etc.)
4. `PBXSourcesBuildPhase` section — add to Sources files list

## pmset learnings

- `womp` = Wake-on-LAN (network wake), NOT physical USB device wake. Labeled "Disable Network Wake" in the app.
- There is no pmset key to disable physical USB wake during normal sleep. Protection comes from hibernatemode 25 cutting power to USB ports after hibernation completes.
- Between `pmset sleepnow` and full hibernation, there's a brief window where the Mac is in normal sleep and USB devices could still wake it.
- The sudoers rule (`/etc/sudoers.d/benzo`) grants passwordless access to all `pmset` subcommands including `sleepnow`.
