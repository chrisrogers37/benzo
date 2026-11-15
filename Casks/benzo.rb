cask "benzo" do
  version "0.4.0"
  sha256 "167333639732a399f3e74d5cf35f5218284d207afe8baf88866e3c45fb2cb8ff"

  url "https://github.com/chrisrogers37/benzo/releases/download/v#{version}/Benzo-#{version}.dmg"
  name "Benzo"
  desc "Manage selected macOS sleep and wake settings from the menu bar"
  homepage "https://benzo.work"

  depends_on macos: ">= :ventura"

  app "Benzo Development.app"

  # Removing the app does not prove restoration or safe permission retirement.
  # Preserve the existing grant, original-settings backup and preferences.
end
