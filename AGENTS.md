# Curfew Agent Operating Guide

This file defines how coding agents must operate in this repository.

## Project Context

Curfew is a production-focused macOS app that enforces end-of-day boundaries with escalating warnings, lockout behavior, and optional shutdown.

Primary code and docs locations:

- `Curfew/` app code (Swift/SwiftUI/AppKit + domain logic)
- `CurfewTests/` unit and behavior tests
- `CurfewUITests/` UI tests
- `Documentation/plan.md` product requirements
- `Documentation/todos.md` implementation backlog and status
- `Documentation/todo-test-matrix.md` behavior-to-test mapping

## Non-Negotiable Rules

1. No production code changes without a failing test first.
2. No substantive change without documentation updates.
3. No completion claim without test/lint/build verification evidence.

If there is uncertainty, treat the change as substantive and apply full process.

## Standard Command Runbook (From Repo Root)

Use these defaults unless a maintainer explicitly instructs otherwise.

Project defaults:

- Project: `Curfew.xcodeproj`
- Scheme: `Curfew`
- Destination: `platform=macOS`

Tool installation and version checks:

```bash
brew install swiftlint swiftformat
command -v xcodebuild && xcodebuild -version
command -v swiftformat && swiftformat --version
command -v swiftlint && swiftlint version
```

Common test commands:

```bash
# single test method (replace placeholders)
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/<TestCase>/<testMethod>

# concrete examples from this repo
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/SchedulePolicyEngineTests
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/FeatureBehaviorTests
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewUITests/CurfewUITests

# full unit tests
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests

# full UI tests
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewUITests
```

Common build commands:

```bash
xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Debug -destination 'platform=macOS'
xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Release -destination 'platform=macOS'
```

Lint and format commands:

```bash
# apply formatting
swiftformat Curfew CurfewTests CurfewUITests

# formatting check (must pass before completion claim)
swiftformat Curfew CurfewTests CurfewUITests --lint

# lint check (must pass before completion claim)
swiftlint lint --strict
```

## Mandatory TDD Workflow (Hard Gate)

Use red-green-refactor for all feature, bugfix, refactor, and behavior changes.

1. Red
- Add or update the smallest test that expresses the desired behavior.
- Run targeted tests and confirm the new/changed test fails for the expected reason.
- Command pattern:
```bash
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/<TestCase>/<testMethod>
```

2. Green
- Implement the minimum code required to pass the failing test.
- Re-run the same targeted tests until they pass.
- Command pattern:
```bash
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/<TestCase>/<testMethod>
```

3. Refactor
- Improve clarity/structure while preserving behavior.
- Keep all tests green throughout refactor work.
- After refactor, run at minimum:
```bash
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests
```

Hard prohibitions:

- No implementation-first coding.
- No retrofitting tests after code is already written.
- No marking work complete if the failing-first proof was skipped.

## Mandatory Documentation Workflow (Comprehensive Gate)

Every substantive change must update docs in the same change set.

Required updates:

1. `Documentation/todos.md`
- Update item status (`[ ]`, `[-]`, `[x]`) and relevant notes.

2. `Documentation/todo-test-matrix.md`
- Add or adjust mappings from changed behavior/todo items to automated tests.

3. Additional docs under `Documentation/` when needed
- Add or update behavior notes, architecture notes, operational guidance, or release notes content when the change affects those areas.

Doc verification commands:

```bash
# confirm docs were touched in this change
git diff --name-only -- Documentation/

# review exact doc edits before completion claim
git diff -- Documentation/todos.md Documentation/todo-test-matrix.md
```

Documentation content requirements for substantive work:

- What changed and why
- Behavioral impact and user-visible impact
- Test coverage impact
- Operational/release impact
- Risk and rollback notes (if applicable)

## Mandatory Lint and Formatting Workflow (Hard Gate)

Lint and formatting are required before claiming completion.

Required tooling policy:

- `SwiftFormat` for formatting
- `SwiftLint` for lint checks

Execution expectations:

1. Run formatter on impacted code.
2. Run lint checks.
3. Re-run tests after formatting/lint-driven changes.

Required execution order:

```bash
swiftformat Curfew CurfewTests CurfewUITests
swiftformat Curfew CurfewTests CurfewUITests --lint
swiftlint lint --strict
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests
```

If lint/format tooling or config is missing:

- Do not silently skip.
- Explicitly report the missing setup as a blocker.
- Provide exact missing file/tool details and the commands attempted.
- Do not claim full completion until resolved or explicitly waived by a maintainer.

## Production-Ready macOS App Best Practices

Agents must preserve production readiness in all changes.

1. Reliability and State Safety
- Prefer deterministic state transitions and explicit edge-case handling.
- Preserve lockout/recovery correctness across app relaunches and system lifecycle events.
- Avoid hidden side effects in schedule/enforcement decisions.

2. Security and Privacy
- Respect least-privilege principles for entitlements and system capabilities.
- Avoid broad permissions unless required.
- Document any new permission, helper, or privileged behavior clearly.

3. Accessibility and UX Integrity
- Preserve VoiceOver compatibility where applicable.
- Respect Reduce Motion/Reduce Transparency behavior.
- Keep error states clear and actionable.

4. Performance and Responsiveness
- Avoid blocking main-thread work.
- Keep overlays/lockout UI responsive during warning and enforcement windows.
- Prevent unnecessary background churn.

5. Release and Distribution Quality
- Keep changes compatible with signed/notarized distribution goals.
- Highlight any change that can impact packaging, entitlement validation, startup behavior, or update paths.

## Verification Before Completion

A task is not complete until verification evidence is provided.

Minimum evidence to report:

1. Tests run
- Targeted tests for changed behavior
- Additional relevant suites (unit/UI as appropriate)
- Minimum commands to report:
```bash
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/<TestCase>/<testMethod>
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests
```

2. Lint and formatting
- Formatter command outcome
- Lint command outcome
- Minimum commands to report:
```bash
swiftformat Curfew CurfewTests CurfewUITests --lint
swiftlint lint --strict
```

3. Build status
- Build result for impacted target(s)
- Minimum command to report:
```bash
xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Debug -destination 'platform=macOS'
```

4. Gaps
- Explicit list of checks not run and why

## Change Classification Matrix

Substantive changes (full gate required):

- Feature additions or behavior changes
- Bug fixes
- Refactors affecting behavior or risk profile
- Schedule/enforcement/lockout/override logic changes
- Settings, persistence, migration, entitlement, or release-process changes
- Test strategy or test coverage model changes

Trivial changes (may use reduced process only when clearly safe):

- Typo-only copy edits with no behavior impact
- Comment-only edits
- Non-functional markdown formatting

If a change appears trivial but touches executable code, treat it as substantive.

## Handoff / PR Checklist

Include this in final handoff notes:

1. Failing test was added/observed first (or justified exception approved by maintainer).
2. Final tests pass.
3. Lint and format checks pass.
4. Documentation updated with exact files changed.
5. Risks, mitigations, and rollback notes listed where relevant.
6. Any remaining gaps/blockers clearly called out.

## Agent Behavior Expectations

- Prefer small, reviewable diffs with clear intent.
- Align with existing architecture and naming conventions.
- Avoid introducing process exceptions without explicit maintainer approval.
- Never skip test, lint, or documentation gates due to time pressure.
