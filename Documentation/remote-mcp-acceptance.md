# Remote MCP acceptance evidence

Snapshot: 2026-10-12. This is an evidence ledger, not a claim that the full
download-to-phone-control flow is released. The later signed dev update and
restart were explicitly authorized. No new lock or unlock was sent.

## 2026-10-13 installed enforcement update

The corrected company-signed `studio.hypertext.curfew.studio.dev` build was
installed at `/Applications/Curfew Studio Dev.app` and restarted with
`open -g`, without a foreground UI test or another remote command. Its
`app.launched` audit at 12:57:55 Pacific records `enforcementArmed: true`,
`setupComplete: true`, `accessibility: granted`, `phase: working`, and
`autoShutdownEnabled: false`. Its enforcement health changed from a one-second
startup helper probe to `active` at 12:57:56. The prior installed build's
09:36:17 launch audit had `enforcementArmed: false`. The current local schedule
reported working until 6 p.m. before restart. This verifies the fixed native
launch path, but not a second physical remote-lock execution; the one authorized
command had already expired and was not replayed. The replaced app remains
recoverable at `/Applications/.Curfew Studio Dev.pre-enforcement.app`.

## 2026-10-13 authorized lock diagnosis

The user authorized one five-minute remote lock. Codex Staging listed Studio
Dev Mac online with a report received at `19:29:40Z`. The single device-specific
command `c864797a-33a8-476a-92d0-a9d472316ee0` queued at `19:30:51Z` and
returned an **applied daemon receipt** at `19:31:09Z`, with deadline
`19:36:09Z`. No second command or unlock was sent. The native process logged
the durable deadline at `19:31:10Z`, but subsequent live reports at `19:31:45Z`
and `19:32:47Z` said `working` with a null lockout deadline. An applied receipt
therefore did **not** prove active UI enforcement.

Source and build settings identify the cause: `StudioDev` compiles with `DEBUG`,
and `CurfewLaunchBehavior` treated all Debug builds as display-only unless
`CURFEW_ENABLE_ENFORCEMENT=1` was set. The signed installed app had been launched
normally without that variable. The launch policy now arms the verified Studio
Dev bundle by default while keeping personal Debug and loaded test hosts
disarmed. Environment-only test markers and Debug demo fixtures cannot disarm
the signed Studio Dev app; the shared test-host predicate also requires a loaded
XCTest runtime for both signed Studio Dev and Release, preventing environment
markers from suppressing their event tap or related enforcement effects.
`CURFEW_FLAVOR` cannot make a personal Debug app arm.
The old command expired; the signed update has since been installed and its
armed startup verified, but a new command must not be sent without separate
authorization. This change
does not affect OAuth, coordinator delivery, or protocol schemas.

## Earlier installed-dev and Codex verification

At `2026-10-13T06:13:31.508Z` (October 12, 23:13 Pacific), the actual Codex
staging `list_devices` tool reports Studio Dev Mac **online**, with a fresh
native report observed at `06:13:30Z`, phase `unknown`, and null lockout deadline.
The installed app visibly says Curfew is off. This verifies the installed Mac's
authenticated reporting through staging to Codex; it is not an enforcement test.

The user's last native sign-in succeeded: restarting the signed app consumed
those credentials without another browser sign-in. The defect was the missing
post-reauthentication transport restart. The installed correction explicitly
reconnects after successful same-account persistence, but a second interactive
reauthentication has not been performed just to exercise that callback.

The installed and built debug library SHA-256 both equal
`17f03dac6d9223f29772c59820e9b486a577e1056326d9758bf7cd5e01be201f`.
Deep strict signature verification passes under team `T95VDD3A4W` and bundle
`studio.hypertext.curfew.studio.dev`. The helper remains running as PID 27480
with its Mach endpoint active; no second repair was performed. No lock or
unlock was sent, no enrollment/replay state was reset, and no UI test ran on
the user's desktop. Final PR CI is tracked separately from this runtime proof.

Remaining acceptance is the rendered MCP panel, interactive Apple/TOTP/recovery
provider paths, measured sustained indexed-write usage, and any future physical
device-control test explicitly authorized by the user. Production downloadable
release credentials are not a blocker for this installed-dev/staging result.

### Earlier offline and quota observations (superseded)

- Native PR #51 and coordinator PR #50 are rebase-merged. Native CI run
  `38315375674` passed; staging deployment `38317602146` published Worker
  `0c4b8c08-2d64-482b-aed9-eabd80e77caf`. These checks do not prove the installed
  app's authenticated connection.
