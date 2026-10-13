#!/bin/bash
# Hostless theme checks: no app process, windows, UI automation, or permission prompts.
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
theme_package="$repo_root/build/theme-background"
mkdir -p "$theme_package/Sources/Curfew" "$theme_package/Tests/ThemeTests"
ln -sfn "$repo_root/CurfewKit/Sources/CurfewKit" "$theme_package/Sources/CurfewKit"
for source in UI/CurfewTheme.swift UI/Destinations/SundownType.swift UI/Sundown/SundownPalette.swift App/Infrastructure/PrivilegedHelperManager.swift App/Infrastructure/PrivilegedDaemonClient.swift App/Infrastructure/EnforcementHealth.swift UI/AccountConnectionPresentation.swift Core/Features/AccountSyncStatus.swift UI/ConsentPresentation.swift Core/Features/TaskBrowserEnforcementViewModel.swift Core/Features/CalendarMonitor.swift UI/CalendarOverlapCopy.swift; do
    ln -sfn "$repo_root/Curfew/$source" "$theme_package/Sources/Curfew/$(basename "$source")"
done
ln -sfn "$repo_root/Curfew/App/Infrastructure/PrivilegedHelperMaintenance.swift" "$theme_package/Sources/Curfew/PrivilegedHelperMaintenance.swift"
ln -sfn "$repo_root/Curfew/App/Infrastructure/AppServiceController.swift" "$theme_package/Sources/Curfew/AppServiceController.swift"
ln -sfn "$repo_root/Curfew/App/Infrastructure/HelperReadAuthorization.swift" "$theme_package/Sources/Curfew/HelperReadAuthorization.swift"
ln -sfn "$repo_root/Curfew/App/Infrastructure/PrivilegedHelperManager+Repair.swift" "$theme_package/Sources/Curfew/PrivilegedHelperManager+Repair.swift"
for source in ThemeConsistencyTests.swift ButtonFeedbackTests.swift SettingsTypographyTests.swift PresentationStateTests.swift ConsentPresentationTests.swift CalendarPresentationTests.swift AccountStatusPresentationTests.swift; do
    ln -sfn "$repo_root/CurfewTests/App/UI/$source" "$theme_package/Tests/ThemeTests/$source"
done
ln -sfn "$repo_root/CurfewTests/Core/Settings/TaskBrowserEnforcementViewModelTests.swift" "$theme_package/Tests/ThemeTests/TaskBrowserEnforcementViewModelTests.swift"
ln -sfn "$repo_root/CurfewTests/App/Infrastructure/PrivilegedHelperManagerTests.swift" "$theme_package/Tests/ThemeTests/PrivilegedHelperManagerTests.swift"
ln -sfn "$repo_root/CurfewTests/App/Infrastructure/HelperServiceTestDoubles.swift" "$theme_package/Tests/ThemeTests/HelperServiceTestDoubles.swift"
ln -sfn "$repo_root/CurfewTests/App/Infrastructure/HelperRepairIntegrationTests.swift" "$theme_package/Tests/ThemeTests/HelperRepairIntegrationTests.swift"
ln -sfn "$repo_root/CurfewTests/App/Infrastructure/EnforcementHealthTests.swift" "$theme_package/Tests/ThemeTests/EnforcementHealthTests.swift"
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
