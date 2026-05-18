// swift-tools-version: 5.9
import PackageDescription

// Shared library and CLI/MCP/daemon executables. The Curfew app target and
// the widget extension both *also* compile the files in Sources/CurfewKit/
// directly via the Xcode project's PBXFileSystemSynchronizedRootGroup
// entries — there is no `import CurfewKit` from the app side. SPM exists
// here so the three command-line products can share the same source.
//
// Folder contract: anything dropped in Sources/CurfewKit/ is auto-discovered
// by SPM and auto-synced into the Xcode app + widget targets. Files that
// must NOT ship to the CLI/MCP/daemon (anything depending on AppKit,
// SwiftUI, UserNotifications, EventKit, CloudKit, SMAppService, etc.) stay
// under Curfew/ and remain reachable only to the app/widget targets.
let package = Package(
    name: "CurfewTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CurfewKit", targets: ["CurfewKit"]),
        .executable(name: "curfew-ctl", targets: ["curfew-ctl"]),
        .executable(name: "curfew-mcp", targets: ["curfew-mcp"]),
        .executable(name: "curfew-daemon", targets: ["curfew-daemon"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        )
        // Sparkle autoupdate is an Xcode-level framework dependency only.
        // It is NOT used by any SPM target (CLI/MCP don't need it).
        // Add it via Xcode → project → Package Dependencies when ready.
    ],
    targets: [
        .target(
            name: "CurfewKit",
            dependencies: [],
            path: "Sources/CurfewKit",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "curfew-ctl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "CurfewKit")
            ],
            path: "Sources/curfew-ctl"
        ),
        .executableTarget(
            name: "curfew-mcp",
            dependencies: [
                .target(name: "CurfewKit")
            ],
            path: "Sources/curfew-mcp"
        ),
        .executableTarget(
            name: "curfew-daemon",
            dependencies: [
                .target(name: "CurfewKit")
            ],
            path: "Sources/curfew-daemon"
        )
    ]
)
