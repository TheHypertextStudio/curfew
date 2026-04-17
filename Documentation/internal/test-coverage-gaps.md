# Test Coverage Gaps

This document enumerates all remaining test coverage gaps as of the current `Documentation/todos.md` and `Documentation/todo-test-matrix.md`.

## Summary

- Completed todo items (`[x]`): 49
- In-progress todo items (`[-]`): 3
- Not-started todo items (`[ ]`): 61
- Completed items missing explicit matrix mapping: 0

## A. Completed Items Missing Explicit Test Mapping

None.

## B. In-Progress Items Without Full Test Closure

## 0. Foundation and Project Structure

- Create `CurfewShared` module for shared domain models and policy logic.
- Configure entitlements: App Group, CloudKit, notifications, accessibility-related requirements.

## 8. Menu Bar UI + Core Screens

- Unify main window, menu popover, settings, and onboarding styling with shared theme components.

## C. Not-Started Items With No Coverage Yet

## 0. Foundation and Project Structure

- Add targets for `curfew-mcp`, `curfew-ctl`, privileged helper, and WidgetKit extension.
- Define centralized app constants (`AppGroup`, bundle IDs, IPC endpoints, CloudKit record names).

## 5. Bypass Protection + Privileged Layer

- Implement privileged helper and LaunchDaemon via `SMAppService`.
- Persist lockout state in root-owned path: `/Library/Application Support/Curfew/state.plist`.
- Ensure user app reads but cannot modify privileged state.
- Implement helper health monitor for main app process recovery behavior.
- Register login items for compatibility requirements.
- Implement event tap behavior for force-quit interception during lockout.

## 6. Extension and Override Systems

- Implement CLI override command: `sudo curfew-ctl override --reason "..."`

## 8. Menu Bar UI + Core Screens

- Build "This Week" retrospective entry screen in app UI.

## 9. Calendar Integration

- Add optional EventKit permission flow.
- Detect meeting overlaps 1 hour before curfew.
- Offer extension prompt tied to extension budget consumption.
- Limit data usage to event title and timing only.
- Support multiple calendar sources surfaced by EventKit.

## 10. CloudKit Sync

- Define CloudKit schema for `Schedule`, `LockoutState`, `Device`, `DeviceActivity`.
- Implement schedule sync with conflict strategy (record change tag, last-write-wins).
- Implement lockout state propagation with subscriptions.
- Implement offline/sleep reconciliation on wake/reconnect.
- Add sync status UI and device list management in Settings.
- Handle no-iCloud mode gracefully with local-only behavior.

## 11. Unified Work Timer + Device Awareness

- Track active work time with idle cutoff (default >5 min excluded).
- Write periodic `DeviceActivity` heartbeat while active (60s interval).
- Aggregate cross-device time totals for UI and enforcement.
- Implement hours-based mode and combined mode trigger logic.
- Implement warning handoff when user switches devices mid-escalation.
- Implement active-device-aware shutdown sequencing.

## 12. Weekly Retrospective + Export

- Implement local SQLite storage (52-week retention).
- Compute daily/weekly rollups: hours, extensions, overrides, days off, streak.
- Add device-attributed insights for extensions/overrides.
- Gate pattern insights until 2+ weeks of data.
- Implement CSV export for historical data.

## 13. WidgetKit

- Add small widget with circular countdown ring and state-aware visuals.
- Add medium widget with schedule + extension + work-time context.
- Add large widget with weekly mini chart and streak.
- Add lockout/day-off widget states.
- Wire timeline updates to warning intervals and lockout transitions.

## 14. MCP Server

- Create `curfew-mcp` executable target bundled in app.
- Integrate official MCP Swift SDK and stdio transport.
- Implement read-heavy tool set and write tool queueing behavior.
- Add optional localhost streamable HTTP transport (disabled by default).
- Build Integrations settings tab with "Copy MCP config" action.
- Add Claude Desktop auto-detection and one-click registration prompt.

## 15. Onboarding

- Ensure onboarding schedule changes still respect anti-bypass timing rules.

## 16. Accessibility, Localization, Performance

- Externalize all user-facing strings for localization readiness.
- Ensure WCAG AA contrast and keyboard navigation in settings.
- Add VoiceOver support for lockout and primary workflows.
- Implement reduce-motion and reduce-transparency behavior variants.
- Verify performance budgets (CPU, memory, render smoothness targets).

## 17. Distribution and Operations

- Integrate Sparkle auto-update flow and appcast handling.
- Build DMG packaging flow and installer polish.
- Configure signing and notarization pipeline in GitHub Actions.
- Add Homebrew Cask workflow artifacts.
- Implement in-app uninstall flow and standalone uninstall script.
- Finalize OSS repository docs: README, LICENSE, CONTRIBUTING, privacy notes.

## 18. System Verification and Release Readiness

- Build end-to-end verification checklist (single-device and multi-device).
- Run lockout persistence validation across reboot/login scenarios.
- Validate no bypass through app force-quit/login/shortcut paths.
- Validate CloudKit propagation, offline reconciliation, and budget consistency.
- Validate widget/MCP outputs against app state.
- Perform launch readiness review and release candidate sign-off.
