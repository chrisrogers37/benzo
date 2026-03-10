cask "benzo" do
  version "0.2.0"
  sha256 "7e2f533771c143e3f016a50369160b60f3633658ac783dce04998596ed9acb18"

  url "https://github.com/chrisrogers37/benzo/releases/download/v#{version}/Benzo-#{version}.dmg"
  name "Benzo"
  desc "Force true deep sleep on macOS — the anti-Amphetamine"
  homepage "https://benzo-gules.vercel.app"

  depends_on macos: ">= :ventura"

  app "Benzo.app"

  uninstall quit: "com.benzo.app",
            delete: "/etc/sudoers.d/benzo"

  zap trash: [
    "~/Library/Application Support/Benzo",
    "~/Library/Preferences/com.benzo.app.plist",
  ]
end
