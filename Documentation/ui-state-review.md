# UI simplification and visual verification

## Design contract

Use native Mac navigation and grouped controls with warm accents. Keep the sky on
Today, warnings, and lockout. State the outcome before technical details. Keep
permissions, delayed changes, AI data access, shutdown, and deletion consequences
visible at the decision. Preserve all enforcement policy and stored identifiers.

## State inventory

Each row defines the states to exercise, the information users need, and the next
action. Transitions must update while the window remains open.

| Surface | Reachable states | Required presentation and next action |
| --- | --- | --- |
| Setup | Welcome, schedule unreviewed/reviewed, budget, Accessibility missing/granted/revoked, confirmation, returning user | One step title and next action. Schedule review and live Accessibility trust still gate completion. Back and dismissal preserve existing semantics. |
| Today / menu bar | Setup incomplete, off/on, day off, countdown, warning, locked, extended, overridden | Show actual phase and next lock/unlock time. Readiness must not imply Curfew is on. Open Schedule for missing schedule; setup for incomplete setup. |
| Protection | Healthy, missing Accessibility, interrupted event tap, helper unavailable/unauthorized/stale/registration failed | Healthy is “Ready to enforce.” Degraded states explain the problem and appropriate repair, without suggesting Accessibility repairs a helper signature. |
| Background protection | Not installed/not found, needs approval, registered; connection ready/unavailable/unauthorized/stale/registration failed; operation error | Install, approve in System Settings, remove, or review troubleshooting as appropriate. Registration does not mean connected. Keep diagnostics available separately. |
| Startup | Login item not registered/not found, needs approval, enabled, operation failure | Open at login; approval action when needed; inline error on failure. |
| Limits | Weekly counts zero/nonzero, durations at bounds, budgets available/exhausted, reset day | Separate weekly allowance from duration. Explain extension versus override once. Preserve ranges and reset semantics. |
| Schedule | Normal/overnight/day off, pending stricter/weaker edit, applied confirmation | Work ends / Work resumes. Show effective time for pending edits and preserve cooldowns. |
| Warnings | Every warning stage, interval bounds | Distinct stage labels with minutes; normalization and ordering preserved. |
| Shutdown | Unavailable, off/on, scheduled/retry, denied/failed/completed | Delay shown only when enabled. State unsaved-work risk and permission requirement. Never execute shutdown in capture fixtures. |
| Assistants | Build disabled, off/on, Claude absent/unconfigured/replacement/configured, registration failure/restart needed, copied | Hide unavailable setup. Show journal read access and consent behavior. Copy feedback; refresh registration after action; disclose manual configuration. |
| AI requests | Queue/automatic/read-only; no pending/one/multiple; approved/denied/dismissed/execution failure | Review opens the real request. Preserve signed-request restrictions and default approval policy. Dismissal denies through existing path. |
| Calendar | Build hidden, Plus locked, permission unknown/granted/denied/restricted, events empty/populated | No disabled-build advertising. Permission action and accurate event count; no claim that events change schedules. |
| Devices / sync | Build hidden/local only, empty/local/remote devices; idle/syncing/synced/failed/iCloud unavailable | Hide nonfunctional setup advice. Show real sync status; readable error with details. |
| Plus | No key/empty draft/invalid key, lifetime/subscription active, expired, deactivated | Offer only build-enabled benefits. Activation disabled for empty key. “Active until” never “renews.” |
| Journal | Entries empty/populated, prompts empty/populated/editing; reflection text/rating/mood, missing required answers/submitted/skipped | Clear empty-state action; one submission action; preserve required-answer validation and local storage. |
| Activity / export | Empty/populated, Markdown/JSON/CSV, save cancelled/succeeded/failed | Explain empty history without implying failure. Preserve format choice; failure remains actionable. |
| Removal | Confirmation/cancel, helper removal failure, complete/partial data removal | Explicit irreversible consequences and retained cloud data; never perform deletion in capture fixtures. |

## Visual acceptance protocol

1. Preserve baseline captures outside the extractor's output directory before
   recapturing; include Settings tabs and lower scroll positions.
2. Capture actual windows in isolated Debug demo launches. Assert the requested
   window/state exists. Never substitute the desktop for a missing window.
3. Capture all redesigned destinations in light/dark and at default/minimum
   sizes. Capture distinct states once; repeat dense and critical states across
   sizes/appearances. Use deterministic fixture state rather than real accounts.
4. Inspect screenshots and share labeled before/after examples inline in chat.
   Keep a manifest of capture coverage and outstanding real-system verification.
5. Check keyboard traversal, VoiceOver, Reduce Motion/Transparency separately.
   Mock permission and helper states are visual proof only; signed-build system
   behavior needs independent verification.

## Release and rollback

