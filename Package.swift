// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CurfewTools",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "curfew-ctl", targets: ["curfew-ctl"]),
        .executable(name: "curfew-mcp", targets: ["curfew-mcp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        // CLI: reads app settings and activity log; no IPC with the app required.
        // Source directory symlinks Core + App files the CLI needs directly into
        // its build unit — no library module wrapper, no `public` modifiers.
        // When CurfewShared is extracted as a proper Swift package (v0.1.1),
        // the symlinks become package imports.
        .executableTarget(
            name: "curfew-ctl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/curfew-ctl",
            linkerSettings: [
                // ActivityStore uses the system SQLite3 bundled with macOS.
                .linkedLibrary("sqlite3"),
            ]
        ),
        // MCP server: JSON-RPC 2.0 over stdio. Also reads shared storage and
        // appends write requests to the queue file for user approval in the app.
        .executableTarget(
            name: "curfew-mcp",
            dependencies: [],
            path: "Sources/curfew-mcp",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
