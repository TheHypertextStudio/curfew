# Presence detection

Curfew can use the camera to tell whether a person is actually at the machine.
This document is the complete specification of that feature: what it captures,
what it derives, what it retains, how consent works, and what it deliberately
cannot do. It is written to be readable by someone who does not trust it.

The short version, for a reader who stops here:

- The camera is **off** on a fresh install and after every upgrade. Only a
  person clicking a switch in Curfew's own Settings window turns it on.
- Frames exist in memory for the length of one Vision call and are never
  written to disk, never encoded, and never sent anywhere.
- The only thing that outlives a frame is one boolean — *was a human shape
  visible* — and the time it was taken.
- Curfew detects a person. It does not identify one. There is no face print,
  no template, no enrolment, and nothing to compare a face against.

## Why this exists

Curfew's founding document makes two claims that the app could not previously
support: that it can tell whether the user is actually at their computer
working, and that it can warn them when they are distracted.

Before this feature, presence was HID idleness alone —
`CGEventSource.secondsSinceLastEventType` with a five-minute threshold, in
`Curfew/Core/Features/IdleWatcher.swift`. That signal knows when the keyboard
and trackpad went quiet. It does not know why. Reading a long document, sitting
in a meeting, and leaving for the afternoon are the same event to it.

That ambiguity is not merely imprecise, it is load-bearing in the wrong
direction. Idle minutes are excluded from work-time accounting, so an hour
spent reading a specification reads as an hour not worked. The auto-shutdown
workflow uses `!isUserIdle` as its "is this the active device?" test, so a
machine whose user is sitting right in front of it gets the short idle grace.
And a distraction warning built on idleness alone would fire at an empty chair,
which is the fastest way to teach someone to ignore a notification.

A camera answers the missing half of the question, and only that half.

## The fused signal

Two inputs, four outcomes. The rule lives in
`Sources/CurfewKit/Domain/PresenceState.swift` as `PresenceFusion.resolve`.

| HID idle? | Camera says | Fused state       | Meaning |
|-----------|-------------|-------------------|---------|
| no        | anything    | `working`         | Input arrived. Someone is here and using the Mac. |
| yes       | `detected`  | `present_idle`    | Quiet, but a person is in frame. Reading, thinking, on a call. |
| yes       | `not_detected` | `absent`       | Quiet and nobody in frame. The user walked away. |
| yes       | `unavailable`  | `unknown`      | Quiet, and no camera signal to say why. |

`unknown` is not a degraded `absent`. It is the honest answer, and it is the
**steady state on a default install**, where the camera is off. Any consumer
that treats "we cannot see" as "nobody is there" is wrong, and the
`PresenceState.isPersonKnownAbsent` accessor exists so no call site has to
re-derive that distinction.

### HID activity wins outright

If input arrived inside the idle threshold, the answer is `working` no matter
what the camera says. Someone typing on an external keyboard, sitting outside
the lens' cone, or working in a dark room is still working, and a camera that
contradicts live keystrokes is wrong about the room rather than about the user.

The cost of that rule is that Curfew cannot distinguish a human from a mouse
jiggler. That is a trade the product accepts deliberately: Curfew is a
commitment device its user installs for themselves, not an invigilator, and a
design that treats its own user as the adversary at the camera would be a
different product.

### Staleness

A camera reading carries the moment it was taken, and a reading older than
`PresenceDetectionPolicy.observationToleranceSeconds` (20 s) decays to
`unavailable`. This matters more than it looks: without it, a capture session
that wedges — the lid closes, another app seizes the device, the delegate queue
stalls — would pin its last verdict forever, and Curfew would keep reporting a
person who left an hour ago. A reading timestamped in the future is also
rejected, so a backwards clock step cannot extend a reading's life.

## What is captured, derived, and retained