No remote protocol, entitlement, or enforcement policy changes are intended.
Existing Settings identifiers retain their raw values where sections are renamed.
Rollback is a source revert; no persisted-data migration is introduced. Visual
acceptance stays open until the user reviews the screenshots. Capture artifacts
are local build outputs and are not committed as production assets.

## Review revision: ordinary-case labels

The initial Settings treatment was rejected as unpolished. The revision removes
its brand overline, uses neutral system surfaces and a compact sidebar, combines
General options, and discloses helper connection details. All forced uppercase
and letter spacing in Journal dates, weekly activity, and calendar labels have
also been removed in response to explicit feedback.

Verification for this revision (2026-10-10):

- Failing-first evidence covers typography, native keyboard navigation, retained
  Settings routing, minimum General layout, pre-activation assistant disclosure,
  and the warning capture container. The corresponding regressions now pass.
- All 300 unit tests (299 Swift Testing plus the destination snapshot XCTest)
  and 21 interaction UI tests pass. All six capture suites have passing runs
  against the revised presentation; captures were rerun after affected changes.
- The gallery at `build/ui-review/index.html` contains 160 current labeled
  screenshots, plus preserved baseline and earlier typography examples. Settings
  and workspace matrices cover both appearances and sizes; distinct fixtures,
  repeated critical states, consent sheets, and cancellation dialogs add coverage.
- The final critical-state/overlay run passes in
  `build/ui-capture-snapshot-final.xcresult`. Capture assertions read one frozen
  accessibility snapshot to avoid stale live-element matching. Warning captures
  contain the actual timer; rejected desktop captures have been replaced.
- SwiftFormat and strict SwiftLint pass with zero violations. Debug build passes
  (`/tmp/curfew-final-debug.log`). Release remains blocked before compilation:
  the Mac Team Provisioning Profile excludes the configured Apple Development
  certificate (`/tmp/curfew-final-release.log`). Signing was not changed.
- Captures were inspected for clipping and action visibility. Expanded helper
  details at minimum height scroll normally; collapsed General keeps Setup in
  view. Nine baseline screenshots remain, with incomplete lower-position coverage.
- The user authorized foreground captures. No production release is included.
  Full visual acceptance, signed system checks, and assistive technology exercises
  remain open as detailed below.

## Navigation and capture follow-up

A retained Settings window could remain on General after a second Manage AI Access
request. The UI regression test reproduced that failure before sidebar selection
was synchronized with the shared destination. Native List selection restores up
and down arrow navigation; its test failed with the former button-only sidebar.
Both tests and minimum-position General coverage pass in the focused rerun.

Lower-position captures now target the detail pane, not the workspace sidebar,
and assert the bottom scroll value or that all lower content fits. The previous
silent scrollbar fallback is removed. This affects test evidence only and does
not alter app scrolling or persistence. Revert the presentation and capture
changes to roll back; no data migration or distribution change is introduced.

The first corrected capture matrix passed all 48 screenshots, but image inspection
found a separate degraded-General density issue. A new minimum-window regression
failed with Review Setup below the visible pane. Removing the duplicate helper
attention row keeps the action visible while retaining Troubleshooting details.
A second failing UI test showed assistant read-access copy appeared only after
activation; it now appears before activation. Both regressions pass in the final
combined run. All captures affected by these revisions have been regenerated.

## Coverage still requiring acceptance

The fixture matrix is broad visual evidence, not an exhaustive certification of
every inventory row. Remaining visual/system exercises include each warning
stage; granted/expired extension and override presentation; assistant replacement,
restart, registration and execution errors; calendar restricted/populated states;
remote device data; license deactivation; export outcomes; uninstall success and
partial failure; and real VoiceOver/Reduce Motion/Reduce Transparency runs.
Existing behavior tests retain policy coverage, but that is distinct from these
visual and system checks. User acceptance of the revised design remains open.

## Unified theme revision

Feedback identified color inconsistency across Settings and the workspace.
Settings now uses the same warm gray canvas and sidebar as Schedule and Journal.
Shared ink and secondary text are darker in light mode and lighter in dark mode;
clay links, native control assets, and filled buttons are coordinated semantic
roles. White button labels use a deeper fill instead of the lighter dark-mode
link color. The sky remains atmospheric, while its controls use those same roles.

`ThemeConsistencyTests` failed first for text contrast and diverging Settings/sky
colors, then passed after consolidation. It resolves both appearances and checks
4.5:1 contrast for body, secondary text, and links across the three shared content
surfaces. This does not certify all composited or native system surfaces.
Enforcement, permissions, stored settings, and approval rules are unaffected.
Rollback is a source and AccentColor asset revert. Revised capture verification
is recorded below when complete; pre-revision examples remain in
`build/ui-review/before-unified-theme/`.

## Background-only completion of shared theme

