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
        // Source files live canonically in Curfew/Core/ and Curfew/App/;
        // this target compiles them directly from there so no symlinks are needed.
        .target(
            name: "CurfewKit",
            dependencies: [],
            path: ".",
            exclude: [
                "build",
                "Curfew.xcodeproj",
                "CurfewTests",
                "CurfewUITests",
                "Documentation",
                "scripts",
                "landing",
                ".build",
                ".github",
                "Curfew/UI",
                "Curfew/App/Model",
                "Curfew/App/Infrastructure",
                "Curfew/Core/Features",
                "Sources/curfew-ctl",
                "Sources/curfew-mcp",
                "AGENTS.md",
                "CONTRIBUTING.md",
                "LICENSE",
                "PRIVACY.md",
                "README.md",
                "justfile",
            ],
            sources: [
                // Domain
                "Curfew/Core/Domain/ScheduleModels.swift",
                "Curfew/Core/Domain/CurfewEnforcementEngine.swift",
                "Curfew/Core/Domain/WarningStage.swift",
                "Curfew/Core/Domain/ExtensionBudgetTracker.swift",
                "Curfew/Core/Domain/OverrideRequestPolicy.swift",
                "Curfew/Core/Domain/SchedulePolicyEngine.swift",
                "Curfew/Core/Domain/SchedulePreset.swift",
                // Storage
                "Curfew/Core/Storage/ActivityEvent.swift",
                "Curfew/Core/Storage/ActivityStore.swift",
                "Curfew/Core/Storage/ActivityRollups.swift",
                // Settings + shared types
                "Curfew/App/Settings/CurfewSettingsStore.swift",
                "Curfew/App/Settings/EnforcementSnapshot.swift",
                "Curfew/App/Settings/SharedPaths.swift",
                // MCP queue
                "Curfew/App/MCP/MCPPendingRequest.swift",
                "Curfew/App/MCP/MCPRequestQueue.swift",
                // Utilities (CLI/MCP helpers, not compiled into the app)
                "Sources/CurfewKit/Utilities.swift",
            ],
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
