# Curfew Module

This module contains app entry and shell-level SwiftUI surfaces.

## File Map

| File | Responsibility | Key Details |
| --- | --- | --- |
| `CurfewApp.swift` | App entry and scene composition | Defines launch policy (`CurfewLaunchBehavior`), startup orchestration (`AppCoordinator`), and scenes (`WindowGroup`, `MenuBarExtra`, `Settings`). |
| `ContentView.swift` | Shell views for app and menu bar | Defines `ContentView` (menu popover), `MainWindowView`, `MainWorkspaceSection`, and main section detail views. |

## Launch Behavior

- Debug auto-start is off by default; set `CURFEW_ENABLE_ENFORCEMENT=1` to auto-start enforcement.
- Release auto-start is on by default; set `CURFEW_SKIP_ENFORCEMENT=1` to skip auto-start.

## Runtime Contract

- Shell surfaces consume state from `CurfewAppModel`.
- Menu bar icon and status are derived from `model.snapshot`.
- Menu action "Open Curfew" activates app and opens the main workspace window.
