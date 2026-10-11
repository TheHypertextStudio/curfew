// swift-tools-version: 5.9
import Foundation
import PackageDescription

let curfewProtocolsDependency: Package.Dependency = if let localPath =
    ProcessInfo.processInfo.environment["CURFEW_PROTOCOLS_LOCAL_PATH"],
    !localPath.isEmpty {
    .package(name: "curfew-protocols", path: localPath)
} else {
    .package(
        url: "https://github.com/TheHypertextStudio/curfew-protocols.git",
        exact: "0.0.11"
    )
}

/// Shared library `CurfewKit` plus the CLI/MCP/daemon executables. This package
/// lives in `CurfewKit/` (its own subfolder, not the repo root) so opening the
/// repo folder in Xcode resolves to `Curfew.xcodeproj`, not a package-only
/// window. `Curfew.xcodeproj` references this package locally and links the
/// `CurfewKit` library product into the app, the widget, and the CLI tools —
/// every consumer `import CurfewKit`; there is a single compiled copy (no
/// dual-compilation).
///
/// Folder contract: anything dropped in `Sources/CurfewKit/` is auto-discovered
/// by SPM and, because the app and widget link the product, is available to
/// every consumer once marked `public`. Files that must NOT ship to the
/// CLI/MCP/daemon (anything depending on AppKit, SwiftUI, UserNotifications,
/// EventKit, CloudKit, SMAppService, etc.) stay under `Curfew/` and remain
/// reachable only to the app/widget targets.
let package = Package(
    name: "CurfewTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CurfewKit", targets: ["CurfewKit"]),
        .library(name: "CurfewProtocolBridge", targets: ["CurfewProtocolBridge"]),
        .executable(name: "curfew-ctl", targets: ["curfew-ctl"]),
        .executable(name: "curfew-mcp", targets: ["curfew-mcp"]),
        .executable(name: "curfew-daemon", targets: ["curfew-daemon"]),
        .executable(name: "studio.hypertext.curfew.browser", targets: ["curfew-browser"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
        // Versioned wire-format contract shared with curfew-sync (the
        // Cloudflare coordinator). The Swift face of
        // Swift package face of the same exact 0.0.11 contract published as
        // @thehypertextstudio/curfew-protocols through GitHub Packages. The
        // bridge and curfew-mcp targets below consume its generated Codable
        // types; wire shapes are never duplicated locally.
        curfewProtocolsDependency
        // Sparkle autoupdate is an Xcode-level framework dependency only.
        // It is NOT used by any SPM target (CLI/MCP don't need it).
        // Add it via Xcode → project → Package Dependencies when ready.
    ],
    targets: [
        .executableTarget(
            name: "curfew-browser", dependencies: [.target(name: "CurfewKit")],
            path: "Sources/curfew-browser"
        ),
        .testTarget(
            name: "BrowserNativeHostTests",
            dependencies: [.target(name: "CurfewKit")],
            path: "Tests/BrowserNativeHostTests"
        ),
        .testTarget(
            name: "CurfewKitTests",
            dependencies: [.target(name: "CurfewKit")],
            path: "Tests/CurfewKitTests"
        ),
        .target(
            name: "CurfewKit",
            dependencies: [],
            path: "Sources/CurfewKit",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "CurfewProtocolBridge",
            dependencies: [
                .target(name: "CurfewKit"),
                .product(name: "CurfewProtocols", package: "curfew-protocols")
            ],
            path: "Sources/CurfewProtocolBridge"
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
                .target(name: "CurfewKit"),
                .target(name: "CurfewProtocolBridge"),
                .product(name: "CurfewProtocols", package: "curfew-protocols")
            ],
            path: "Sources/curfew-mcp"
        ),
        .executableTarget(
            name: "curfew-daemon",
            dependencies: [
                .target(name: "CurfewKit")
            ],
            path: "Sources/curfew-daemon"
        ),
        .testTarget(
            name: "CurfewProtocolBridgeTests",
            dependencies: [
                .target(name: "CurfewKit"),
                .target(name: "CurfewProtocolBridge"),
                .product(name: "CurfewProtocols", package: "curfew-protocols")
            ],
            path: "Tests/CurfewProtocolBridgeTests"
        ),
        .testTarget(
            name: "CurfewMCPTests",
            dependencies: [
                .target(name: "curfew-mcp")
            ],
            path: "Tests/CurfewMCPTests"
        )
    ]
)
