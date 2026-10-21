# Continuous Lockout and Morning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use superpowers:subagent-driven-development only if the owner selects delegated execution. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve a coherent lockout through midnight and sleep, animate meaningful changes including clock movement, and prepare for future customization and optional Sunrise display wake.

**Architecture:** Keep a persistent native host per display and one shared semantic presentation model. Separate restriction authority, schedule-derived atmosphere, content/drafts, appearance, and per-display reveal state. Extend the existing sky and reflection components rather than rebuilding enforcement.

**Tech Stack:** Existing Swift, SwiftUI, AppKit, CurfewKit, Swift Testing, and XCTest UI fixtures. IOKit power APIs are assessment candidates only in this plan.

**Spec:** [Continuous lockout and morning experience](../lockout-experience-design.md).

## Global Constraints

- Morning atmosphere follows the user's **scheduled unlock**.
- **Sunrise is a feature name**, not an astronomical event or a synonym for the instant all restrictions expire.
- Presentation, a request to wake a display, and permission to unlock are separate decisions.
- Preserve schedule evaluation, override validation, deadline persistence, enforcement ownership, helper recovery, and shortcut interception.
- No new dependencies, remote schemas, entitlement changes, full customization editor, or power-management implementation in the core visual refactor.
- No production code before an observed failing test. Every implementation slice updates `Documentation/todos.md` and `Documentation/todo-test-matrix.md`.
- Repository staging/commit rule: `git restore --staged . && git add <explicit-paths> && git commit -F <message-file>` in one invocation. Never stage unrelated work.
- Current checkout has unrelated edits in CI/release workflows and `Curfew.xcodeproj/project.pbxproj`; preserve them. At execution, inspect active worktrees and use a suitable isolated checkout when needed.

## Review Focus

- Midnight while typing: retain answers, focus, and pending reflection while daily accounting resets; Task 2 owns the regression.
- Early override and delayed release: neither a `.working` transition nor the brightening sky alone declares morning/release; Tasks 2 and 3 own tests.
- Wake behind authentication and duplicate notifications: animate once when visible rather than finishing behind the login screen; Task 4 owns tests plus physical acceptance.
- Monitor removal during editing or hold confirmation: retain the shared draft and never duplicate a mutation; Tasks 1 and 4 own tests.
- DST, timezone/clock jumps, and short/missing schedules: derive a valid current sky without replay or invalid interpolation; Task 3 owns tests.

## File and responsibility map

Paths below are existing unless marked new. New types stay app-local; do not add them to the cross-device protocol.

| File | Responsibility |
| --- | --- |
| `Curfew/App/Infrastructure/OverlayCoordinator.swift` | Persistent per-display hosts, reconciliation, coverage and input policy |
| `Curfew/App/Model/CurfewAppModel+Reflection.swift` | Session-scoped reflection lifecycle and shared in-memory drafts |
| `Curfew/App/Model/CurfewAppModel+Lifecycle.swift` | Preserve accounting reset; propagate authoritative transitions |
| `Curfew/App/Model/CurfewAppModel+Sky.swift` | Supply retained scheduled interval to atmospheric calculation |
| New `Curfew/App/Model/RestPresentation.swift` | Pure semantic snapshot, interval, content identity and appearance values |
| New `Curfew/UI/RestScreenView.swift` | Shared sky/clock/status/content/action composition |
| `Curfew/UI/LockoutScreenView.swift`, `Curfew/UI/DaybreakReflectionView.swift` | Reuse their meaningful content inside that composition; remove duplicate full-screen ownership |
| `Curfew/UI/ReflectionFormView.swift` | Bind editable answers to shared session state |
| `Curfew/UI/Sundown/SkyMoment.swift`, `Curfew/UI/Sundown/SundownSky.swift` | Continuous atmosphere and visibility-aware ambient rendering |
| New `Curfew/App/Infrastructure/RestDisplayLifecycle.swift` | Visibility/reveal policy, display identity, notification coalescing |
| `Curfew/App/Model/CurfewAppModel+Reassertion.swift` | Refresh state and connect lifecycle without weakening enforcement |
| `Curfew/App/Demo/DemoFixture.swift`, `CurfewUITests/MarketingCaptureTests.swift` | Safe repeatable overnight/morning/transition captures |

