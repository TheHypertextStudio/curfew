# Rest appearance, screensaver and Sunrise

Curfew's rest experience combines a readable interactive rest screen, an optional native screensaver and opt-in Sunrise wake. Morning follows the scheduled unlock. Appearance, handoff, wake and screensaver dismissal cannot release stronger restrictions or bypass macOS authentication.

## Appearance on this Mac

Rest Screen settings provide a live preview, animated atmosphere, solid background or one owned imported image, Sundown/warm amber/cool twilight palettes, rounded/standard/serif system-formatted clocks, center/upper-center/lower-left ambient positions, static-background choice and a personal message of at most 140 characters. Motion follows Reduce Motion; interactive forms keep their authored layout and readability. Existing Sundown appearance is the migration default.

JPEG, PNG and HEIC imports use the system file picker. Curfew keeps an optimized owned copy, with aspect-fill cropping and adjustable focal point, so moving the original is safe. Text and controls always have a readability treatment. The saver shares the selected background; sharing the personal message is a separate opt-in. Appearance and Sunrise preferences stay local and outside account-synchronized settings.

## Native companion

The optional macOS 26 Curfew.saver uses ScreenSaverView and the same absolute-time rendering contract as the app. It supports preview/fullscreen lifecycle and releases render resources on stop. Outside an occurrence it shows background/clock/permitted message. Missing or expired occurrence data never invents restriction status.

A small versioned presentation export includes only appearance, relevant occurrence timestamps and an optimized image rendition. Module-specific ScreenSaverDefaults exchange requires actual host-process readback acceptance. The host is not assumed to inherit App Group access. Image payloads are validated before decode, limited to 3840 pixels on the longest edge and 2 MiB encoded, and published on appearance changes rather than ticks. Reflection drafts, journals, accounts and recovery controls never enter this export.

After reflection is submitted or skipped, 60 seconds without input may begin the handoff. Editing, confirmation holds and recovery flows prevent it. Rest now is an explicit alternative. Curfew settles contextual content into the ambient composition, requests the publicly resolved system screensaver via NSWorkspace, and preserves native hosts/drafts. Returning refreshes time and actual restriction authority before permitted content returns. Authentication interruptions resume the current composition. System gamma fade and matched composition coordinate the handoff; macOS retains compositor/authentication control.

Installation, system settings selection, version mismatch, update and removal are explicit actions. Curfew never rewrites the user's selected saver or simulates idle input. If launch or the companion is unavailable, interactive Curfew remains usable with an appropriate setup action.

## Sunrise wake

Automatic wake starts disabled. The default lead-in is 30 minutes, adjustable from 5 to 60; the same interval drives visual progression and wake scheduling. External power is required unless battery operation is separately enabled. Presentation may hold the display awake until five minutes after scheduled unlock, ending earlier when dismissed or disabled.

Display wake and whole-system wake are distinct operations. The running app requests display activity and a bounded display-sleep assertion. The authenticated existing helper schedules one owned kIOPMAutoWake event for a sleeping Mac, never power-on from shutdown. A typed helper-local plan carries occurrence, timing, power policy and scoped cancellation identity. Replacement, deduplication, durable recovery and schedule/timezone/DST/power reconciliation prevent stale plans. Disabling/uninstalling cancels owned events and releases assertions.

AC-only plans cancel when a power-source change is observed and recheck power before lighting/holding the display. Unplugging an already sleeping Mac may still allow an earlier scheduled system wake; battery exclusion must still prevent unattended display hold. Scheduled, helper unavailable, rejected and battery excluded states remain distinct. Closed lids, off monitors, FileVault and authentication retain normal platform limitations; an accepted request proves neither monitor illumination nor visible Curfew rendering. Personal backgrounds receive gradual tint/lighting rather than abrupt replacement. Global brightness, gamma and monitor configuration are untouched.

## Acceptance and rollout

Implementation proceeds through local preferences/shared scene, customization, actual native companion exchange/handoff, and Sunrise helper/display delivery. Each substantive increment needs behavioral failing-first tests, docs, formatter and strict lint. Final acceptance includes actual global native accessibility with no suppressed findings or temporary diagnostics, native lifecycle and physical sleep/wake, authentication return, two displays, VoiceOver/keyboard/workspace restoration and recorded motion/rendered composition across appearance and accessibility choices.

Source, automated tests, screensaver-host acceptance, API success, physical machine wake, illuminated monitors and visible rendering are separate evidence. Production activation and public installer publication remain held. App and companion artifacts require independent version checks; uninstall and feature disable must restore ordinary platform behavior. Reversible commits and local-only preference defaults permit rollback without altering enforcement or remote protocols.

### Scheduled wall clocks and daylight saving

Configured lock and unlock times are local calendar clock values. Resolve those values before adding elapsed extension minutes; a missing spring-forward clock preserves its smaller components at the next valid time, and a repeated clock uses its first occurrence. If an elapsed extension overtakes the originally resolved unlock, select the next configured unlock clock after the actual lock. Explicit saved day offsets retain their original reference day. The same schedule resolver supplies enforcement and Sunrise, so presentation cannot invent an independent release time. This date correction is independently reversible; reverting it restores the previous transition-day drift and requires repeating schedule and Sunrise regression acceptance.

## Runtime composition and recovery

Normal app launch explicitly creates the optional rest runtime after the demo and loaded-test-runtime guards. Appearance changes and the existing display clock reconcile companion publication and Sunrise independently of enforcement. The companion receives bounded owned image bytes and a fresh readback nonce; a preferences write is not proof that the screensaver process read it. Activity and display assertions have separate owners so cleanup cannot consume another policy’s retained retry token.

The privileged helper composes its authenticated Sunrise operations with a fixed flavor-specific event owner and a private root-owned journal beneath `/private/var/db`. Unsafe or unavailable storage disables optional scheduling while restriction enforcement continues. Disable Sunrise to cancel its owned event and release its display hold; rollback removes the optional runtime composition without changing restriction authority. Installed-helper recovery, actual host exchange and physical power behavior remain separate acceptance requirements.
