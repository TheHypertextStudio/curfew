# App Module

This module owns orchestration, persistence, and system-level integration.

## File Map

| File | Responsibility | Key Details |
| --- | --- | --- |
| `CurfewAppModel.swift` | Runtime state and orchestration | Main `ObservableObject`. Owns settings/state/timers, integrates core logic and platform services, and exposes `EnforcementSnapshot` for UI. Also defines helper types: `FeatureFlags`, routing/presentation protocols, `ShutdownWorkflow`, and lockout key interception policy. |
| `CurfewSettingsStore.swift` | Settings persistence | Loads/saves `CurfewSettings` to `UserDefaults`; tracks one-time setup prompt consumption (`curfew.settings.v1`, `curfew.initialSetupShown.v1`). |
| `OverlayCoordinator.swift` | Overlay window management | Creates and reconciles warning, lockout, and floating timer windows across all displays. |
| `WarningNotificationManager.swift` | Warning notifications | Registers categories/actions, sends warning-stage notifications, and forwards snooze actions through callback. |

## Runtime Flow

`CurfewAppModel.tick()` performs runtime reconciliation in order:

1. update time/day tokens
2. apply pending schedule changes
3. reset weekly extension and override trackers if needed
4. evaluate enforcement phase
5. update notifications
6. update lockout key interception
7. update shutdown workflow
8. update overlay windows

## Contracts and Extension Points

- Enforcement startup is gated by `settings.hasCompletedInitialSetup`.
- One-time onboarding prompt is gated by `consumeShouldShowInitialSetup()`.
- `FeatureFlags` defaults deferred modules off (`widgetKit`, `cloudSync`, `mcpServer`, `privilegedHelper`).
- `AppRouting` and `GettingStartedPresenting` are protocol boundaries used for test spies and future routing changes.
