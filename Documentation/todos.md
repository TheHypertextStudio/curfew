# Curfew Implementation TODOs

Source: [`Documentation/plan.md`](./plan.md)
Execution Order: [`Documentation/internal/execution-plan.md`](./internal/execution-plan.md)
Test Matrix: [`Documentation/todo-test-matrix.md`](./todo-test-matrix.md)
Owner: Willie + Codex
Status legend: `[ ]` todo, `[-]` in progress, `[x]` done

## 0. Foundation and Project Structure

- [-] Create `CurfewShared` module for shared domain models and policy logic.
- [x] Convert app shell to a standard macOS app window (`LSUIElement = false`) with menu bar quick access.
- [x] Default debug/Xcode launch starts with enforcement disarmed unless explicitly enabled.
- [x] Add a dedicated app launch coordinator so app startup orchestration is isolated from scene composition.
- [ ] Add targets for `curfew-mcp`, `curfew-ctl`, privileged helper, and WidgetKit extension.
- [-] Configure entitlements: App Group, CloudKit, notifications, accessibility-related requirements.
- [ ] Define centralized app constants (`AppGroup`, bundle IDs, IPC endpoints, CloudKit record names).
- [x] Add feature flags for deferred modules (widget/cloud/MCP/privileged helper) with safe defaults off.

## 1. Schedule + Enforcement Core

- [x] Implement weekly schedule model (per-day end time, unlock time, day-off support).
- [x] Implement schedule presets: 9-to-5, Startup Hours, Half Day.
- [x] Enforce anti-bypass policy:
- [x] Stricter schedule changes can apply next day.
- [x] Weaker schedule changes require 24-hour cooldown.
- [x] Add DST-safe local timezone handling and schedule resolution tests.
- [x] Add schedule summary sentence generation for Settings.
- [x] Add a single `EnforcementSnapshot` read model for UI surfaces.

## 2. Warning Escalation

- [x] Implement warning stage engine for `T-30`, `T-15`, `T-5`, `T-2`, `T-1`, `T-0`.
- [x] Deliver warnings via `UNUserNotificationCenter` with categories/actions.
- [x] Add snooze (1 minute) action only for `T-30` and `T-15`.
- [x] Build click-through dim overlay windows with stage-specific opacity.
- [x] Add always-on-top floating timer for last 5 minutes.
- [x] Add advanced settings to customize warning intervals.

## 3. Lockout Experience

- [x] Build full-screen lockout windows on all displays and spaces.
- [x] Add `.screenSaver`-level window behavior and input capture.
- [x] Add keyboard shortcut interception strategy for lockout.
- [x] Implement rotating encouragement messages.
- [x] Implement lockout visual design (time, unlock time, optional stats card).
- [x] Respect accessibility settings: VoiceOver, reduce motion, reduce transparency.

## 4. Shutdown Manager

- [x] Implement optional auto-shutdown delay setting (1-60 min, default 10).
- [x] Show lockout countdown UI for shutdown.
- [x] Request graceful app termination before shutdown.
- [x] Implement shutdown retry once after 60 seconds on failure.
- [x] Keep lockout active if shutdown ultimately fails.

## 5. Bypass Protection + Privileged Layer

> v0.1 progress note (2026-04-17): a user-space `PersistentLockdown`
> class now ships with tests — writes a `LaunchAgent` plist whose
> `KeepAlive.PathState` watches a trigger file. Arming the trigger tells
> launchd to respawn Curfew if killed; disarming lets normal exits
> succeed. Not automatically installed by default; hardened SMAppService
> path below remains the v0.2 target.

- [ ] Implement privileged helper and LaunchDaemon via `SMAppService`.
- [ ] Persist lockout state in root-owned path: `/Library/Application Support/Curfew/state.plist`.
- [ ] Ensure user app reads but cannot modify privileged state.
- [-] Implement helper health monitor for main app process recovery behavior. (v0.1 shim: `PersistentLockdown` respawning LaunchAgent; v0.2 hardening pending.)
- [ ] Register login items for compatibility requirements.
- [ ] Implement event tap behavior for force-quit interception during lockout.

## 6. Extension and Override Systems

- [x] Implement weekly extension budget (default 3/week) and duration (default 15 min).
- [x] Restrict extension requests to warning phase only.
- [x] Implement deliberate extension activation interaction (hold-to-confirm).
- [x] Implement extension reset day configuration (default Monday at unlock).
- [ ] Implement CLI override command: `sudo curfew-ctl override --reason "..."`
- [x] Enforce override limit (default 2/week) shared with lockout UI flow.

## 7. “Convince Me” Unlock Flow

- [x] Add subtle lockout entry point: “Need to get back in?”
- [x] Enforce 5-minute cooldown before unlock request form.
- [x] Require minimum 50-character justification.
- [x] Add consequence confirmation with 3-second hold-to-confirm.
- [x] Grant time-limited unlock (default 30 min), then re-lock automatically.
- [x] Log timestamp/device/reason/granted duration for each override event.

