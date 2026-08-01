# CurfewUITests

Foreground UI launch tests using XCTest.

## Files

### `CurfewUITests.swift`

Contains semantic fixture tests for onboarding gates, warning/lockout surfaces,
override friction, v0.1 integration visibility, helper errors, and Sparkle.

### `CurfewUITestsLaunchTests.swift`

Contains launch smoke test assertions for foreground running state.

### `MarketingCaptureTests.swift`

Drives the app through each demo-fixture scenario (`CURFEW_DEMO_FIXTURE=1`,
`CURFEW_DEMO_SCENARIO=<token>`) and saves a full-screen `XCUIScreen.screenshot()`
as a `.keepAlways` attachment. This is the CI / debug screenshot tier — it needs
no Screen Recording permission, so it runs on headless GitHub runners.

The scenario tokens (`overview`, `configuration`, `settings`, `getting-started`,
`this-week`, `warning`, `lockout`) match `DemoScenario` raw values in
`Curfew/App/Demo/DemoFixture.swift`. Demo mode is Debug-only, seeds throwaway
stores (it never touches real settings/history), and never arms enforcement, so
auto-shutdown can never fire during a capture.

## Capturing screenshots & video

```bash
just capture        # XCUITest screenshots → build/screenshots/curfew-*.png (CI-safe)
just capture-hero   # local per-window stills with shadow (needs Screen Recording)
just capture-video  # local lockout walkthrough .mov (needs Screen Recording)
```

`just capture-hero` / `just capture-video` use `screencapture`, which requires
**Screen Recording** permission for the controlling terminal (System Settings →
Privacy & Security → Screen Recording). `just capture` does not.

## Operational Note

- These tests launch real app UI and can interrupt desktop workflow.
- Prefer `CurfewTests` for normal development loops.
- Run UI tests as an explicit verification pass near release checkpoints.

## Running

```bash
xcodebuild test -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewUITests
```