The user clarified that UI contrast was affected, then prohibited further UI
automation or foreground activity. The selected-row regression was traced to a
foreground-style override on the common Settings ancestor. A failing regression
was observed before removing it; native selection now owns selected text color.
Supporting Settings text explicitly uses the contrast-checked secondary role.

The warning timer and older lockout view no longer embed RGB values. They use
shared atmospheric text, glow, and night-gradient roles. The warning capsule's
opaque night gradient prevents desktop colors from changing its background.
Setup's supporting text and reflection form labels also use shared roles.
Reflection inputs use a dark backing in both modes (opaque under Reduce
Transparency); selected mood/rating controls use the shared filled-action pair.
The evening reflection card uses the opaque night surface. Hold progress uses a
dark overlay so the label keeps its contrast as confirmation fills. These are
presentation changes only; required answers, hold duration, cooldowns, submission,
and permission boundaries are unchanged.

Native AccentColor assets are checked against the shared filled-action role;
links have a separate appearance-adaptive role so dark-mode link brightness does
not weaken white-label button contrast. Runtime content still comes from models.

Final background verification (2026-10-10):

- `scripts/test-theme-background.sh`: 12 tests pass in 3 suites. This compiles
  symlinks to the real theme/typography and CurfewKit sources in a generated Swift
  package, without the app entry point or a GUI test host. It covers four shared
  surfaces, body/supporting/link/warning text at 4.5:1, filled-action labels at
  4.5:1, atmospheric text/icons across night gradient stops, native accent asset
  consistency, reflection input contrast on a worst-case white backdrop,
  hold-progress label contrast, disabled/Reduce Motion feedback, and typography. A failing-first
  run caught the remaining two view-level RGB color definitions before removal.
- SwiftFormat lint and strict SwiftLint pass with zero violations.
- Debug build passes (`/tmp/curfew-theme-background-debug.log`).
- Release build remains blocked by the provisioning profile/certificate mismatch
  (`/tmp/curfew-theme-background-release.log`). No signing changes were made.
- The earlier hosted run passed 302 unit tests and 21 interaction tests before
  the final atmospheric token consolidation. Those counts are historical proof,
  not a claim that the full hosted suite was rerun for the final source.
- No UI tests, screenshots, app launches, or permission changes were performed
  after the user requested background-only work. Full hosted unit tests are
  deferred because their normal target uses Curfew as its app host. Final visual,
  keyboard, VoiceOver, Reduce Transparency, and composited sky contrast remain
  unverified. Numerical tests do not substitute for visual acceptance.

Existing gallery screenshots predate the final background-only changes and must
not be represented as screenshots of this final theme. Rollback is limited to
presentation sources, the AccentColor asset, tests, and the generated test helper;
there are no enforcement, persistence, permission, or wire-format changes in this
color pass.

## Integration follow-up

The verification results above describe the pre-rebase color pass. The integrated
branch also includes current main's account enrollment/recovery, presence,
protected-work and task-browser states. These panels now use grouped Settings forms
and the existing semantic palette. Camera images/privacy stay visible; destination
mapping and protected application/process lists sit behind disclosures.

New helper states distinguish registration, authenticated connection and storage
failure. Damaged local transport persistence leaves signed remote and legacy
policy evaluation running, but local RPCs report failure. A verified terminal wake
state may unlock the UI while durable completion retries; the local deadline is
removed only after root acknowledgement. Remote authority remains independent.
These are substantive integration changes, so the color-only rollback note above
must not be applied to daemon/account integration files. See the current integration
sections in `todos.md` and `todo-test-matrix.md` for coverage and remaining acceptance.

## Contradictory combinations reviewed

Today can retain a scheduled locked phase while protection is off. Its hero must
not say Curfew is active in that combination; its action remains Turn on Curfew.
A day off still says no curfew is scheduled. Finish Setup routes to the walkthrough
so a pre-existing Accessibility grant cannot skip schedule review.

Reopening completed setup is a review, with actual on/off status and Done. Revoked
Accessibility access shows the repair control; Done only dismisses. The first-run
completion gate remains schedule review plus the live permission grant.

Assistant consent shows the action derived from current settings and queued
arguments, including overnight unlock and policy delay. Unreviewable requests and
unavailable extensions disable Approve; Deny remains available. Legacy overrides
must use the in-app cooldown, reason, and hold flow. A verification failure names
the failed background connection and recommends an official reinstall, without
calling the user's app a rejected build. A keyboard interruption with permission
present no longer sends the user to grant the same permission again.

Pending schedule previews also disclose cancellation or replacement of the queued
weekly change and list discarded pending weekdays. The 24-hour delay is a minimum;
a weaker change cannot apply during active lockout. Account enrollment hides the
stopped legacy iCloud service and device registry rather than presenting stale
healthy rows. Calendar refresh reads current authorization before reading events;
revocation clears cached event content and restores the permission repair row.
Calendar advice does not suggest an extension with no eligible extension action.

