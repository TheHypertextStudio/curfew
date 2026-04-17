# Curfew Execution Plan

This plan converts the backlog into a practical implementation sequence for the next development stretch.

## Goal

Ship a stable, usable MVP with:

- clear first-run configuration UX
- reliable schedule/warning/lockout behavior
- consistent app-wide interface
- professional non-flaky test coverage for implemented behavior

## Current Baseline

Already implemented:

- app window + menu bar shell
- schedule, warnings, lockout, and shutdown core flows
- extension/override policy foundation
- first-launch setup gating
- broad behavior test coverage for completed todos

Still missing in near-term UX/product flow:

- deliberate extension interaction (hold-to-confirm)
- override event logging
- complete first-run flow steps
- "This Week" in-app retrospective surface
- settings information architecture polish (integrations/devices/advanced)

## Prioritized Milestones

## Milestone A: Complete Core UX Flows

Objective: finish the user-facing workflows needed for daily use.

Scope:

- Implement deliberate extension activation interaction (hold-to-confirm).
- Add override event logging (timestamp, device, reason, granted duration).
- Complete first-run flow steps (welcome, schedule, budget, permissions, confirmation).
- Ensure onboarding schedule changes still respect anti-bypass timing.

Acceptance criteria:

- Users cannot trigger extension by accidental tap.
- Every granted override writes a structured event record.
- First-run flow configures schedule and limits without dead ends.
- Schedule changes from onboarding queue using existing policy rules.

Test gate:

- Add targeted behavior tests for extension hold interactions.
- Add persistence tests for override log records.
- Add onboarding flow routing/state tests.
- Keep existing tests passing.

## Milestone B: Finish Core Screens and Information Architecture

Objective: make the app feel complete as a standard desktop app.

Scope:

- Finish settings section architecture for:
- schedule
- enforcement
- integrations (placeholder-safe)
- devices (placeholder-safe)
- advanced
- Build "This Week" retrospective entry surface in-app.
- Complete shared style consistency across main window, settings, onboarding, and menu popover.

Acceptance criteria:

- All core navigation sections are visible and coherent.
- "This Week" entry exists and shows meaningful current data from available local state.
- No major visual clashes between surfaces.

Test gate:

- Add non-UI behavior/presentation tests for section availability and data formatting.
- Add view model/state tests for retrospective summaries.
- Avoid adding full-screen UI automation during active iteration.

## Milestone C: Hardening and Readiness

Objective: make current scope robust before adding large platform integrations.

Scope:

- Externalize user-facing strings for localization readiness.
- Tighten keyboard navigation and contrast in settings workflows.
- Verify accessibility behavior for primary workflows beyond lockout.
- Add centralized constants for app identifiers/endpoints used by future modules.

Acceptance criteria:

- User strings are centralized and easy to localize.
- Settings workflow is keyboard-navigable end-to-end.
- Accessibility behavior is explicitly validated in tests where possible.
- Constants are defined in one place and consumed by current modules.

Test gate:

- Add focused unit tests for localization key resolution helpers/constants.
- Add tests for accessibility formatting/state behavior.
- Maintain green suite for all existing completed todo mappings.

## Deferred Until Post-MVP

Keep deferred while MVP polish and reliability complete:

- privileged helper + LaunchDaemon
- CloudKit multi-device sync
- widget target
- MCP server target
- CLI tooling
- packaging/distribution automation

These stay tracked in `Documentation/todos.md`.

## Delivery Order

1. Milestone A
2. Milestone B
3. Milestone C

No large integration targets should start before Milestone A and B acceptance criteria are complete.

## Tracking

- Source backlog remains `Documentation/todos.md`.
- Test mapping remains `Documentation/todo-test-matrix.md`.
- This file defines execution order and release gating.