## Task 1: Persistent display hosts and interaction continuity

**Tests:** New `CurfewTests/App/Infrastructure/OverlayContinuityTests.swift`; extend `CurfewUITests/CurfewUITests.swift`.

**Interfaces:** Preserve `OverlayCoordinator.updateOverlays(for:model:lockoutMessage:)`. Add app-local `RestDisplayID` based on the native display ID and a retained host entry. Reconciliation consumes connected IDs/frames, not `ObjectIdentifier(NSScreen)`.

- [ ] Add `retainsHostAcrossTicks()` asserting the same window and content-view references after repeated updates. Add `removesDisconnectedDisplay()` and `preservesHostOnRearrangement()` assertions. Observe the first test failing because the current coordinator replaces `contentView`.
- [ ] Run `xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/OverlayContinuityTests`; save the expected failing result outside task descriptions.
- [ ] Retain each host and let observation update its content. Reconcile added/removed frames independently of 1 Hz content updates. Preserve existing level, space behavior, capture and ownership policies.
- [ ] Add UI regression `testReflectionTypingSurvivesClockTicks` that types a multiword answer, advances fixture time, and asserts the exact answer and focused control remain. Test a hold gesture across multiple ticks.
- [ ] Run the same targeted suite green, affected UI tests, update docs, and commit only this slice using the required atomic chain.

## Task 2: Session content survives calendar rollover

**Tests:** Extend `CurfewTests/App/Model/ReflectionGatingTests.swift` and `DisplayClockTests.swift`; new `RestPresentationTests.swift` beside model tests.

**Interfaces:** `RestSessionContext` retains the scheduled start/end as absolute dates and a stable local occurrence identity. Reuse the existing durable lockout identifier where applicable. Shared `ReflectionDraft` contains the prompt snapshot and `[UUID: ReflectionValue]`; its scope is the current process/session. Snapshot and draft identifiers never change on each tick.

- [ ] Add `pendingEveningSurvivesMidnight()` with an active evening gate, entered answer and 23:59-to-00:01 rollover. Assert pending state, exact draft and occurrence identity survive while daily accounting resets. Run the new tests red before changing reset logic.
- [ ] Add `overrideDoesNotCreateMorning()`, `returnFromOverrideDoesNotRepromptEvening()`, `saveAfterMidnightResolvesOriginalSession()` and `unfinishedEveningSurvivesMorningHandoff()`. Assert save/skip causes one resolution and no duplicate stored reflection.
- [ ] Separate calendar accounting/suppression maintenance from active-session dismissal. Bind `ReflectionFormView` to the shared draft. Preserve current saved-reflection format and prompt snapshots; do not introduce a database migration for unsaved answers.
- [ ] While editing, retain the evening form until save/skip; afterward resolve the current morning scene. Make save from either display act on the same draft and ignore duplicate submission of the same resolved occurrence.
- [ ] Run `xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/ReflectionGatingTests -only-testing:CurfewTests/DisplayClockTests -only-testing:CurfewTests/RestPresentationTests` red then green; update docs and commit the slice.

## Task 3: Shared composition, sky continuity, and purposeful motion

**Depends on:** Tasks 1 and 2.

**Tests:** Extend `CurfewTests/UI/SkyMomentTests.swift`; new `CurfewTests/UI/RestTransitionTests.swift`; safe fixture UI captures.

**Interfaces:** `RestPresentationSnapshot` carries semantic scene, scheduled interval, actual restriction status, content identity and appearance. Proposed pure entrypoint: `RestPresentationSnapshot.resolve(now: Date, session: RestSessionContext, isRestricted: Bool, content: RestContentState) -> RestPresentationSnapshot`. `RestAppearance` supplies one default palette/type/layout/motion value; it is not a persistent customization schema. `RestScreenView` consumes the observed snapshot and shared draft/actions.

