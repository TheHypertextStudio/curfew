# Architecture

## Module map

```
Curfew.app
├── Curfew/Core/          Pure domain logic — no UI, no AppKit
│   ├── CurfewEnforcementEngine   Stateless (schedule, now, budget) → CurfewEvaluation
│   ├── ScheduleModels            CurfewSchedule, DayRule, Weekday, SchedulePreset
│   ├── WarningStage              T-30 / T-15 / T-5 / T-2 / T-1 / lockout enum
│   ├── ExtensionBudgetTracker    Weekly budget with reset-weekday logic
│   ├── OverrideRequestPolicy     "Convince me" cooldown and justification gate
│   ├── ActivityRecorder          sqlite3 C API — lifecycle/extension/override events
│   ├── ActivityRollups           Daily/weekly aggregation for This Week view
│   ├── IdleWatcher               CGEventSource idle detection, 5-min default cutoff
│   ├── LicenseGate               Ed25519 offline license key verification (CryptoKit)
│   ├── LicenseKey                Codable payload: email, product, orderID, issuedAt
│   └── CalendarMonitor           EventKit — today's events, Pro + flag gated
│
├── Curfew/App/           @MainActor orchestration
│   ├── CurfewAppModel            Central ObservableObject: tick loop, state, actions
│   ├── CurfewAppModel+Actions    User-initiated mutations (override, extension, schedule)
│   ├── CurfewAppModel+Lifecycle  Reactions to state changes, day rollover, shutdown
│   ├── CurfewAppModel+Presentation  Menu bar symbol, status line, snapshot shape
│   ├── FeatureFlags              Runtime on/off for deferred modules
│   ├── CurfewSettingsStore       UserDefaults persistence for CurfewSettings
│   ├── OverlayCoordinator        NSWindow management across all displays/Spaces
│   ├── LockoutKeyInterceptor     CGEventTap for ⌘⇥, ⌘Q, ⌘⌥Esc during lockout
│   ├── WarningNotificationManager  UNUserNotificationCenter bridge
│   ├── MCPRequestMonitor         Polls queue file for pending AI write requests
│   ├── CloudKitSyncEngine        CKRecord last-write-wins sync (Pro, flag gated)
│   └── PersistentLockdown        Respawning LaunchAgent for bypass deterrence
│
├── Curfew/UI/            SwiftUI views
│   ├── ContentView               NavigationSplitView: Overview / Configuration / Setup
│   ├── SettingsView              tabbed: true → Settings window; false → sidebar pane
│   ├── SettingsView+InfoPanels   Integrations, Devices, Advanced, Setup panels
│   ├── LockoutOverlayView        Full-screen dim + extend + override UI
│   ├── ThisWeekView              Retrospective: lockouts held, budgets, streak
│   ├── LicenseView               Activate / deactivate Pro license key
│   ├── PurchasePromptView / ProGate  Gate wrapper for Pro-only surfaces
│   ├── MCPConsentSheet           Approve / deny queued AI write requests
│   ├── DayRuleRow                Per-day schedule editor row (Apply to all shortcut)
│   └── HoldToConfirmButton       Deliberate hold interaction, reusable
│
└── CurfewWidget/         WidgetKit extension (Pro, flag gated)
    ├── CurfewWidget              StaticConfiguration, small/medium/large families
    ├── CurfewWidgetProvider      TimelineProvider — reads shared UserDefaults suite
    ├── CurfewWidgetEntry         TimelineEntry snapshot
    └── CurfewWidgetView          Small/medium/large SwiftUI views

Sources/
├── CurfewKit/            SPM library — public re-exports of Core/Domain, Core/Storage,
│                         Settings, and MCP queue types. One source of truth that the
│                         app, CLI, and MCP server all depend on.
├── curfew-ctl/           ArgumentParser CLI — status, schedule, budget, activity, override.
│                         Read operations inspect shared storage directly; `override`
│                         enqueues onto the MCP request queue so the running app
│                         raises a consent sheet.
└── curfew-mcp/           MCP server — stdio transport, JSON-RPC 2.0.

CurfewTests/              ~90 unit tests, no UI dependencies
```

## Key design decisions

### Pure enforcement engine
`CurfewEnforcementEngine` is a stateless function: `(schedule, now, extensionMinutes, overrideUntil, warningIntervals) → CurfewEvaluation`. It has no side effects and no stored state. The app model calls it every second and reacts to the result. This makes every enforcement behavior trivially testable and keeps the Core completely independent of AppKit.

### `CurfewKit` as the shared library
The CLI, MCP server, and app all link against a single SPM library, `CurfewKit`, that re-exports Core/Domain, Core/Storage, App/Settings, and the MCP queue types. Earlier revisions shared source files by symlink across targets; the library form makes the public seam explicit, removes duplicate compilation, and lets each consumer import exactly what it needs. Source files still live canonically under `Curfew/` so Xcode's synchronized-folder discovery continues to work — `Package.swift` just compiles them into the library target from there.

### Feature flags + license as two separate gates
`FeatureFlags` controls whether a code path is *reachable at all* (off by default for incomplete features). `LicenseGate` controls whether a reachable feature is *unlocked* for the user. Both must pass for Pro surfaces to activate. This means a free-tier user who reverse-engineers the binary still hits the license check; a Pro user on an early build still hits the feature flag.

### Long-term gate seams
The activity log schema carries optional `gateKind` and `reflection` fields. MCP tool verbs use generic names where sensible so future gate types (morning intent, midday check-in, evening retrospective) can land as sibling tools rather than overloads of the existing ones. `CurfewEnforcementEngine` is intentionally narrow — future gate types will live as sibling engines, not as modifications to the existing one.

### CloudKit sync strategy
One `CKRecord` in the private database, record type `"Settings"`, deterministic record name `"curfew-settings-v1"`. Fields: `payload: Data` (JSON-encoded `CurfewSettings`) and `modifiedAt: Date`. Conflict resolution is last-write-wins on `modifiedAt`. This is intentionally simple — the schedule is a small, rarely-changed value and the consequences of a merge conflict are a minor schedule mismatch, not data loss.
