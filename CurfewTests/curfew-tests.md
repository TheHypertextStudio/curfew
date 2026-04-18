# CurfewTests

Unit and behaviour tests for Curfew. Uses Swift Testing (`import Testing`).

## Layout

The directory tree mirrors `Curfew/` — each test file sits in the same
module subdirectory as its production subject. Consult a file's
production counterpart at the matching path to find what it exercises.

```
CurfewTests/
├── App/
│   ├── Infrastructure/      # ShutdownWorkflow, PersistentLockdown, overlays, notifications
│   │   ├── ActiveDeviceShutdownTests.swift
│   │   ├── FeatureBehaviorTests.swift
│   │   └── PersistentLockdownTests.swift
│   ├── MCP/                 # AIConsentPolicy, MCPPendingRequest
│   │   ├── AIConsentPolicyTests.swift
│   │   └── MCPPendingRequestTests.swift
│   └── Model/               # CurfewAppModel + CurfewSettingsStore behaviour
│       ├── AppConfigurationBehaviorTests.swift
│       ├── CurfewTests.swift
│       ├── LifecycleWiringTests.swift
│       ├── OnboardingAndUIBehaviorTests.swift
│       └── OverrideAndExtensionBehaviorTests.swift
├── Core/
│   ├── Domain/              # Pure enforcement/policy logic
│   │   ├── CurfewEnforcementEngineTests.swift
│   │   ├── HoursModeEngineTests.swift
│   │   └── SchedulePolicyEngineTests.swift
│   ├── Features/            # IdleWatcher, WorkTimeAggregator
│   │   ├── IdleWatcherTests.swift
│   │   └── WorkTimeAggregatorTests.swift
│   └── Storage/             # ActivityStore + ActivityRecorder + rollups
│       ├── ActivityRecorderTests.swift
│       ├── ActivityRecorderTrimTests.swift
│       ├── ActivityRollupsTests.swift
│       └── ActivityStoreTests.swift
└── Support/                 # Shared test helpers (spies, fixtures)
    ├── ActivityTestSupport.swift
    └── TestSpies.swift
```

The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` for the
test target, so new files dropped into any subdirectory are picked up
automatically — no pbxproj edit required.

## Running

Full suite:

```bash
just test
```

One suite:

```bash
just test-one CurfewEnforcementEngineTests
just test-one FeatureBehaviorTests/overlayWindowConfiguration
```

Full ship-gate (format + lint + tests + Debug build):

```bash
just check
```

With coverage:

```bash
just test-coverage
```