- [ ] Add `continuousAcrossScheduledUnlock()` comparing sky output immediately before/at/after the boundary; assert adjacent light/color/position inputs stay within the defined small interpolation tolerance rather than switching to the next lock's day calculation. Add `morningCanRemainRestricted()` asserting the atmosphere can reach morning while restriction status remains locked. Run red.
- [ ] Add table tests for 22:00–07:00, post-midnight lock, a 20-minute interval, missing interval, DST transitions, timezone change and forward/backward clock jumps. Use explicit calendars/dates rather than the machine's current timezone; preserve the actual scheduled absolute interval.
- [ ] Implement the snapshot and shared composition. Use retained schedule context for a continuous 45-minute morning approach capped to the interval and a 15-minute post-boundary blend. Blend sun/glow placement continuously instead of moving a glow from bottom to top at one Boolean flip.
- [ ] Add `ordinaryTickDoesNotTriggerLayoutTransition()`, `contentResolutionMovesClock()`, `interruptedTransitionRetargets()`, and `reducedMotionRemovesTranslation()`. Assert motion decisions for 350 ms content / 650 ms layout, and at most 150 ms opacity with Reduce Motion. Observe red, then implement semantic transitions without globally animating time/status updates.
- [ ] Compose settling, quiet night, morning approach and morning states using existing content. Keep truthful restriction/status/recovery controls visible. Honor keyboard and screen-reader focus; avoid duplicate live announcements and animating focused input away.
- [ ] Add safe fixture capture points at entry, active reflection, resolved night, 23:59/00:01, pre-morning and boundary. Review rendered small/large displays and long content; revise timing/geometry as one composed experience.
- [ ] Run targeted `SkyMomentLockedTests`, `RestPresentationTests` and `RestTransitionTests`, plus affected UI tests. Update docs and commit the slice.

## Task 4: Resume from sleep at the current scene

**Depends on:** Tasks 1 and 3.

**Tests:** New `CurfewTests/App/Infrastructure/RestDisplayLifecycleTests.swift`; extend `EnforcementReassertionWiringTests.swift` and relevant UI fixtures.

**Interfaces:** `RestDisplayLifecycle` consumes `RestDisplayID`, an injected elapsed clock, and typed events (`hidden`, `wakeObserved`, `visible`, `removed`). `handle(_:for:)` returns a `RestRevealDecision` (`none`, `arm`, `begin`, `cancel`). Keep lifecycle state per display, and scene/drafts shared. Select concrete native visibility signals only after confirming their behavior on the supported macOS version.

- [ ] Add `duplicateWakeBeginsOnce()`, `hiddenWakeWaitsForVisibility()`, `activationWithoutSleepDoesNotReveal()`, `oneDisplayWakeDoesNotRestartOthers()`, and `removedDisplayDoesNotKeepRevealAlive()`. Run the new suite red.
- [ ] Refresh authoritative state before resolving a resumed scene. Retain windows, arm one reveal, and consume it on a verified visibility opportunity. Coalesce related screen/system notifications; distinguish app activation from actual return from nonvisibility.
- [ ] Implement the internal opaque cover and 1.2 s reveal with content entry after 200 ms. Never lower whole-window opacity during enforcement. Use current target state when wake crosses midnight/unlock rather than replaying missed phases.
- [ ] Pause ambient rendering when nonvisible. Add `hiddenDisplayStopsAmbientUpdatesButNotEnforcement()` and `releaseDuringRevealDoesNotLeaveInvisibleBlocker()`; observe red, then implement. Disabling drawing must not pause the authoritative tick/daemon path.
- [ ] Verify a disconnected editor display preserves the draft on the remaining display. Record physical display sleep, full sleep and authentication handoff separately from injected event tests.
- [ ] Run `RestDisplayLifecycleTests`, `EnforcementReassertionWiringTests`, and affected native UI tests; update docs and commit the slice.

## Task 5: Assess and design app-initiated Sunrise wake

