# Architecture

> **Three-repo layout:** this doc describes the **`curfew`** repo (the macOS app + the local `curfew-mcp` binary + the license-issuer Worker). Curfew Sync's coordinator (Hono + Durable Objects + D1 + Better Auth) lives in [`curfew-sync`](https://github.com/TheHypertextStudio/curfew-sync); the shared wire-format contract (MCP tool schemas, pending-request shapes) lives in [`curfew-protocols`](https://github.com/TheHypertextStudio/curfew-protocols) and is consumed here via SPM. See `AGENTS.md` §"Repo topology" and §"Cross-repo changes" for the full layout and change-coordination protocol.

## Module map

```
Curfew.app
├── CurfewKit/Sources/CurfewKit/    Pure domain, storage, settings, and MCP queue types
│   ├── Domain/
│   │   ├── CurfewEnforcementEngine   Stateless (schedule, now, budget) → CurfewEvaluation
│   │   ├── ScheduleModels            CurfewSchedule, DayRule, Weekday, SchedulePreset
│   │   ├── SchedulePolicyEngine      Classifies schedule edits as stricter/weaker/no-op
│   │   ├── WarningStage              T-30 / T-15 / T-5 / T-2 / T-1 / lockout enum
│   │   ├── ExtensionBudgetTracker    Weekly budget with reset-weekday logic
│   │   ├── OverrideRequestPolicy     "Convince me" cooldown and justification gate
│   │   └── Reflection                Reflection gate value types (gate, prompt, answer, mood)
│   ├── Storage/
│   │   ├── ActivityEvent / ActivityStore  sqlite3 C API — lifecycle/extension/override events
│   │   ├── ActivityRollups          Daily/weekly aggregation for This Week view
│   │   ├── ReflectionStore          sqlite3 C API — morning/evening reflection content
│   │   └── LockoutDeadlineStore     Durable lockout deadline survives reboot
│   ├── Settings/
│   │   ├── CurfewSettingsStore      UserDefaults persistence for CurfewSettings + reflection config
│   │   ├── ReflectionConfiguration  User-editable per-gate prompts + enable flags
│   │   ├── EnforcementSnapshot      Shared snapshot type for app + widget
│   │   └── SharedPaths              File-path constants used across surfaces (see curfew-flow.md)
│   └── MCP/
│       ├── MCPPendingRequest        Queue payload + provenance metadata
│       ├── MCPRequestQueue          Append-only JSON-lines queue file
│       └── MCPRequestSigner         HMAC-SHA256 per-install signing
│
├── Curfew/Core/Features/  App-only features that depend on Apple frameworks
│   ├── IdleWatcher               CGEventSource idle detection, 5-min default cutoff
│   ├── LicenseGate               Ed25519 offline license key verification (CryptoKit)
│   ├── LicenseKey                Codable payload: email, product, orderID, issuedAt
│   ├── CalendarMonitor           EventKit — today's events, Pro + flag gated
│   ├── CloudKitSyncEngine        CKRecord last-write-wins sync (Pro, flag gated)
│   └── WorkTimeAggregator        Per-day work-minute aggregation from ActivityStore
│
├── Curfew/App/           @MainActor orchestration
│   ├── CurfewAppModel            Central ObservableObject: tick loop, state, actions
│   ├── CurfewAppModel+Actions    User-initiated mutations (override, extension, schedule)
│   ├── CurfewAppModel+Lifecycle  Reactions to state changes, day rollover, shutdown
│   ├── CurfewAppModel+Presentation  Menu bar symbol, status line, snapshot shape
│   ├── FeatureFlags              Runtime on/off for deferred modules
│   ├── OverlayCoordinator        NSWindow management across all displays/Spaces
│   ├── LockoutKeyInterceptor     CGEventTap for ⌘⇥, ⌘Q, ⌘⌥Esc during lockout
│   ├── WarningNotificationManager  UNUserNotificationCenter bridge
│   ├── MCPRequestMonitor         Polls queue file for pending AI write requests
│   ├── PersistentLockdown        Respawning LaunchAgent for bypass deterrence
│   └── PrivilegedHelperManager   SMAppService registration for the root daemon
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
    ├── CurfewWidgetProvider      TimelineProvider — reads mirrored widget settings + shared activity DB
    ├── CurfewWidgetEntry         TimelineEntry snapshot
    └── CurfewWidgetView          Small/medium/large SwiftUI views

CurfewKit/                local Swift package (in its own subfolder, not the repo root,
│                         so opening the repo folder lands on Curfew.xcodeproj).
└── Sources/
    ├── CurfewKit/        SPM library — Domain, Storage, Settings, and MCP queue types
    │                     live here canonically. `Curfew.xcodeproj` references this
    │                     package locally and links the `CurfewKit` library product
    │                     into the app, widget, and CLI tools; every consumer
    │                     `import CurfewKit` (one compiled copy, no dual-compilation).
    ├── curfew-ctl/       ArgumentParser CLI — status, schedule, budget, activity, override.
    │                     Read operations inspect shared storage directly; `override`
    │                     enqueues onto the MCP request queue so the running app
    │                     raises a consent sheet.
    ├── curfew-mcp/       MCP server — stdio transport, JSON-RPC 2.0.
    └── curfew-daemon/    Root-enforced shutdown when the app dies mid-lockout.

CurfewTests/              Unit tests, no UI dependencies (in the Xcode project)
```

