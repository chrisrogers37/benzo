cask "benzo" do
  version "0.2.1"
  sha256 "a75fea68b27345d6b6318f5cb6efaf9b23e38ef8978933f964b66abcf6479e64"

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
