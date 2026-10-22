# Continuous lockout and morning experience

Implementation design. Source changes and verified native acceptance are separate; this document defines the intended behavior. The execution sequence is in [the implementation plan](internal/lockout-experience-plan.md).

## Intent

Curfew should carry someone from the end of their working day through overnight rest and into morning without abrupt content loss or unrelated-looking screens. It must work both when someone leaves the display on overnight and when they return after the display or Mac has slept.

Morning atmosphere follows the user's **scheduled unlock**. **Sunrise is a feature name**, not an astronomical event or a synonym for the instant all restrictions expire. Presentation, a request to wake a display, and permission to unlock are separate decisions. An independently active restriction must remain enforced even if the sky looks like morning.

The clock may intentionally move and resize when the composition changes. Future customization should be possible without rewriting the screen's lifecycle or enforcement rules.

## Source findings and boundaries

- The baseline lockout path replaces `NSHostingView` instances on repeated updates. The newer baseline already preserves its daybreak host. Extend stable hosting to the continuous experience and update observed data instead.
- `handleDayRollover` calls `resetReflectionGatesForNewDay`, which unconditionally removes pending reflection surfaces. This is a confirmed dismissal path for the evening card; it does not prove the cause of every reported disappearing element.
- `ReflectionFormView` keeps unfinished answers in view-local state. Host replacement and content replacement can discard that state.
- `SkyMoment.locked` already describes a night arc, but its direction flag changes discretely, and changing to the working calculation can jump from pre-dawn to daylight.
- Lockout and daybreak currently use separate window collections. Their handoff should share a stable screen composition while retaining the correct input policy.
- Wake observers currently reassert enforcement; they do not manage an intentional visible reveal or rendering suspension.

This is a native macOS presentation refactor. Preserve schedule evaluation, override validation, deadline persistence, enforcement ownership, helper recovery, and shortcut interception. No remote schema, service, entitlement, or protocol changes belong in the core refactor.

## Approach

Use one persistent rest-screen composition per display, backed by a shared presentation model. Keep the existing sky renderer and content components where useful. Separate the current semantic scene from the short animation used to arrive at it.

Adding transitions to the existing frequently replaced roots is smaller initially but leaves input/state loss and cross-window handoff unresolved. A screen saver plug-in would introduce a different lifecycle without providing Curfew's interaction or enforcement contract. Persistent native hosts address the actual failure path and allow future appearance choices.

## The experience through the night

| Moment | Composition and transition |
| --- | --- |
| Lockout begins | Desktop coverage and enforcement take effect immediately. Sky and content settle into the evening composition inside the covering window. |
| Evening reflection is active | Clock makes room for meaningful content. The user may answer or skip using existing policy. Ordinary clock updates do not move the layout. |
| Reflection resolves | Content fades out and the clock intentionally moves into the quieter overnight composition. |
| Midnight | Bookkeeping may reset; an active evening form, draft, clock, and current lockout explanation remain. There is no midnight dismissal or special animation. |
| Overnight | Dark, restrained atmosphere with gentle optional ambient motion. Keep lock status, the applicable unlock explanation, and available recovery actions understandable. |
| Morning approaches | Sky gradually warms during the final portion of the scheduled interval. Keep the transition continuous through the scheduled boundary. |
| Morning scene becomes relevant | Clock moves to support the morning content. Render actual restriction status independently of the atmosphere. Morning reflection is dismissible according to its existing contract. |
| The screen leaves | If no restriction or user-requested morning surface remains, transition the visual content out without delaying release authority. |

If an evening draft is still being edited when morning becomes relevant, keep that form visible and usable. After save/skip, move to the current morning scene. Never silently discard an unfinished answer to run a transition. A temporary override is not a new morning, and does not create a second evening prompt on return to the same scheduled night.

Evening reflection records use the originating lock occurrence's timestamp, so saving after midnight remains in the correct journal day and does not suppress the next evening. Activity events retain the actual save time. The stored reflection format is unchanged.

Draft continuity covers updates, midnight, sleep, and monitor changes while the process remains alive. Durable recovery of unsaved drafts after process termination is a separate feature; do not claim it from this refactor.

## Presentation and time model

Keep these inputs independent:

1. **Authoritative restriction state:** what is currently enforced and which actions are permitted.
2. **Scheduled interval:** absolute lock/unlock dates used for the overnight atmosphere, retained across date rollover.
3. **Session content:** reflection occurrence, answers, override draft, and current meaningful interaction.
4. **Per-display visibility:** attached, sleeping/hidden, awaiting visibility, revealing, or visible.
5. **Appearance:** palette, typography, spacing, motion, and composition choices.

Derive the target sky from absolute time and the scheduled interval. Use elapsed animation time only for short transitions. On resume or a significant clock change, resolve the current target directly; do not replay all missed states. Preserve the scheduled interval when enforcement continues for another reason beyond that interval. If no valid scheduled interval exists, retain a readable static night fallback and truthful restriction copy.

Proposed first-pass tuning, subject to rendered review:

