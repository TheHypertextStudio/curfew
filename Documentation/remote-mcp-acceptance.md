# Remote MCP acceptance evidence

Snapshot: 2026-10-20. This is an evidence ledger, not a claim that the full
download-to-phone-control flow is released. Historical sections below retain
their point-in-time wording; the latest evidence takes precedence.

## 2026-10-20 installed-dev and staging acceptance

The company-signed `/Applications/Curfew Dev.app` now contains the native
browser-attempt lifetime correction from [native PR #87](https://github.com/TheHypertextStudio/curfew/pull/87).
Its matching privileged helper is running. A previous attempt's delayed
cancellation cannot close a newer sign-in; the deterministic regression was
observed failing before the correction and passing afterward.

The actual full app-host native result passes all 1,054 tests, with no failures
or skips. The 44 focused native regressions, shared-package tests, all 142
repository script tests, formatting, strict lint, workflow lint, and signed
Debug build also pass. The installed artifact and the verified canonical
source match. These results are separate from the broad hosted graphical and
marketing-capture checks, whose completion is not claimed here.

[Coordinator PR #88](https://github.com/TheHypertextStudio/curfew-sync/pull/88)
aligns consent readiness with the same five-minute security window enforced
on submission and routes expired signed requests to a separate restart page.
Successful grant redirects still take precedence. Better Auth and its five
directly used companion packages are aligned on 1.7.12; the official MCP Apps
extension SDK is 2.0.3. All 739 Worker, 181 browser, and 32 Node checks pass,
along with types, lint, formatting, local migrations, and deployment dry-runs.
The staging-home configuration regression was observed red before its
correction and green afterward.

The owner explicitly approved this patch's one-time local staging deployment
after GitHub billing prevented the protected CI deployment from starting.
The upgraded immutable version was checked against the retained database,
coordinator namespace, declarative export, all public settings, and provider
secret-name inventory before activation. The canonical staging home URL is
preserved. Cloudflare accepted the minified candidate with 405 ms startup;
no limit was increased and no deployment-check bypass was used. A failed
incomplete export declaration never became active. Native deployment format
was used after the cf strict dashboard comparison rejected representation-only
binding differences; a passing strict-mode upload is not claimed.

Independent post-deployment Codex access through the saved OAuth grant succeeds.
A subsequent actual read-only device result contains a native report received
after activation, proving that the installed Mac reported through the upgraded
backend: activation was at `18:48:58.583582Z`, and the report was observed at
`18:49:53Z` and received at `18:49:54.604Z`. The Mac is online, on a day off,
and has no active lockout. No lock,
unlock, repeated recovery setup, production deployment, or foreground desktop
interaction was performed for this acceptance.

The current implementation composes Better Auth MCP and CIMD with the
`mcp-2026-07-28` metadata profile and SDK tests exercising that protocol.
Device-specific and all-device lock scopes are distinct; unlock permissions
remain separate. The MCP App uses the official extension SDK, and the daemon
composes local and remote command backends behind the shared backend interface.
The versioned contracts remain independent of macOS UI and helper machinery.
The live claimed-HTTPS callback association includes the installed canonical
application identifier and matches its signed associated-domains entitlement.
This does not claim an implemented Windows client.

The owner previously completed the real native OAuth callback, confirmed the
Apple callback correction worked, and finished authenticator and recovery-code
setup. Those completed steps were not reset or repeated. The owner accepted
desktop Codex verification instead of another phone walkthrough. A fresh
interactive sign-in has not been observed on the latest canonical installation;
saved-grant connectivity and deterministic callback tests do not establish that
specific interactive acceptance. The healthy enrolled app does not expose its
reconnect action unless reauthentication is required; do not invalidate its
working credentials merely to manufacture a retry.

Delivery is the reviewed native/coordinator PRs, not a general-availability
release. Fresh interactive canonical-app acceptance and the outstanding hosted
graphical scope remain explicitly unverified. Historical physical enforcement
evidence below is not authorization for another control command. Public app
publication and Plus/live-billing activation remain separate withheld work.

## 2026-10-13 native reconnect diagnosis in progress

Hosted CI on the test-only PR #61 head `08980730` reproduced the reconnect
regression: after a successful browser callback but failed native connection,
the controller showed the generic expired-sign-in instruction. The existing
enrollment and refresh token stayed intact. The proposed fix distinguishes
that post-browser failure from cancellation and records only OAuth stage and
HTTP status in unified logging under the `account-oauth` category. It does not
log authorization codes, tokens, account identifiers, response bodies, or
the sign-in URL. The installed signed app has not received this fix yet; a
green hosted run and a single same-account reconnect are still required.

For a user-initiated reconnect, inspect the last ten minutes without opening
another browser window or changing device state:

```sh
log show --last 10m --style compact --predicate 'subsystem == "studio.hypertext.curfew" && category == "account-oauth"'
```

An accepted callback followed by token endpoint, userinfo, or credential
commit failure identifies the native boundary; a missing callback points to
the browser handoff. This is diagnosis, not evidence that the app is online.
Rollback retains existing enrollment and keys by reinstalling the prior signed
Studio Dev build; do not erase or re-register the device. No lock or unlock is
needed for verification.

## 2026-10-13 read-only connector follow-up

At 22:17 UTC, Codex Staging's read-only `list_devices` call succeeded and
returned Studio Dev Mac, but it was offline with its last enforcement report
received at 21:56:08 UTC. The signed Studio Dev app was not running at the time
of a read-only process check; the root daemon was running. No app restart,
window, lock, or unlock was caused by this check. A phone-side Codex device
list is still pending. The status-mirror fix is source-only until hosted CI and
signed installation; it does not explain why the installed app stopped.
Review of that fix found four status edge cases. The same change now arbitrates
two same-flavor writers so a live lock owner's observation wins, publishes an
unavailable state during helper maintenance, suppresses a healthy-lock claim
when protection is degraded, and retains the configured time/hours countdown
mode. Package tests exercise the status file and real local MCP handler; the
native maintenance regression must run in hosted CI. This does not change
coordinator command delivery, lockout authority, or remote OAuth state.

## 2026-10-13 signed physical-lock acceptance

The user separately authorized one final five-minute lock after the signed
Studio Dev update reported enforcement armed and healthy. Codex Staging listed
Studio Dev Mac (`dfdde4c3-cffc-4c76-9e6a-ba2568b8f89c`) online. The one
device-specific command `29ef25c6-66c2-42b9-a0d7-3f4947cec785` returned an
applied daemon receipt at `21:39:09Z`, with deadline `21:44:09Z`. At
`21:39:16Z`, staging reported the device locked. The installed app's audit
stream recorded `lockout.started` and active lockout health; read-only
WindowServer inspection showed Curfew's opaque full-screen, on-screen window
at layer 1000. At the deadline, staging reported working, the app recorded
`lockout.ended`, and the full-screen window disappeared. This is physical
enforcement and natural-release evidence for the installed signed app and
Codex staging connector, not merely a queue receipt. No additional lock or
unlock command was sent.

The user also confirmed after the restart that the morning reflection accepts
typing and its buttons work without resetting. This closes that specific
installed-UI regression, not all first-use or accessibility acceptance.

Curfew PR #57 was rebase-merged as `c5fb4f69087f215024b14d17839677d599796a58`.
Its native CI format/lint/test/build and documentation jobs succeeded; the
separate screenshot capture job remained in progress when last inspected. A
physical lock is now proven, but Claude-phone execution, remote unlock, and a
downloadable production release are not. The user has not authorized another
device-control command; do not repeat this test without fresh direction.

`curfew-ctl status` returned `working` during that lock because it evaluates
the saved schedule rather than reading the app's settled state or the daemon's
remote deadline. Local MCP's `curfew_status` and
`curfew_get_time_remaining` use the same schedule-only calculation. These
local readouts must not be treated as proof of actual enforcement until they
consume a fresh observed-state source that includes remote commands, overrides,
and whether this app owns enforcement. Do not patch only the remote-deadline
branch: a live release or another Curfew flavor can make that answer wrong.

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
- Visible physical enforcement is verified for the installed signed Studio Dev
  app through Codex staging as recorded above. Remote-unlock behavior remains
  unverified. Do not issue another lock or unlock, launch UI automation, or
  take focus to obtain further proof without fresh user direction.
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

This ledger update changes documentation only: no app behavior, credentials,
package versions, migrations, permissions, or wire shapes. Existing automated
coverage stays unchanged. Revert the documentation change if its evidence is
wrong; update this ledger when stronger evidence becomes available rather than
marking the incomplete acceptance items complete.