## 8. Menu Bar UI + Core Screens

- [x] Build menu bar icon state system (green/amber/red/gray/lock).
- [x] Implement popover content: countdown, schedule, extension action, quick links.
- [x] Build primary app window UX with overview, configuration, and getting started sections.
- [-] Unify main window, menu popover, settings, and onboarding styling with shared theme components.
- [x] Build Settings app sections: schedule, enforcement, integrations, devices, advanced.
- [ ] Build “This Week” retrospective entry screen in app UI.

## 9. Calendar Integration

- [ ] Add optional EventKit permission flow.
- [ ] Detect meeting overlaps 1 hour before curfew.
- [ ] Offer extension prompt tied to extension budget consumption.
- [ ] Limit data usage to event title and timing only.
- [ ] Support multiple calendar sources surfaced by EventKit.

## 10. CloudKit Sync

- [ ] Define CloudKit schema for `Schedule`, `LockoutState`, `Device`, `DeviceActivity`.
- [ ] Implement schedule sync with conflict strategy (record change tag, last-write-wins).
- [ ] Implement lockout state propagation with subscriptions.
- [ ] Implement offline/sleep reconciliation on wake/reconnect.
- [ ] Add sync status UI and device list management in Settings.
- [ ] Handle no-iCloud mode gracefully with local-only behavior.

## 11. Unified Work Timer + Device Awareness

- [ ] Track active work time with idle cutoff (default >5 min excluded).
- [ ] Write periodic `DeviceActivity` heartbeat while active (60s interval).
- [ ] Aggregate cross-device time totals for UI and enforcement.
- [ ] Implement hours-based mode and combined mode trigger logic.
- [ ] Implement warning handoff when user switches devices mid-escalation.
- [ ] Implement active-device-aware shutdown sequencing.

## 12. Weekly Retrospective + Export

- [ ] Implement local SQLite storage (52-week retention).
- [ ] Compute daily/weekly rollups: hours, extensions, overrides, days off, streak.
- [ ] Add device-attributed insights for extensions/overrides.
- [ ] Gate pattern insights until 2+ weeks of data.
- [ ] Implement CSV export for historical data.

## 13. WidgetKit

- [ ] Add small widget with circular countdown ring and state-aware visuals.
- [ ] Add medium widget with schedule + extension + work-time context.
- [ ] Add large widget with weekly mini chart and streak.
- [ ] Add lockout/day-off widget states.
- [ ] Wire timeline updates to warning intervals and lockout transitions.

## 14. MCP Server

- [ ] Create `curfew-mcp` executable target bundled in app.
- [ ] Integrate official MCP Swift SDK and stdio transport.
- [ ] Implement read-heavy tool set and write tool queueing behavior.
- [ ] Add optional localhost streamable HTTP transport (disabled by default).
- [ ] Build Integrations settings tab with “Copy MCP config” action.
- [ ] Add Claude Desktop auto-detection and one-click registration prompt.

## 15. Onboarding

- [x] Show a first-launch getting-started window so users can configure Curfew immediately.
- [x] Persist one-time first-launch setup state so Settings only auto-opens once.
- [x] Build first-run flow: welcome, schedule, extension budget, permissions, confirmation.
- [x] Ensure onboarding schedule changes still respect anti-bypass timing rules. (Verified 2026-04-17: all schedule mutations from onboarding route through `model.updateRule` / `applyPreset`, both of which call `queueScheduleUpdate`. The only direct `settings.schedule = ...` write is inside `applyPendingScheduleIfNeeded` after the cooldown elapses. No bypass path exists.)
- [x] Allow onboarding relaunch from Settings.
- [x] Add warm explanatory copy for commitment model and enforcement behavior.

## 16. Accessibility, Localization, Performance

- [ ] Externalize all user-facing strings for localization readiness.
- [ ] Ensure WCAG AA contrast and keyboard navigation in settings.
- [ ] Add VoiceOver support for lockout and primary workflows.
- [ ] Implement reduce-motion and reduce-transparency behavior variants.
- [ ] Verify performance budgets (CPU, memory, render smoothness targets).

## 17. Distribution and Operations

- [ ] Integrate Sparkle auto-update flow and appcast handling.
- [ ] Build DMG packaging flow and installer polish.
- [ ] Configure signing and notarization pipeline in GitHub Actions.
- [ ] Add Homebrew Cask workflow artifacts.
- [ ] Implement in-app uninstall flow and standalone uninstall script.
- [ ] Finalize OSS repository docs: README, LICENSE, CONTRIBUTING, privacy notes.

## 18. System Verification and Release Readiness

- [ ] Build end-to-end verification checklist (single-device and multi-device).
- [ ] Run lockout persistence validation across reboot/login scenarios.
- [ ] Validate no bypass through app force-quit/login/shortcut paths.
- [ ] Validate CloudKit propagation, offline reconciliation, and budget consistency.
- [ ] Validate widget/MCP outputs against app state.
- [ ] Perform launch readiness review and release candidate sign-off.