- Content entry/exit: 350 ms opacity transition with at most 8 pt of translation.
- Intentional clock/layout movement: 650 ms eased movement; clock text continues to show current time without an animation on every tick.
- Wake reveal: 1.2 s fade from an opaque black layer inside the covering window; content entry begins after 200 ms and completes within that reveal.
- Morning approach: final 45 minutes of the scheduled night, capped to the interval length. Blend continuously into the morning atmosphere over the following 15 minutes instead of switching immediately to the next evening's daytime calculation.
- A change during an animation retargets from the current presentation, without briefly restoring old content. Interactions remain correctly validated throughout.

Reduce Motion freezes ambient drift and removes positional/scale movement; necessary content changes use at most a 150 ms opacity transition. Reduce Transparency provides solid readable content surfaces. Preserve native text editing, focus, and accessible action names. Announce meaningful state changes once, not once per animation frame or clock tick.

The dark rest atmosphere uses Dark Aqua on its native covering window so hosted controls inherit an appearance consistent with the sky and light text, regardless of the surrounding application's appearance. Warning and timer windows retain their supplied appearance. This local policy adds no application-wide theme override; future palette customization must keep native controls and the rendered surface consistent. Reverting this window policy restores inherited appearance without changing schedules, drafts, or enforcement.

Screen-covering rest and daybreak windows expose modal accessibility semantics so assistive technology can identify the active interaction context. Click-through warning and timer windows remain nonmodal. This uses the native accessibility property without introducing an application-modal event loop or changing enforcement, display lifecycle, or ordinary workspace presentation.

## Sleep, visibility, and displays

Keep windows and hosts alive during display sleep. Suspend ambient drawing when the app's content is not visible; do not suspend enforcement as a consequence of rendering policy. On wake, refresh authoritative state before choosing the scene and reassert active lockout coverage immediately.

Arm a reveal for a genuine return from nonvisibility. Consume it only when the app has a visible presentation opportunity. System wake and screen wake can both describe the same return, so coalesce them. Normal app activation must not replay a wake animation.

Use display identifiers rather than `NSScreen` object identity for host lifetime. Reconcile attached, removed, rearranged, and rescaled screens. Keep visibility/reveal state per display, but share the semantic scene and editable drafts. A returning display must not restart the animation on an already-visible display. Choose actual native signals during implementation and verify their behavior; workspace sleep/wake notifications alone do not establish per-monitor physical visibility. Native reconciliation also checks `CGDisplayIsAsleep` for each attached display and waits until that display is drawable. This is OS-reported power state; a monitor's electronics can illuminate later and still need hardware verification.

Reconcile native window-visibility callbacks as well as clock updates: a static scene must reveal as soon as macOS reports it visible. Ordinary ticks retain the visible window without reordering it during input; activation and wake reassertion own restoring frontmost coverage. Give the borderless window and its native hosting group useful accessibility names and exclude decorative sky layers from navigation. The deliberate override hold runs alongside native button tracking; presentation changes must not shorten its duration or bypass authorization gates.

Do not fade the entire enforcing window to transparency. Fade content or an opaque internal cover while retaining coverage and mouse capture. When the authoritative state releases, disable enforcement immediately; cosmetic animation must not extend lockout or leave invisible interactive blockers.

macOS owns the backlight transition, login screen, and authentication. A dark cover can choreograph Curfew's first visible frames, but cannot promise control over firmware, monitor behavior, or the system authentication screen. Verify the native handoff rather than inferring it from a notification.

## Sunrise and app-initiated wake

Investigate a user-controlled **Wake the display for Sunrise** option, initially off. Its trigger belongs to the configured Sunrise behavior; the sky's morning anchor remains scheduled unlock. Do not infer a separate wake schedule from the feature name or implicitly replace scheduled unlock with a Sunrise deadline.

Two different capabilities must be assessed:

| Capability | Candidate mechanism | Evidence required |
| --- | --- | --- |
| Mac running, display asleep | Public `IOPMAssertionDeclareUserActivity`; optionally a short bounded display-sleep assertion | API outcome, observed display wake, and actual visible scene, measured separately |
| Mac asleep | Persist a scheduled system wake through `IOPMSchedulePowerEvent` using existing authenticated privilege boundaries if appropriate | Supported hardware/power-state proof, helper availability, cancellation/replacement, and subsequent visible display wake |

