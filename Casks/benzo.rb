cask "benzo" do
  version "0.3.0"
  sha256 "0da25dee8fdc1b260fd8113d5d001b7f556864fef9ac0578146cb0bde62dd6c7"

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