| Stage | What exists | Where | For how long |
|-------|-------------|-------|--------------|
| Captured | Video frames from the default camera at the `.medium` preset (roughly 480×360), 32-bit BGRA | RAM, inside `CameraPresenceEngine`'s capture queue | The duration of one `VNImageRequestHandler.perform` call. Frames arriving between analyses are never read. |
| Derived | Human bounding boxes with confidences, from `VNDetectHumanRectanglesRequest` | RAM, inside one function body | Until the next statement. The boxes, the count, and the confidences are reduced to one `Bool` and discarded. |
| Retained | `PersonObservation`: one `PersonSignal` (`detected` / `not_detected` / `unavailable`) plus a `Date` | RAM, one instance | Until the next observation replaces it, or until the camera stops — `stop()` resets it to `PersonObservation.never`. |
| Recorded | Fused state transitions, camera start/stop, authorization changes, nudges delivered | `~/Library/Logs/Curfew/curfew-app.jsonl` | 90 days (the audit log's normal retention) |

**Never written anywhere:** an image, a crop, a thumbnail, a bounding box, a
confidence score, a person count, a face descriptor, an identity.

The audit envelope makes the last row structurally safe rather than merely
disciplined. `AuditValue` admits strings, integers, doubles, and booleans and
nothing else, so there is no representation in which a frame could be written
even by a future edit that wanted to.

## Detection, not recognition

Curfew runs `VNDetectHumanRectanglesRequest` with `upperBodyOnly = true`. That
request returns rectangles where a human torso appears. It is a detector: it
has no notion of who the human is, computes no embedding, and produces nothing
that could be matched against another frame or another person.

Curfew never calls Vision's face-landmark, face-capture-quality, or
feature-print APIs, and never touches `VNGenerateFaceprintRequest` or any
`Photos`/`ImageIO`/`CoreImage` API. The imports that would make persistence or
transmission possible are absent from
`Curfew/Core/Features/CameraPresenceSensor.swift` by design, and that absence is
part of the contract the file's header documents.

The detection confidence floor is 0.5. A false *present* is the more expensive
error: it would keep Curfew reporting a user who has gone home and would let a
nudge fire into an empty room, so the threshold is set to reject a coat over a
chair rather than to catch every marginal frame.

## Consent

Camera access is requested exactly once, at the moment the user turns the
feature on, and never at launch or speculatively.

- **Usage description.** `INFOPLIST_KEY_NSCameraUsageDescription`, set on both
  the Debug and Release app configurations in `Curfew.xcodeproj`. It names what
  is looked for, states that nobody is identified and no image is saved or
  sent, and says the feature is off unless turned on.
- **Default off.** `PresenceDetectionPolicy.default` has `cameraEnabled: false`.
  Every decode path falls back to that default, including `decodeIfPresent` on
  a settings blob written by a build that predates the feature — so an upgrade
  can only ever land on "off". There is no migration that turns it on.
- **Grant before intent.** `CurfewAppModel.enablePresenceDetection()` prompts
  first and persists `cameraEnabled = true` only if access was actually
  granted. Flipping the setting first would leave a stored intent to run a
  camera the user had just declined.
- **Not reachable by anything else.** The MCP write tools cover schedule,
  extensions, and overrides. Turning on a camera is not among them, and
  `curfew-ctl` has no presence subcommand. Consent for a camera comes from the
  person whose camera it is, in Curfew's own window.
- **Withdrawal is immediate.** `disablePresenceDetection()` stops the session
  synchronously rather than waiting for the next tick. Revoking access in
  System Settings is caught by the per-tick recheck and takes the camera down
  within a second, without a relaunch.

## Off means off

`PresenceMonitor` is the only object in the app that calls
`PersonPresenceSensing.start()`, and it calls it only when the user's setting is
on *and* macOS reports access granted. `PresenceMonitorTests` asserts this from
four directions: the setting off across fifty ticks, each of the three
non-granted authorization states, revocation mid-session, and app termination.

Stopping tears the capture graph down rather than pausing it — `stopRunning()`,
then every output and input removed, then the session released — because a
session that is merely paused can hold the device, and the system camera
indicator light going out is part of the contract.

`VisionCameraPresenceSensor.start()` additionally refuses to run inside a
unit-test host, mirroring the guards already on Accessibility and Notifications
in `RuntimeEnvironment`. `xcodebuild test` re-signs the app on every run, so
without that guard a test pass would re-prompt the developer for camera access
and turn their camera on to do it.

## The in-app indicator

macOS draws its own green light next to the lens, and that light is the
authoritative one — Curfew cannot suppress it and does not try. The in-app
indicator exists because the system light says only that *some* app is using
the camera.

`CameraLiveIndicator` renders only while a session is live, so its presence on
screen is itself the signal. It appears in two places: the Settings presence
panel, above the switch rather than below it, and the menu-bar popover, which is
where someone goes when they notice the green light and want to know which app
turned it on. Both carry a control that turns the feature off.

## The distraction nudge

`DistractionWarningPolicy` decides whether a present-but-idle user gets a
banner. It is pure — no timers, no notification centre, no camera — so every
branch is reachable from a test with three dates and an enum.

The interesting decisions are the ones that produce silence:

- **Only `present_idle` counts.** An `absent` user is not distracted, they are
  gone, and a banner fired at an empty chair is noise the user discovers ten
  minutes later. An `unknown` user is one Curfew has no camera signal for, so
  guessing there would make the nudge fire constantly on a default install.
- **Never during lockout or a day off.** During lockout the screen is already
  covering the Mac and "get back to work" is the opposite of the instruction.
  On a day off there is no work to get back to.
- **Never immediately.** The default is three minutes of stillness before the
  first nudge — long enough to sit out a paragraph or a short call, short
  enough to land inside the drift it is trying to interrupt.
- **At most one every ten minutes** thereafter, so a long meeting produces a
  handful of banners across an afternoon rather than one every three minutes.

Both windows are user-adjustable and clamped on construction *and* on decode, so
a hand-edited settings file cannot disable the feature by arithmetic or turn it
into a notification storm.

Delivery is a silent notification banner, never an overlay and never a lockout.
The state it fires in is one where the user is at the machine but not using it,
and something that seized the screen would interrupt the reading or the call
that Curfew cannot distinguish from drift.

## Audit records

Presence transitions are exactly the kind of state change the audit log exists
to record, and they are written under the same envelope and redaction rules as
everything else. Five event types, documented in full in
[`audit-log.md`](audit-log.md#presence--stream-app):

| Event | What it bounds |
|-------|----------------|
| `presence.state_changed` | The fused verdict moving between `working`, `present_idle`, `absent`, and `unknown` |
| `presence.camera_started` | The camera coming on. Written before the first frame can be analysed. |
| `presence.camera_stopped` | The camera going off, with the reason |
| `presence.camera_authorization_changed` | Consent given, refused, or withdrawn |
| `presence.distraction_warned` | A nudge delivered |

The camera start/stop pair is deliberately redundant with the state records. An
auditor asking "when could this app have been watching me?" should be able to
answer it by grepping two event names, rather than by reconstructing settings
history.

The pre-existing HID-only `presence.changed` record is unchanged and still
written. The fused record is additive: a parser built against the old format
keeps working, and the two disagree by design, because `active`/`idle` is one
signal and `working`/`present_idle`/`absent`/`unknown` is two.

## Limitations

Stated plainly, because a presence signal that oversells itself is worse than
none:

- **A covered lens or a dark room reads as `absent`.** Vision cannot
  distinguish "nobody there" from "cannot see". Curfew's fused state will say
  `absent` where the truth is "unusable frame". The staleness tolerance catches
  a dead session but not a live one pointed at nothing.
- **A mouse jiggler defeats it**, by the HID-wins rule above.
- **A second person in frame is indistinguishable from the user**, because
  Curfew does not identify anyone. Presence means "a human", not "you".
- **A clamshell-mode Mac has no usable camera**, and reports `unknown`
  indefinitely — correctly, but the Settings panel's stalled-camera note is the
  only place that says so.
- **Nothing verifies the audit chain at runtime**, the same gap the audit log
  documents for every other event type.

## Implementation

| Concern | File |
|---------|------|
| Fused state, person signal, observation freshness | `Sources/CurfewKit/Domain/PresenceState.swift` |
| Nudge cadence and eligibility | `Sources/CurfewKit/Domain/DistractionWarningPolicy.swift` |
| User settings and their defaults | `Sources/CurfewKit/Settings/PresenceDetectionPolicy.swift` |
| Capture, Vision, and the "off means off" teardown | `Curfew/Core/Features/CameraPresenceSensor.swift` |
| Fusion, the consent gate, transition publishing | `Curfew/Core/Features/PresenceMonitor.swift` |
| Model wiring, tick integration, nudge delivery | `Curfew/App/Model/CurfewAppModel+Presence.swift` |
| Audit emitters | `Curfew/App/Model/CurfewAppModel+AuditPresence.swift` |
| Consent UI and the data statement | `Curfew/UI/SettingsView+PresencePanel.swift` |
| Camera-live indicator | `Curfew/UI/CameraLiveIndicator.swift` |
| Nudge copy and category | `Curfew/App/Infrastructure/WarningNotificationManager.swift` |
