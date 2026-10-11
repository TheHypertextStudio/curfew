#!/bin/bash
# Hostless theme checks: no app process, windows, UI automation, or permission prompts.
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
theme_package="$repo_root/build/theme-background"
mkdir -p "$theme_package/Sources/Curfew" "$theme_package/Tests/ThemeTests"
ln -sfn "$repo_root/CurfewKit/Sources/CurfewKit" "$theme_package/Sources/CurfewKit"
for source in UI/CurfewTheme.swift UI/Destinations/SundownType.swift UI/Sundown/SundownPalette.swift; do
    ln -sfn "$repo_root/Curfew/$source" "$theme_package/Sources/Curfew/$(basename "$source")"
done
for source in ThemeConsistencyTests.swift ButtonFeedbackTests.swift SettingsTypographyTests.swift; do
    ln -sfn "$repo_root/CurfewTests/App/UI/$source" "$theme_package/Tests/ThemeTests/$source"
done
cat > "$theme_package/Package.swift" <<'PACKAGE'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CurfewThemeChecks",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CurfewKit", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "Curfew", dependencies: ["CurfewKit"]),
        .testTarget(name: "ThemeTests", dependencies: ["Curfew"])
    ]
)
PACKAGE
swift test --package-path "$theme_package" "$@"
