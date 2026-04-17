// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CurfewTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CurfewKit", targets: ["CurfewKit"]),
        .executable(name: "curfew-ctl", targets: ["curfew-ctl"]),
        .executable(name: "curfew-mcp", targets: ["curfew-mcp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
        // Sparkle autoupdate is an Xcode-level framework dependency only.
        // It is NOT used by any SPM target (CLI/MCP don't need it).
        // Add it via Xcode → project → Package Dependencies when ready.
    ],
    targets: [
        // Domain models and storage shared by the app, CLI, and MCP server.
        // Source files live in Curfew/Core/ and Curfew/App/; this target
        // references them via symlinks so the app Xcode target and the package
        // compile the same source without duplication.
        .target(
            name: "CurfewKit",
            dependencies: [],
            path: "Sources/CurfewKit",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // CLI: reads app settings and activity log; no IPC with the app required.
        .executableTarget(
            name: "curfew-ctl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "CurfewKit"),
            ],
            path: "Sources/curfew-ctl"
        ),
        // MCP server: JSON-RPC 2.0 over stdio. Also reads shared storage and
        // appends write requests to the queue file for user approval in the app.
        .executableTarget(
            name: "curfew-mcp",
            dependencies: [
                .target(name: "CurfewKit"),
            ],
            path: "Sources/curfew-mcp"
        ),
    ]
)