**Depends on:** The design's authority and timing boundaries, not completion of Tasks 1–4. This investigation does not block passive wake-resume improvements.

**Deliverable:** Extend the design document with a supported-state capability table and a reviewed follow-on implementation boundary. No shipped API wrapper, helper RPC, or actual power event is introduced by this task.

- [ ] Check current SDK headers and Apple documentation for `IOPMAssertionDeclareUserActivity`, bounded display-idle assertions, `IOPMSchedulePowerEvent`, and owned-event cancellation. Use the repo's Context7 workflow first; disclose quota failure and use primary documentation if unavailable.
- [ ] Specify separate requests for display wake while running and system wake while sleeping. Document permissions, actual visibility, failure outcomes, lid/AC/battery behavior and what remains unproven.
- [ ] Design an initially-off display-wake option attached to Sunrise behavior. Before implementation, settle its explicit trigger, numerical maximum awake duration, cancellation/replacement and missed-occurrence rules. Do not assign these from the atmosphere's scheduled-unlock anchor by assumption.
- [ ] Account for synthetic activity in work-time/idle sampling and any future wake-proof policy. Restriction authority must not change when a request succeeds.
- [ ] Define controlled physical probes and clean-up for a later authorized implementation: preserve preexisting power events, cancel only Curfew-owned events, release all assertions, and report requested/observed/visible separately.
- [ ] Review whether full-system wake is supportable through the existing authenticated helper; if needed, propose a separate failing-first native implementation change with capability and rollback checks. Do not promise dark-wake promotion, startup from shutdown, login bypass, or an alarm reliability guarantee.

## Task 6: Verify the complete experience and handoff

**Depends on:** Tasks 2–4. Assess Task 5's decision separately; unimplemented automatic wake is not an acceptance claim.

- [ ] Exercise overnight always-on, midnight while typing, natural morning handoff, display-only sleep, full Mac sleep, authentication, monitor reconnect/rearrangement and unequal display wake times. Use fixtures for deterministic visuals and a controlled physical Mac for OS lifecycle checks.
- [ ] Review recordings for clock movement, interruption and frame continuity; review stills for hierarchy, clipped content and status legibility. Check VoiceOver, keyboard editing, Reduce Motion and Reduce Transparency. Verify hold/override behavior and enforcement coverage throughout transitions.
- [ ] Run required formatter/lint/test/build gates in the repository's order:

```bash
swiftformat Curfew CurfewTests CurfewUITests
swiftformat Curfew CurfewTests CurfewUITests --lint
swiftlint lint --strict
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewUITests
xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Debug -destination 'platform=macOS'
```

- [ ] Confirm additional CurfewKit tests if shared model/storage code changed. Review exact documentation diffs and keep proposed versus passing coverage distinct.
- [ ] Report automated results, rendered design review, physical lifecycle acceptance, optional power capability, and remaining release gaps separately. Review rollback by restoring the previous presentation while preserving deadlines and settings.

## Execution and review status

Implementation is underway in an isolated checkout based on current origin/main. The retained hosts, shared drafts, scheduled atmosphere, composition and resume policy are implemented, with safe unsigned review fixtures. The full native unit suite passes. Rendered accessibility/interruption review and physical lifecycle acceptance remain required before the whole experience is treated as finished. The grouped checklist steps above stay open where they also require recordings, hardware checks, or integration acceptance. Active power wake remains an assessment and follow-on design, with no power experiments or new helper authority in this change.

## Physical verification procedure

Use the unsigned `rest-continuity` fixture, whose private scene clock advances by elapsed wall time on wake. The fixture registers the real workspace sleep/wake notifications but never arms enforcement, starts the keyboard shield, requests shutdown, or changes real schedules/history. Compare the same entered draft before and after screensaver dismissal, display sleep, full Mac sleep/authentication and monitor reconnect. Record the notification-driven resume separately from what the operator actually saw. A single attached monitor establishes reconnect behavior only; unequal wake across multiple displays requires a second monitor.
