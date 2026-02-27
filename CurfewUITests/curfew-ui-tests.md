# CurfewUITests

Foreground UI launch tests using XCTest.

## Files

### `CurfewUITests.swift`

Contains template launch/performance tests that execute the app in foreground.

### `CurfewUITestsLaunchTests.swift`

Contains launch smoke test assertions for foreground running state.

## Operational Note

- These tests launch real app UI and can interrupt desktop workflow.
- Prefer `CurfewTests` for normal development loops.
- Run UI tests as an explicit verification pass near release checkpoints.

## Running

```bash
xcodebuild test -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewUITests
```
