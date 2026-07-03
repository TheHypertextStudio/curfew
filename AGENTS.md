# Curfew Agent Operating Guide

This file defines how coding agents must operate in this repository.

## Repo topology

Curfew lives across three repositories. Boundaries here matter — most edits stay in **this** repo, but anything touching the cross-device wire format or the Cloudflare coordinator goes elsewhere.

- **`curfew`** (this repo) — the macOS app, the local `curfew-mcp` and `curfew-ctl` and `curfew-daemon` binaries, the license-issuer Cloudflare Worker (`web/worker/src/` + `web/worker/wrangler.toml`), the landing site (`web/landing/`), the Homebrew cask (`Casks/`), and the product-level Curfew Sync design (`Documentation/curfew-sync.md`).
- **`curfew-sync`** ([github.com/TheHypertextStudio/curfew-sync](https://github.com/TheHypertextStudio/curfew-sync)) — the Cloudflare-deployed Curfew Sync coordinator: Hono Worker, Durable Objects, D1, Better Auth, OAuth 2.1 MCP endpoint. Backend architecture lives in *that* repo's `Documentation/ARCHITECTURE.md`.
- **`curfew-protocols`** ([github.com/TheHypertextStudio/curfew-protocols](https://github.com/TheHypertextStudio/curfew-protocols), npm `@hypertext/curfew-protocols`) — versioned JSON Schemas for MCP tools, pending-request shapes, and (in v0.2+) sync delta envelopes and OAuth payloads. Consumed by both `curfew` (via SPM) and `curfew-sync` (via npm). Tagged releases only — no floating `main` references.

## Cross-repo changes

A change to a wire-format shape (MCP tool argument schemas, the `MCPPendingRequest` envelope, OAuth scope strings, sync deltas) is a **three-PR ceremony**, in this order:

1. **`curfew-protocols`** — edit schema, run `pnpm codegen`, contract tests, bump version (semver: additive = minor, breaking = major), tag, `pnpm publish`.
2. **`curfew-sync`** — bump `@hypertext/curfew-protocols` in `package.json`, update consuming code, deploy.
3. **`curfew`** (this repo) — bump the SPM pin in `Package.swift` (currently `exact: "0.1.0"` for the curfew-mcp target), update consuming Swift code, ship in the next macOS release.

Do not invent new shapes in this repo. If a shape needs to exist on the wire (anything the local app sends to or receives from a remote AI host or the coordinator), it goes through `curfew-protocols` first.

## Project Context

Curfew is a production-focused macOS app that enforces end-of-day boundaries with escalating warnings, lockout behavior, and optional shutdown.

Primary code and docs locations:

- `Curfew/` app code (Swift/SwiftUI/AppKit + domain logic)
- `CurfewKit/` local Swift package: shared `CurfewKit` library + the CLI/MCP/daemon executables. `Curfew.xcodeproj` references it locally and links the `CurfewKit` library into the app, widget, and CLI tools (every consumer `import CurfewKit` — no dual-compilation)
- `CurfewKit/Sources/CurfewKit/` shared Swift library (Domain, Storage, Settings, MCP queue types)
- `CurfewKit/Sources/curfew-mcp/` local MCP server binary; consumes `@hypertext/curfew-protocols` via SPM
- `CurfewKit/Sources/curfew-ctl/` CLI
- `CurfewKit/Sources/curfew-daemon/` privileged helper
- `CurfewTests/` unit and behavior tests
- `CurfewUITests/` UI tests
- `Documentation/plan.md` product requirements
- `Documentation/curfew-sync.md` Curfew Sync product design (the coordinator's external contract — backend internals live in the `curfew-sync` repo)
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

Marketing / debug capture (Debug-only demo fixture; never touches real
settings/history and never arms enforcement, so auto-shutdown can't fire):

```bash
just capture        # XCUITest screenshots → build/screenshots/curfew-*.png (CI-safe, no perms)
just capture-hero   # local per-window stills with shadow (needs Screen Recording perm)
just capture-video  # local lockout walkthrough .mov (needs Screen Recording perm)

# launch a single surface by hand
CURFEW_DEMO_FIXTURE=1 CURFEW_DEMO_SCENARIO=lockout \
  build/Build/Products/Debug/Curfew.app/Contents/MacOS/Curfew
```

Scenarios live in `Curfew/App/Demo/DemoFixture.swift`. `just capture-hero` /
`capture-video` require Screen Recording permission (System Settings → Privacy &
Security → Screen Recording); `just capture` does not.

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