### Account readiness consistency after main integration

Remote locks require both a fresh daemon heartbeat and an authenticated ready connection, while Studio Dev still yields to a live higher-priority Curfew owner. Settings refreshes signed status on opening, activation, and the existing heartbeat interval. Pending approval opens the macOS approval pane; installed connection failures route to General; installation is offered only when needed. Account messages describe an unchanged schedule instead of claiming protection is active.

Hostless coverage: `PrivilegedHelperManagerTests.remoteReadinessRequiresAuthenticatedConnection` rejects unavailable, unauthorized, stale, and failed registration despite a fresh heartbeat file. `PresentationStateTests` checks recovery routing and copy. The new assertions failed before the fix; CI retains full app behavior and screenshot checks. No local UI execution or app launch. This changes readiness presentation and recovery routing, not enforcement rules, persisted identifiers, or the wire format. Rollback is the readiness/copy change; signed helper and real macOS approval verification remain separate.

Account rejection copy now distinguishes expired sign-in, explicit server access denial, and local remote-update failures. A version without background protection explains availability without directing to a hidden General section. `AccountStatusPresentationTests` exercises actual status-to-copy resolution in the hostless suite; both regressions failed before correction. The existing sync status enum is extracted unchanged for hostless coverage, with no identifier or wire changes.

Final recovery-copy review: Today’s off state describes following the local schedule without promising that independent remote controls cannot lock the Mac. Uninstall failure uses the product action as its heading, with specific diagnostics retained. Unavailable remote locks offer Get Curfew using the shared production website origin rather than a duplicated URL. `PresentationStateTests.offAndRecoveryCopy` failed first; the unavailable-feature screenshot asserts its website action. Enforcement, uninstall order, and account behavior are unchanged.

### Menu-bar contrast and actual popover coverage

The menu-bar countdown now uses the same tested text scrim and supporting-text
role as Today. Completed setup offers “Review Setup”; unfinished setup offers
“Finish Setup.” The status item exposes its current status to accessibility.
These changes do not alter enforcement or extension behavior.

Remote UI checks open the actual status item and assert its identified 320-point
popover before capture. Light/dark captures cover ready, missing permission,
interrupted keyboard protection, and helper verification failure. The popover has
one fixed width, so workspace minimum/default resizing does not apply. No desktop
or replacement view is accepted. Local app launches and UI checks remain disabled.

An explicit off-plus-warning fixture keeps the scheduled extension flag true while
Curfew remains disarmed. Both remote interaction and capture assertions require
the menu to say “Curfew is off” and offer no extension action, preventing an
inapplicable menu action from consuming the weekly budget.

Remote capture regression: locked evaluations retain a zero-minute display value.
Today now checks the phase explicitly before showing a countdown, so an off Mac
with a past scheduled lock shows “Curfew is off. Review your schedule.” instead
of “0:00.” The state-consistency capture runs first to expose fixture failures
early. `PresentationStateTests.lockedCountdown` and the remote capture both cover
this presentation-only correction; enforcement and stored schedules are unchanged.


Returning setup review now derives its content from the saved setup state instead
of the walkthrough cursor. A revoked Accessibility grant immediately shows its
repair action; completed review hides the first-run checklist and never arms
protection. The remote missing-permission capture exposed a real blank-panel
regression. `PresentationStateTests.setupReviewContent` and the setup-review
capture states cover the correction. CI runs the new state matrix in a separate
preflight before the full capture sweep, preserving failure diagnostics early.
No permission, persistence, enforcement, or onboarding completion rules changed.
Rollback is limited to presentation and CI ordering.

The preflight uses ten independent XCTest methods, one per state family. A failure
in one state does not prevent the other families from being exercised; each still
asserts its own screen and state before attaching an image.

AI extension exhaustion is distinct from a warning stage that offers no extension.
The consent preview reads the live weekly allowance and says “No extensions left
this week.” Approval is disabled while Deny remains available. The isolated
`assistant-exhausted` fixture reproduces a warning with zero allowance in light
and dark appearance at default and minimum sizes. Core grant application must
also consume the tracker successfully, including automatic approval and a budget
that becomes exhausted after the sheet opens. No wire or persistence shape changes.

The previous MCP grant path discarded the tracker's rejection. It now returns
without adding minutes or recording a grant when consumption fails, refreshes
the allowance, and records the denial. Manual and automatic actual-model tests
failed first remotely; a positive grant case retains normal slot consumption.
Risk is limited to refusing an invalid grant that should already have been refused.
Rollback must retain the budget guard; UI copy and fixture changes are separable.
No schedule, cooldown, licensing, or protocol rules are changed.
