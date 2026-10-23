# Presence detection

Curfew can use the camera to detect whether a human shape is visible. It cannot
determine whether the user is working or distracted.
This document is the complete specification of that feature: what it captures,
what it derives, what it retains, how consent works, and what it deliberately
cannot do. It is for users and maintainers evaluating camera access and presence signals.

The short version, for a reader who stops here:

- Camera access is **off by default** on a fresh install or when older settings
  contain no camera preference. Curfew preserves an existing preference. Only a
  person clicking a switch in Curfew's own Settings window turns it on.
- Frames exist in memory for the length of one Vision call and are never
  written to disk, never encoded, and never sent anywhere.
- The only thing that outlives a frame is one boolean — *was a human shape
  visible* — and the time it was taken.
- Curfew detects a human shape. It does not identify one. There is no face print,
  no template, no enrolment, and nothing to compare a face against.

## Why this exists

HID activity shows recent keyboard or pointer input. Camera detection adds a
separate observation about whether a human shape is visible. Neither signal
establishes that the user is working or distracted.

Before this feature, presence was HID idleness alone —
`CGEventSource.secondsSinceLastEventType` with a five-minute threshold, in
`Curfew/Core/Features/IdleWatcher.swift`. That signal measures time since
keyboard or pointer input. Reading a document, attending a meeting, and leaving
the Mac can all produce the same idle reading.

That distinction affects time accounting and shutdown timing. Curfew excludes
idle minutes from counted activity, so an hour spent reading a specification
may not count toward an hours-based limit. The auto-shutdown workflow uses `!isUserIdle` as its "is this the active device?" test, so a
machine whose user is sitting right in front of it gets the short idle grace.
And a distraction warning built on idleness alone would fire without any detected person being present.

The camera supplies human-shape detection without identifying the person or
determining what they are doing.

## The fused signal

Curfew combines two inputs into four states. The rule lives in
`Sources/CurfewKit/Domain/PresenceState.swift` as `PresenceFusion.resolve`.

| HID idle? | Camera says | Fused state       | Meaning |
|-----------|-------------|-------------------|---------|
| no        | anything    | `working`         | Keyboard or pointer input arrived within the idle threshold. |
| yes       | `detected`  | `present_idle`    | No recent input; the camera detected a human shape. |
| yes       | `not_detected` | `absent`       | No recent input; the camera did not detect a human shape. |
| yes       | `unavailable`  | `unknown`      | No recent input; no camera observation is available. |

`unknown` is not a degraded `absent`. It is the
**steady state on a default install**, where the camera is off. Any consumer
that treats "we cannot see" as "nobody is there" is wrong, and the
`PresenceState.isPersonKnownAbsent` accessor exists so no call site has to
re-derive that distinction.

### Recent input takes precedence

If input arrived inside the idle threshold, the answer is `working` no matter
what the camera says. Camera detection can fail for a person outside the frame or in a dark room.
The `working` token therefore reports recent input even when no human shape
is detected. It does not establish that the person was doing work.

The cost of that rule is that Curfew cannot distinguish a human from a mouse
jiggler. Curfew accepts this limitation. It does not use camera detection to reject
recent input.

### Staleness

A camera reading carries the moment it was taken, and a reading older than
`PresenceDetectionPolicy.observationToleranceSeconds` (20 s) decays to
`unavailable`. Without this limit, a capture session that stops producing
readings — after a lid close, device
contention, or a stalled delegate queue — would retain its last observation
indefinitely. A reading timestamped in the future is also
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

`AuditValue` admits strings, integers, doubles, and booleans. Current audit
emitters record only state and permission metadata. They do not encode images
as strings or record frame data.

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

The detection confidence floor is 0.5. A false *present* observation could
trigger a reminder without a person present. The threshold filters
low-confidence detections but cannot eliminate false positives.

## Consent

Camera access is requested exactly once, at the moment the user turns the
feature on, and never at launch or speculatively.

- **Usage description.** `INFOPLIST_KEY_NSCameraUsageDescription`, set on both
  the Debug and Release app configurations in `Curfew.xcodeproj`. It names what
  is looked for, states that nobody is identified and no image is saved or
  sent, and says the feature is off unless turned on.
- **Default off.** `PresenceDetectionPolicy.default` has `cameraEnabled: false`.
  Every decode path falls back to that default, including `decodeIfPresent` on
  a settings blob written by a build that predates the feature — so an upgrade without a stored preference uses "off". Existing preferences
  remain unchanged. No migration turns the feature on.
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

## Inactivity reminder

`DistractionWarningPolicy` decides whether a present-but-idle user gets a
banner. It is pure — no timers, no notification centre, no camera — so every
branch is reachable from a test with three dates and an enum.

The interesting decisions are the ones that produce silence:

- **Only `present_idle` counts.** The `absent` state has no detected human
  shape. It does not establish that the user left, but it does not qualify for
  the reminder. The `unknown` state has no camera observation and does not
  qualify either.
- **Never during lockout or a day off.** During lockout the screen is already
  covering the Mac and "get back to work" is the opposite of the instruction.
  On a scheduled day off, Curfew does not issue the reminder.
- **Never immediately.** Curfew first detects inactivity after five minutes
  without input. The default adds three minutes while a person remains detected
  and idle before the first reminder.
- **At most one every ten minutes** thereafter, so a long meeting produces a
  handful of banners across an afternoon rather than one every three minutes.

Both windows are user-adjustable and clamped on construction *and* on decode, so
a hand-edited settings file cannot disable the feature by arithmetic or turn it
into a notification storm.

Delivery is a silent notification banner, never an overlay and never a lockout.
Curfew delivers it when the camera detects a human shape and no recent input
was recorded. Reading, thinking, and a call can satisfy those conditions. The
reminder does not establish that the user stopped working.

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

The signals have these limits:

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
