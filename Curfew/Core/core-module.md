# Core Module

This module contains policy and time-domain logic with no UI dependency.

## File Map

| File | Responsibility | Key Details |
| --- | --- | --- |
| `ScheduleModels.swift` | Schedule primitives and date math | Defines `Weekday`, `DayRule`, `WeeklySchedule`, `ScheduleWindow`; computes schedule windows with day-off, overnight, and local calendar semantics; includes default presets and summary sentence generation. |
| `SchedulePolicyEngine.swift` | Anti-bypass schedule policy | Classifies edits (`weaker`, `stricter`, `noChange`) and computes earliest effective date (24h delay for weaker changes, next-day boundary for stricter changes). |
| `CurfewEnforcementEngine.swift` | Enforcement state evaluation | Produces `CurfewEvaluation` from current time, schedule, extension minutes, override window, and warning intervals. |
| `WarningStage.swift` | Warning interval and stage behavior | Defines `WarningIntervals` normalization and warning stage mapping plus stage capabilities (snooze, floating timer, overlay opacity). |
| `ExtensionBudgetTracker.swift` | Weekly budget tracking | Tracks remaining budget and reset boundaries by configured weekday. |
| `OverrideRequestPolicy.swift` | Override request rules | Defines entry prompt, cooldown, minimum reason length, hold-to-confirm duration, and default override duration. |

## Core Contract

- Keep this module deterministic and UI-agnostic.
- Inject `Calendar` in behavior that depends on timezone/date boundaries.
- Cover new policy behavior with unit tests before wiring into app flow.
