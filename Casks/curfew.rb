cask "curfew" do
  version "1.0.0"
  sha256 "REPLACE_WITH_RELEASE_DMG_SHA256"

  url "https://github.com/TheHypertextStudio/curfew/releases/download/v#{version}/Curfew-v#{version}.dmg",
      verified: "github.com/TheHypertextStudio/curfew/"
  name "Curfew"
  desc "A hard stop for your Mac"
  homepage "https://curfew.hypertext.studio/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # `Curfew` depends on macOS 26 — deployment target in the Xcode project.
  depends_on macos: ">= :tahoe"

  app "Curfew.app"

  # `curfew-ctl` and `curfew-mcp` ship inside the app bundle's Resources.
  # Exposing them on `$PATH` lets shell scripts and MCP hosts locate them
  # without referencing the bundle path.
  binary "#{appdir}/Curfew.app/Contents/Resources/curfew-ctl"
  binary "#{appdir}/Curfew.app/Contents/Resources/curfew-mcp"

  zap trash: [
    "~/Library/Application Support/Curfew",
    "~/Library/Caches/studio.hypertext.curfew",
    "~/Library/LaunchAgents/studio.hypertext.curfew.lockdown.plist",
    "~/Library/Preferences/studio.hypertext.curfew.plist",
  ]

  # Submission checklist (for our own reference when PR-ing to homebrew-cask):
  #   1. Bump `version` and regenerate `sha256` with
  #      `shasum -a 256 Curfew-v<version>.dmg`.
  #   2. Verify the release is notarized:
  #      `xcrun stapler validate /Applications/Curfew.app`
  #   3. `brew style --fix Casks/curfew.rb`
  #   4. `brew audit --new --cask Casks/curfew.rb`
  #   5. Open PR against https://github.com/Homebrew/homebrew-cask.
end