Apple documents [display wake through user-activity assertions](https://developer.apple.com/documentation/iokit/1557127-iopmassertiondeclareuseractivity) without special privileges, [bounded display-idle prevention](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep), and [scheduled system power events](https://developer.apple.com/documentation/iokit/1557076-iopmschedulepowerevent), which require root. Recheck SDK headers and current documentation before implementation. Context7 was unavailable because its monthly quota was exhausted; these are primary Apple references.

The assessment must define a maximum hold duration, assertion cleanup, opt-out/cancellation, schedule changes, missed events, quiet recovery, and deduplication. Never renew an assertion indefinitely or wake the display every tick. Cancel only events Curfew owns. Synthetic user activity must not inflate work-time accounting or itself satisfy any future wake-proof condition.

Assess AC and battery operation, closed lid, external displays and docks, manually powered-off monitors, disconnected displays, macOS authentication, absent/denied helper, and app termination. An accepted API request does not prove the monitor lit up or that Curfew was visible. No display wake bypasses authentication or releases a restriction. Do not keep the whole Mac awake overnight just to guarantee an animation.

This plan includes a capability assessment and a concrete opt-in design. Shipping power-management behavior, new helper operations, or full-system wake is a separately reviewed implementation change after capability verification. The core visual refactor must remain useful if automatic wake is unavailable.

## Optional companion screensaver

An optional Curfew screensaver can share the app's atmosphere renderer, absolute-time scene inputs, palette and clock geometry. The purpose is a coherent visual handoff in both directions: the app settles interactive content into the shared ambient composition; the screensaver begins at the matching scene; the returning app starts at that composition and restores its permitted controls.

Apple's public `ScreenSaverView.performGammaFade()` hook requests a gradual system fade at screensaver entry/exit. Evaluate it on the supported macOS versions alongside the app's own motion. Matching composition can hide the ownership boundary, but does not establish a synchronized cross-process compositor animation or control over authentication. An arbitrary user-selected screensaver cannot participate in the same contract.

Keep the screensaver a read-only presentation companion. It must not own enforcement, collect reflection input, authorize release, or receive private draft contents. A follow-on design must settle the supported screensaver target, preview/full-screen lifecycle, read-only appearance/time exchange, multi-display geometry, installation, signing and notarization. No companion target or screensaver setting is added by the current refactor, and choosing another screensaver preserves the normal Curfew experience.

## Customization boundary

Keep a small internal appearance value and semantic content regions: atmosphere, clock, status, contextual content, and actions. The same rendering inputs should support a safe preview using the existing demo fixtures. This allows future palette, clock treatment, content-density, and layout choices without coupling preferences to timers or permissions.

Do not build a layout editor, theme registry, plug-in system, synchronization contract, or persistent appearance migration now. Future customization cannot hide the actual restriction status, remove required recovery actions, weaken accessibility, or change unlock authority.

## Acceptance and rollback

Automated regression coverage must first fail for host replacement, midnight content loss, false morning on override, sky discontinuity, duplicate wake reveal, and drawing while nonvisible. Native UI coverage must exercise typing and focus through ticks, midnight and sleep simulation; transition interruption; and repeat submission across displays.

Use screenshots for composition and recordings for motion. Inspect the complete rendered experience on small and large displays, with long copy, active input, Reduce Motion, Reduce Transparency, keyboard navigation, and VoiceOver. Accelerated fixture time verifies composition, not OS power behavior. Verify display-on overnight and physical wake/authentication paths separately before claiming hardware acceptance.

Keep changes independently reviewable. Retain existing enforcement paths and saved restriction records. Roll back presentation changes without changing schedules or clearing deadlines; if optional power work is later adopted, disabling it must release owned assertions and cancel only owned pending events. The refactor changes native presentation and reflection-session behavior. It adds no permission, helper operation, or power-management call. Restoring the previous presentation must preserve schedules, saved reflections, and active deadlines.

## Sunrise wake operating boundaries

The approved [rest experience features](rest-experience-features.md) supersede the initial wake assessment. The presentation refactor alone adds no power operation. The optional feature distinguishes display activity on a running Mac from a privileged scheduled system wake; neither proves monitor illumination or authentication.

Sunrise follows the current local scheduled unlock, with a configurable 5–60-minute lead-in and a 30-minute default. When enabled and permitted by power policy, hold the display only for the remaining interval through five minutes after scheduled unlock. Release owned assertions on dismissal, disablement, cancellation or teardown. Battery operation requires a separate opt-in. Reconcile the current occurrence after resume without duplicate activity or renewal from the display clock loop.

The authenticated helper schedules one owned wake event and replaces or cancels only Curfew-owned events. Helper unavailability remains an explicit state. No power-on from shutdown, hardware brightness change or authentication bypass is included. Keep synthetic display activity separate from human activity and release proofs. Closed lids, manually powered-off monitors and FileVault retain their platform limitations and require separate hardware evidence.

| Setup | Assessment | Follow-on acceptance |
| --- | --- | --- |
| Mac running, internal display asleep | Public display-wake API is a documented candidate | Observe physical illumination and visible app separately, on AC and battery |
| Mac running, external display in standby | Same API is a candidate; dock/monitor behavior can differ | Exercise the actual dock, cable and monitor; preserve other displays' scene |
| Mac asleep | Requires a scheduled wake; display activation is a second step | Verify owned event delivery, helper rejection, clock/schedule replacement and cancellation |
| Closed lid or disconnected/manually powered-off monitor | No visibility guarantee established | Report unavailable or unverified, without a retry loop |
| Login or FileVault authentication visible | System authentication remains authoritative | Verify Curfew reveals only when its own scene is visible |
| Feature disabled or no current Sunrise request | No wake or keep-awake operation | Verify no assertion/event remains owned by the feature |

No physical wake probes, assertions, helper changes, or scheduled power events have been executed as part of this assessment. The visual refactor remains independent of adopting this optional capability.
