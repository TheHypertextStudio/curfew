# CurfewTests

Unit and behavior tests for policy, orchestration, and configuration.

## Framework

- Uses Swift Testing (`import Testing`).
- Tests are behavior-driven and map to explicit todo items.

## Files

### `CurfewTests.swift`

Covers setup and startup contracts plus shared behavior utilities.

- setup gating and first-run behavior
- warning behavior helpers
- lockout shortcut policy
- lockout accessibility behavior
- shutdown workflow behavior

### `SchedulePolicyEngineTests.swift`

Covers schedule and warning policy calculations.

- schedule weakening/strengthening classification
- effective-date rules
- DST-safe schedule resolution
- preset defaults
- warning stage boundaries and opacity
- extension budget decrement behavior

### `CurfewEnforcementEngineTests.swift`

Covers enforcement phase transitions and warning interval behavior.

- working/warning/lockout/day-off transitions
- custom interval mapping
- extension eligibility by stage

### `FeatureBehaviorTests.swift`

Covers app integration behaviors.

- warning notification payload/category contracts
- overlay window configuration contracts
- encouragement message rotation
- shutdown delay/countdown behavior
- warning interval persistence normalization
- override validation and temporary unlock behavior
- launch behavior and app coordinator startup behavior
- snapshot presentation behavior and workspace section contracts

## Running

All unit tests:

```bash
xcodebuild test -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests
```

Selected suites:

```bash
xcodebuild test -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/CurfewEnforcementEngineTests
```

```bash
xcodebuild test -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/FeatureBehaviorTests
```
