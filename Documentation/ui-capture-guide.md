# UI review captures

Run `just capture` on a dedicated macOS GUI session. XCUITest controls the desktop.
The extractor exports successful attachments for diagnosis but returns failure if
any capture assertion fails. A missing window never falls back to the desktop.

The preserved pre-redesign app is local at `build/baseline/Curfew.app`; original
screenshots are in `build/baseline/screenshots/`. Do not overwrite that directory.
New screenshots are extracted to `build/screenshots/` with stable names containing
surface, state, appearance, and size where applicable.

## Isolated launches

Keep the shell command running while inspecting the app (do not background it in
an ephemeral shell). For example:

```sh
CURFEW_DEMO_FIXTURE=1 CURFEW_DEMO_SCENARIO=settings \
CURFEW_DEMO_STATE=assistant-on CURFEW_DEMO_APPEARANCE=dark \
CURFEW_DEMO_SIZE=minimum \
build/Build/Products/Debug/Curfew.app/Contents/MacOS/Curfew \
-SUEnableAutomaticChecks NO -SUHasLaunchedBefore YES
```

These flags exist only in Debug. Demo models cannot arm enforcement and use
throwaway settings, history, deadlines, license preferences, helper registration,
and daemon RPC. They do not start sync, assistant sockets, shared request queues,
or widget writes. Assistant registration and uninstall confirmation do not change
real configuration or delete real data in demo mode. Copy Configuration explicitly
writes the clipboard and shows “Copied.” Do not activate a real license or follow
purchase links during visual review.

`DemoScenario` selects the surface. `DemoReviewState` enumerates permission,
helper, consent, license, sync, schedule, journal, and override variants. A synthetic
“ready” helper is visual proof only; it does not prove signed XPC connectivity.
`CURFEW_DEMO_SETTINGS_SECTION` accepts the stable Settings raw identifiers.

Settings uses 860×620 content at default and 760×520 at minimum. The main workspace
uses 1080×720 and 980×660. Setup has a content-sized minimum of 640×470. Full-screen
overlays match the display and do not have a separate minimum window size.

## Acceptance

Review actual images for clipped or missing controls, text density, contrast,
alignment, scrolling, and dominant actions. Share labeled before/after images
inline with the user. The full inventory is in `ui-state-review.md`; record gaps
rather than treating fixture availability as acceptance.

Exercise keyboard traversal and VoiceOver separately. Verify Reduce Motion and
Reduce Transparency on the real UI. Real grants/revocation, signed helper
registration/approval/connectivity, shutdown, authentic license activation,
assistant restart/config replacement, export filesystem errors, and uninstall
partial failure require independent system verification. No production release
is part of this change.

The first Settings treatment was rejected during visual review. The revision uses
neutral system surfaces, a compact sidebar, grouped General options, and disclosed
connection details. Capture the revised General at both sizes with missing
Accessibility access, not just the healthy fixture. No all-caps overlines or
letterspaced captions are permitted; check Journal date headings and calendar
labels as well as Settings. These presentation changes do not migrate stored data
or change approval or enforcement rules; rollback is confined to the UI views.

Shared primary, secondary, and link buttons now dim when disabled. Their press
feedback respects Reduce Motion. Verify empty-key Activate and gated setup Next
buttons visually, as well as their accessibility enabled state. This changes
presentation only; activation and setup gates are unchanged.

Lower-position captures must target the content pane rather than the navigation
sidebar. The capture harness verifies the vertical scroll value reaches the end;
when no bar exists, lower text and controls must fit within the pane. A failed
assertion invalidates the capture rather than silently producing a duplicate.

Native NSAlert confirmations are AX dialogs, not standard windows. Assert their
buttons and capture the dialog itself. Native Form disclosure rows require the
chevron hit target; verify the expanded accessibility value before capturing
technical details. Clicking the row center alone is not sufficient proof.

Capture the small warning countdown window itself, not XCUIScreen: the warning
layer is translucent and a full-screen capture includes unrelated desktop content.
The older full-screen warning images failed visual acceptance and are excluded
from the review gallery. Full-screen lockout captures target the asserted overlay.

Color review must compare Settings, Today, Schedule, and Journal together in both
appearances. Settings and workspace use shared canvas/sidebar roles; sky scenes
use shared control colors. A global palette change invalidates prior appearance
captures, so regenerate the matrix instead of mixing revisions in one gallery.

## Background-only work

When the user prohibits screen takeover, do not run UI tests, launch demo windows,
activate apps, manipulate macOS appearance/accessibility preferences, or capture
new screenshots. Builds and lint/format checks stay in the background. The normal
Xcode unit target uses Curfew as its app host, so use the hostless theme subset
when a strict no-window guarantee is required:

```sh
scripts/test-theme-background.sh
```

This generates `build/theme-background/`, symlinks the real source files, and runs
Swift Testing without `CurfewApp` or a GUI app host. Tests resolve symlink paths
when reading the repository's asset and presentation sources. The package uses
local CurfewKit sources and does not fetch external packages or write user data.
Record that this is a targeted subset and defer the full hosted suite. Do not
mix earlier screenshots into final-theme acceptance; recapture only when the
user authorizes foreground verification again.

## Background-only integration review

The user has stopped local screen-affecting verification. Do not run `just capture`,
UI tests, app-hosted unit tests, fixture app launches, hero capture, or video capture
on this Mac. Background format/lint, hostless packages, and `xcodebuild build` /
`build-for-testing` are permitted. Do not change permissions or register helpers.

Remote GitHub macOS runners are authorized for full hosted unit tests, interactive
UI checks and the screenshot matrix. Review the artifacts from the exact PR head,
assert account/Connections as well as the intended fixture state, and share labeled
images inline. Preserve the complete capture set outside this disposable worktree
before cleanup. Earlier captures are historical baseline evidence, not proof of
this integrated build. Keyboard/VoiceOver/Reduce Motion/Reduce Transparency and
signed helper flows need explicit evidence; list remaining gaps honestly.

Authenticated liveness integration: after authenticated arming or a matching heartbeat, legacy heartbeat files cannot keep that window alive. Unmigrated legacy windows retain file fallback. `AuthenticatedDaemonControlTests` covers persistence and binding to the current window; signed transport verification remains a remote/system acceptance gate.

Remote CI follow-up: screenshot extraction preserves the original failed UI-test exit status before attempting export. Authenticated liveness accepts a still-active local source during delayed stronger remote-deadline delivery, without changing effective authority or accepting unknown IDs. Regression checks cover both cases.

Fixture safety review: demo Settings uses an ephemeral account secret store and inert enrollment services; synthetic camera authorization cannot prompt TCC or open Camera Settings. Real account checkpoints, recovery keys, network enrollment, and camera access stay outside captures. ThemeConsistencyTests includes a fixture-wiring regression (14 theme/UI-source tests total). Assistant disclosure includes activity access.

Remote full-suite follow-up: package endpoints now derive app/widget service isolation from their bundle identity when app-only compilation flags cannot propagate into SwiftPM; standalone tools retain their explicit service flag. Setup tests inject Accessibility trust, consent-copy expectations use the approved shorter labels, and the browser uninstall test waits for actual enqueue under loaded CI. A compatibility `landing` symlink preserves the existing Pages root without deployment configuration changes.

Remote capture correction: fully fitting native forms may expose a scrollbar with zero range. Bottom captures now verify the lowest text/control bounds as well as scrollbar position, and accommodate native wheel direction; long clipped panes still fail. The initial remote General capture was visually inspected and shared inline; it is interim evidence until final-head recapture.