## Key design decisions

### Pure enforcement engine
`CurfewEnforcementEngine` is a stateless function: `(schedule, now, extensionMinutes, overrideUntil, warningIntervals) → CurfewEvaluation`. It has no side effects and no stored state. The app model calls it every second and reacts to the result. This makes every enforcement behavior trivially testable and keeps the Core completely independent of AppKit.

### `CurfewKit` as the shared library
Everything shares a single SPM library, `CurfewKit`, whose source lives canonically under `CurfewKit/Sources/CurfewKit/` and is auto-discovered by SPM. The package sits in its own `CurfewKit/` subfolder (not the repo root) so opening the repo folder in Xcode resolves to `Curfew.xcodeproj`, not a package-only window. `Curfew.xcodeproj` references the package locally and links the `CurfewKit` library product into the app, the widget, and the three CLI executables — every consumer `import CurfewKit`. There is one compiled copy of CurfewKit (no dual-compilation); a new file dropped into `CurfewKit/Sources/CurfewKit/{Domain,Storage,Settings,MCP}/` is picked up by SPM automatically and is visible to every consumer once it is marked `public`. (An earlier revision compiled these files directly into the app/widget targets via `PBXFileSystemSynchronizedRootGroup`, with no `import` on the app side; that dual-compile was replaced by the conventional library-product dependency.)

### Feature flags + license as two separate gates
`FeatureFlags` controls whether a code path is *reachable at all* (off by default for incomplete features). `LicenseGate` controls whether a reachable feature is *unlocked* for the user. Both must pass for Pro surfaces to activate. This means a free-tier user who reverse-engineers the binary still hits the license check; a Pro user on an early build still hits the feature flag.

### Long-term gate seams
The activity log schema carries optional `gateKind` and `reflection` fields. MCP tool verbs use generic names where sensible so future gate types (morning intent, midday check-in, evening retrospective) can land as sibling tools rather than overloads of the existing ones. `CurfewEnforcementEngine` is intentionally narrow — future gate types will live as sibling engines, not as modifications to the existing one.

### CloudKit sync strategy
v0.2 splits the private database into four record types — `Settings`, `Device`, `DeviceActivity`, `LockoutState` — collected in `Core/Features/CloudKitSchema.swift`. `Settings` preserves the v0.1 single-record JSON payload for back-compat. `Device` and `DeviceActivity` carry per-Mac identifiers + 60 s heartbeats; `DeviceRegistry` publishes them and drives the Settings → Devices list. `LockoutState` carries the live warning/lockout snapshot so a Mac joining the warning phase mid-escalation can align with whichever device entered warning first.

Delivery is push-based: `CloudKitSyncEngine.start()` registers a deterministic `CKDatabaseSubscription`, and silent APS notifications trigger a pull on remote change. Conflict resolution stays last-write-wins on `modifiedAt` — small values, rare edits, minor consequences.

### MCP transports
Two transports share the same `MCPServer.handle(line:)` dispatcher:

- **stdio** — the default. Claude Desktop spawns `curfew-mcp` and pipes stdin/stdout.
- **Streamable HTTP** — opt-in via Settings → Advanced → Expose MCP over localhost HTTP. Binds `127.0.0.1:9847` with accept-time filtering so non-loopback remotes are rejected. Useful for editors-over-SSH and multi-process setups.

Writes use a Unix-socket seam (`~/Library/Application Support/Curfew/mcp.sock`) that falls through to the JSON request queue when the socket is unavailable. v0.2 ships the client API + the app-side server seam; the POSIX listener itself lands in a later revision.