- The signed StudioDev build was installed at `/Applications/Curfew Studio Dev.app`
  and restarted. Deep strict signature verification passed. Its main executable
  SHA-256 is `74e4445ad50186533270e31b80a3ed50b524e715bdfd61a24363cfad8a040d12`,
  identical to the built executable. The signing team is `T95VDD3A4W` and the
  identity is `studio.hypertext.curfew.studio.dev`.
- The installed app reports remote control offline and background protection
  not connected. The existing launchd registration lacks the new `MachServices`
  endpoint, although the installed plist declares it. A running helper and exit
  code zero therefore do **not** establish authenticated XPC readiness. The old
  helper remains running; no unregister, bootout, or protected-state deletion
  was performed.
- A fresh Codex app-server status request reports `notLoggedIn`, with token
  refresh rejected as requiring OAuth authorization. This is not proof that its
  saved credentials are invalid: the latest staging log observation identifies
  D1 daily row-write quota exhaustion on both `/api/auth/oauth2/token` and
  `/api/auth/oauth2/authorize`. A direct unauthenticated authorization request
  returned HTTP 500. The earlier Chrome reconnect displayed
  `ERR_BLOCKED_BY_CLIENT` and timed out; the newly authorized hidden in-app
  browser also failed to open the OAuth URL, but ordinary sign-in loaded with
  both Apple and passkey buttons. An extension-specific diagnosis is therefore
  unproven. No browser protections were disabled or credentials transferred.
- At `2026-10-12T23:18:25Z`, quota exhaustion remains an active server-side
  blocker. Cloudflare documents a daily reset at 00:00 UTC (5:00 PM Pacific on
  October 12). Retry the saved connector credentials after reset before asking
  for another sign-in. The database-info command's zero-valued 24-hour metrics
  contradict the observed quota exception and cannot establish actual usage;
  attribution and post-fix indexed row-write measurements remain unverified.
  No billing changes, new database, or limiter bypass was used.
- Legacy helper migration needs a trusted maintenance path. An app-side off
  state or missing sentinel cannot establish absence of root-owned enforcement.
  Do not bypass the authenticated uninstall admission merely because the old
  registration has no XPC endpoint. Administrator-authenticated maintenance and
  a fresh browser sign-in surface were authorized by the user. Browser work
  stayed hidden. Background administrator authentication is unavailable;
  protected-state inspection and maintenance still need a user-handled macOS
  authentication prompt at a time that does not interrupt their work.

The earlier online listing and command receipt below are historical evidence,
not proof that the newly installed app or current Codex connector works.

### Post-reset verification and legacy repair admission

At `2026-10-13T04:10Z` (October 12 Pacific), the actual Codex staging
`list_devices` tool succeeds again. It reports Studio Dev Mac offline with a
stale native report, so connector recovery does not establish native recovery.
Codex also lists and retrieves `ui://curfew/status-and-devices` with
`text/html;profile=mcp-app`; the delivered panel uses host style variables.
This is resource delivery, not a rendered interaction or device-control test.

The user's administrator-authenticated inspection and a subsequent successful
read through Apple's `/usr/libexec/authopen` agree: the persisted remote deadline
expired at `2026-10-12T07:05:55Z`, the replay cursor remains 2, and there are no
pending results. The root `lockout-state.json`, root `lockout-deadline.json`, and
Studio Dev user-side `lockout-deadline.json` are absent under accessible existing
parents. The remote-command inbox has no entries. No state was deleted or reset.
These are point-in-time observations, not permission to unregister later without
rechecking after producers are quiescent.

Adversarial review conditionally approves a bounded signed-app reconnect path:
serialize repair; prevent local arming; pause and join account transport and local
command producers; check inbox emptiness and every authoritative deadline source;
recheck the inbox; await asynchronous SMAppService unregister completion; register
the bundled plist; and require authenticated XPC health before resuming producers.
Malformed, unreadable, active, unexpected-owner/type, or unrecognized legacy state
must block maintenance. Legacy admission must positively identify the supported
helper/flavor, not merely observe an unavailable RPC. Registration failure leaves
producers paused and protection visibly unavailable. Never restore an old state
snapshot over newer replay state. The reconnect operation is now implemented.
The first installed attempt completed removal but replacement returned macOS
error 1. Commands remain paused, and installed acceptance is still open.
The user also observed two generic authopen prompts; the correction uses a
Curfew-owned authorization context shared by both exact-path, read-only checks.
No authorization or state snapshot is persisted. UI explains the request.

