cask "benzo" do
  version "0.3.0"
  sha256 "0da25dee8fdc1b260fd8113d5d001b7f556864fef9ac0578146cb0bde62dd6c7"

  url "https://github.com/chrisrogers37/benzo/releases/download/v#{version}/Benzo-#{version}.dmg"
  name "Benzo"
  desc "Force true deep sleep on macOS — the anti-Amphetamine"
  homepage "https://benzo-gules.vercel.app"

  depends_on macos: ">= :ventura"

  app "Benzo.app"

  # Removing the app does not prove restoration or safe permission retirement.
  # Preserve the existing grant, original-settings backup and preferences.
end
