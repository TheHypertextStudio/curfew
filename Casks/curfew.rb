# frozen_string_literal: true

cask("curfew") do
  version("0.0.16")
  sha256("4804f7cdf26ec6aa54fc0877d5cc5f7c12043bb972c10502f346f0924a5f8f34")

  url("https://github.com/TheHypertextStudio/curfew/releases/download/v#{version}/Curfew-v#{version}.dmg")
  name("Curfew")
  desc("Enforced work boundaries and end-of-day shutdown")
  homepage("https://thecurfew.app/")

  livecheck do
    url(:url)
    strategy(:github_latest)
  end

  # `Curfew` depends on macOS 26 — deployment target in the Xcode project.
  depends_on(macos: :tahoe)

  app("Curfew.app")
  # `curfew-ctl` and `curfew-mcp` ship inside the app bundle's Resources.
  # Exposing them on `$PATH` lets shell scripts and MCP hosts locate them
  # without referencing the bundle path.
  binary("#{appdir}/Curfew.app/Contents/Resources/curfew-ctl")
  binary("#{appdir}/Curfew.app/Contents/Resources/curfew-mcp")

  uninstall(
    early_script: {
      executable: "#{appdir}/Curfew.app/Contents/MacOS/Curfew",
      args: ["--unregister-background-service"],
      must_succeed: true
    },
    quit: "studio.hypertext.apps.curfew"
  )

  zap(
    trash: [
      "~/Library/Application Support/Curfew",
      "~/Library/Caches/studio.hypertext.curfew",
      "~/Library/Group Containers/group.studio.hypertext.curfew/Curfew",
      "~/Library/LaunchAgents/studio.hypertext.curfew.lockdown.plist",
      "~/Library/Preferences/studio.hypertext.curfew.plist"
    ]
  )
end
