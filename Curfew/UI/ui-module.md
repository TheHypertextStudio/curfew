# UI Module

This module contains shared visual primitives plus settings and lockout views.

## File Map

| File | Responsibility | Key Details |
| --- | --- | --- |
| `CurfewTheme.swift` | Shared visual design system | Defines color tokens, typography helpers, panel/section primitives, and shared button styles. |
| `SettingsView.swift` | Configuration surface | Implements preset controls, day-by-day schedule editing, extension/override controls, warning interval controls, auto-shutdown controls, and setup actions; also includes `GettingStartedView`. |
| `LockoutScreenView.swift` | Lockout interface | Renders full-screen lockout view with time, message, unlock line, shutdown line, override controls, and accessibility variants. |

## UI Boundaries

- Views render state from `CurfewAppModel`.
- Policy calculations stay in `Curfew/Core`.
- Main app shell views (`ContentView`, `MainWindowView`) are in `Curfew/ContentView.swift`.