At `2026-10-13T05:37Z`, Codex reported this Mac online but its last enforcement
report still claimed locked while the app was off. The native publisher used
the predicted schedule regardless of whether enforcement was armed. The fix
uses the existing protocol unknown phase and null deadlines when off without
an active durable record. Fresh installed reporting remains to be verified.

No lock, unlock, helper unregister, root-state write, or foreground test was used
for these observations. The user authorized the narrow administrator prompt.

## Verified staging evidence

On October 12 at 22:53 Pacific, the user completed the installed repair. Live
launchd inspection confirms a running Studio Dev daemon with the expected
Mach service endpoint; the installed app displays Background protection:
Connected. Its root-owned heartbeat advances. This is actual installed helper
acceptance, with no lock or unlock sent. The native account separately reports
rejected saved authentication and awaits user sign-in renewal; Codex listing
continues to work but reports the Mac offline with the old enforcement report.

The user observed Install/Connect/Reconnect cycling before the eventual prompt.
Installation now waits for authenticated connection health and shows Connecting
throughout. A stable Connect action covers unavailable registration/connection;
macOS approval remains a distinct action. The regression failed before this fix.

- Curfew Sync PR #42 was rebase-merged as `0d08fc64cf1c029cec0f18825bcd166dd37951aa`.
  Deployment run `38217175834` succeeded, publishing Worker version
  `6a600727-030b-4cda-bae8-113bd08c4209`. All 454 Worker and 7 DOM tests passed,
  together with typecheck, lint, formatting, and deployment checks.
- Live authenticated `list_devices` reported Studio Dev Mac online, with native
  status received at `2026-10-12T07:25:03.318Z`. Before deployment, the same
  listing incorrectly reported offline despite a fresh native heartbeat.
- Live authorization-server metadata advertises the account staging issuer,
  authorization and token endpoints, S256 PKCE, and CIMD support. This is
  discovery evidence, not proof of every OAuth or MCP conformance requirement.
- `launchctl print system/studio.hypertext.curfew.studio.dev.daemon` reports the
  registered Studio helper, 15-second run interval, and last exit code zero.
  Its exited state between scheduled runs is not an installation failure.
- Read-only lookup of the earlier authorized command
  `d5c310ce-7bcf-4ce8-9cd0-87c98ba3a50a` returns applied at
  `2026-10-12T07:00:55Z`, with deadline `2026-10-12T07:05:55Z`.
  The Studio app audit stream records a locked-to-working transition and
  lockout end at that deadline. Neither observation proves visible blocking.

## Remaining acceptance and provisioning

- Claude phone execution remains unverified. Codex was used because Claude was
  out of quota. Do not label that substitute as a phone test.
- Visible physical enforcement and remote-unlock behavior remain unverified.
  Do not issue another lock, launch UI automation, or take focus to obtain proof
  while the user's no-lock/background-only constraint remains active.
- No downloadable GitHub release exists at this snapshot. The Curfew repository
  exposes only `SPARKLE_PRIVATE_KEY` among repository secret names; its release
  workflow also requires Apple signing/notarization and Cloudflare credentials.
  A locally installed company-signed development build is not a notarized
  downloadable release. Do not export signing credentials or create replacements
  as an implicit audit step.
- The production coordinator's GitHub environment has no secret names configured,
  and `curfew-account.hypertext.studio` does not resolve from this Mac. Production
  account onboarding therefore cannot be claimed operational. Staging deployment
  does not satisfy production provisioning.
- Configurable Apple sign-in and its required TOTP flow need real provider
  acceptance; source configuration and automated tests are not provider proof.
- The coordinator still retains Dynamic Client Registration as a compatibility
  bridge for Claude. Its architecture documentation explicitly defers retirement
  until replacement client onboarding has real connector acceptance. CIMD
  discovery and Codex sign-in alone do not close that deprecation task.
- Device-neutral coordinator schemas and daemon-injected local/remote backends
  exist in source. That is an architectural foundation, not Windows runtime
  acceptance or full specification-conformance certification.

## Change and rollback boundaries

This audit changes documentation only: no app behavior, credentials, package
versions, migrations, permissions, or wire shapes. Existing automated coverage
stays unchanged. Revert the documentation commit if its snapshot is wrong;
update this ledger when stronger evidence becomes available rather than marking
the incomplete acceptance items complete.
