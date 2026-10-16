# Curfew Implementation TODOs

## Production publication

- [-] Publish the public marketing frontend through native Astro and Worker
  commands independently of Apple/native release readiness. Preserve account
  entry, service routes, documentation, downloads and genuine update-feed bytes;
  accept the actual public site after separately approved cutover.
- [x] Remove the standalone Pages-only website publication workflow and its
  custom preparation/verification wrapper. Use native deployment history and
  retain recorded native versions and routing baselines for explicit recovery.
- [x] Remove website-only domain and provider-inventory wrappers. Keep production
  Cloudflare credentials out of PR validation and use native operator commands
  for approved domain administration.
- [x] Install approved Developer ID app/widget provisioning profiles for signed
  candidates, bind archive/export to their UUIDs, and remove job-owned files.
- [ ] Resolve Apple identifier ownership and supply the issued production
  profiles; verify archive, signing, notarization, and native acceptance.
- [x] Retain the browser-validated static website with a content/configuration
      identity; reject obsolete Pages runtime files.
- [x] Provide manual activation of matching signed candidate and website bytes,
      with fresh private owner acceptance, website TLS, prepared services,
      immutable release assets, and live feed/redirect/retirement checks.
- [ ] Complete production provider, device, assistant, billing, licensing, mail,
      and update acceptance; publish the approved artifacts and verify the cutover.

## Signed emergency-release timestamp persistence

- [x] Sign emergency releases using the timestamp precision stored in their existing
  JSON record, so a release remains verifiable after saving and loading at a second
  boundary. Preserve the signing contract, record format and grant expiry bound.
- [x] Cover deterministic boundary timestamps and validate the native checks before
  integrating the website and documentation changes.

## Website domain preparation

- [x] Activate the public website on the new main domain and permanently redirect
  public old-domain paths and queries, retaining existing account access and
  native update-feed state independently of the signed app release.

- [x] Document Worker hostname setup through the shared hosting configuration and
      native deployment and explicit route/DNS reversal for approved recovery.
      Preserve native/backend release requirements.
- [x] Attach and activate the new hostname with verified DNS and TLS before the
      coordinated production cutover; retain the existing public hostname for its
      permanent redirect.

## License deployment configuration

- [x] Require a verified shared deployment artifact for license cf builds,
  retain the existing Worker/account/KV identities, and expose configuration
  provenance on health responses without changing the health payload.
- [x] Validate license Worker behavior, types, artifact identity, and the same
  cf build/prebuilt dry-run in CI before deployment.
- [x] Isolate license test configuration and discovery when CI checks out the
  app beneath the backend repository; never inherit the enclosing test runner.
- [ ] Disable the independent license Git build before coordinated activation;
  deploy the approved artifact with retained signing secrets and verify its
  health identity, licensing, and Stripe delivery on the new hostname.

## Public legal policies

- [x] Standardize operator, official contact, eligibility, authorized content use,
  adult purchases with organization authority where relevant, consumer rights,
  and source-backed privacy/retention disclosures including local MCP activity
  and device-attributed summaries. Current public contact links distinguish
  product help and general inquiries from official Studio legal/privacy notices.
  Retention describes scheduled batch cleanup without assuming a cron interval.
  Preserve previous policies in native `/legal/history` routes and retain HTML
  aliases. Terms changes use a 30-day existing-user notice; lifetime/MIT/refund
  rights remain intact.
- [ ] Publish policies and deliver the material-change notice through account
  communications before relying on revised Terms for existing users. Verify
  the legal mailbox and deployed routes separately from local site checks.

## Cross-browser account callback (2026-10-13)

- [x] Accept a user-clicked `account-oauth/callback` continuation using the
  already registered, environment-specific scheme only for an exact pending
  state. Convert it to the claimed HTTPS callback before the existing native
  exchange; leave the PKCE verifier in memory and Docket routing separate.
  Headless CurfewKit tests cover malformed and cross-environment URLs; an
  app-host regression covers pending-state consumption and Docket isolation.
  No wire format, entitlement, account data, or app version changed.
- [ ] Run the app-host regression on hosted CI, install a signed update, and
  prove one cross-browser Studio Dev sign-in reaches the same enrolled Mac and
  reports online through the staging connector. Local headless tests/builds
  cannot establish that live callback. Rollback is the prior signed app; do
  not erase the enrollment or repeat authenticator/recovery setup.

## Native reconnect after browser sign-in (2026-10-13)

- [-] Keep a rejected account credential terminal until same-account
  reauthentication succeeds. A rejected transport must stop publishing status
  and ignore stale callbacks; ordinary settings or license reconciliation
  must not restart it. Preserve pending encrypted changes across the explicit
  reconnect. Reject invalid wake updates and failed local release writes
  without terminating otherwise valid credentials. This prevents a completed
  browser sign-in from appearing to reconnect a Mac while its status channel
  remains stopped, without turning local update errors into sign-in loops.
- [-] Keep coordinator access denial terminal until the owner reviews this
  Mac’s access and explicitly retries its saved enrollment. Settings offers
  that retry without opening sign-in or registering a new device; the
  coordinator must still authorize it. Confirm the installed app’s recovery
  path before marking this complete. No credential or wire format changes.
- [-] Retry an unavailable or stale privileged-helper status channel from the
  display clock, at most once per 30 seconds and only while the registered
  helper is enabled. The read-only check must not arm enforcement, prompt for
  approval, run during maintenance, or make the one-second UI clock block.
  This lets a transient helper interruption recover without opening Settings.
- [ ] Prove the signed installed Studio Dev app completes one same-account
  reconnect and publishes fresh online status to the authenticated staging
  connector. Do not repeat authenticator or recovery setup, erase enrollment,
  or issue a lock/unlock during this check. Rollback is the prior signed Dev
  app; preserve stored credentials, device keys, and lockout state.

## Safe release candidate boundary

- [-] Separate candidate preparation from production activation without domain
  or purchase-service changes. Exact 0.0.13 consumers, Studio signing, independent
  existing-source configuration snapshot, four embedded executable checks,
  prearchive public-key pairing and public-retention admission are covered by
  failing-first policy tests. This source split excludes issuer/site/public-docs
  and Cloudflare production configuration. Real signed-device/provider evidence,
  public-exposure approval and activation remain open. See `RELEASE.md` and
  `release-evidence/v0.0.1.md`. Withhold activation or withdraw the first release;
  never replace an active helper or overwrite enforcement state as rollback.
  Adversarial review added fail-closed cleanup of job-owned signing material
  before an immutable artifact action. A synthetic-file regression failed first
  for missing cleanup, then verified actual removal and Keychain-failure handling.
  Keep the Developer ID certificate import after unsigned quality checks and
  before archive, so test dependencies cannot access the signing keychain.

## Daybreak test-window lifecycle (2026-10-13)

- [x] Match the production daybreak-window cleanup in the native regressions.
  Two hosted parallel test attempts ended in a SIGSEGV and left hundreds of
  tests unrun. A diagnostic serial attempt completed 1,004 of 1,006 tests and
  isolated both failures to the new daybreak window tests; its crash report
  faults in `objc_release` while the test host drains an autorelease pool.
  Those tests called `close()` on their windows, unlike production, which uses
  `orderOut(nil)` and releases its strong references. The tests now use that
  same lifecycle. The temporary serial CI setting was removed because it did
  not resolve the crash. This is test-only: installed behavior, signing,
  permissions, and remote-command handling do not change. Hosted full-suite
  and UI-capture CI must pass before release acceptance.

- [x] Make the override-vs-wake cadence regression event-driven. After the
  daybreak tests passed, hosted CI 38469181460 completed 1,005 of 1,006 native
  tests; the lone failure was a 150 ms wall-clock expectation under runner
  load. The test now waits for the wake request to begin, holds its response
  pending, and counts two override polls that occur afterward. Its five-second
  expectation is only a deadlock guard, not a cadence or latency requirement;
  the production transport and its 20 ms fixture interval are unchanged.

- [x] Keep the override-failure health regression event-bound under parallel
  test-host scheduling. The account-poll and offline callbacks must both occur,
  and a healthy callback must remain absent throughout the bounded wait. The
  wait is a test deadlock guard, not a product latency target; transport behavior
  and release configuration are unchanged.

## Renewed account connection handoff (2026-10-12)

- [-] Keep a failed local eligibility-snapshot write separate from lost account
  credentials. A full or temporarily read-only disk must leave the saved
  enrollment and OAuth session intact, report the status channel offline, and
  retry on a later heartbeat after storage recovers. A genuinely missing
  enrollment, malformed or oversized JSON, or an unsafe file entry still
  requires device-identity repair, without offering a sign-in action that
  cannot work without that same record. Settings instead gives a direct support
  contact while leaving the local schedule intact. The coordinator must never
  receive a report whose matching local command-eligibility snapshot was not
  saved.
  Verify the signed installed app resumes status publication after recovery;
  no remote lock or unlock is needed. Rollback keeps the existing enrollment
  but restores the prior false sign-in-required behavior on local write errors.

- [x] Keep revoked refresh credentials distinct from temporary offline status.
  The native transport regression waits for the terminal sign-in-required
  callback before checking that no offline callback follows; its bounded wait
  is a deadlock guard, not an OAuth latency requirement. This changes only test
  synchronization, not credential handling or installed-app behavior.

- [x] Resume the native transport after successful same-account reauthentication.
  The previous flow persisted credentials but left the rejected transport stopped
  and the engine active, so another ordinary start was ignored. Reauthentication
  now returns explicit success; Connections checks the enrollment is unchanged
  and drains/restarts transport. Cancellation and failure do not restart it.
  Pending encrypted changes survive; maintenance and intervening lifecycle
  changes prevent a stale restart. The actual engine regression failed first
  with one connection instead of two and a still-rejected status, then passed
  in the existing background harness. At 06:13:31Z the signed installed update
  reports online with fresh disarmed status through the actual Codex connector.
  A second interactive reauthentication is not claimed. No wire, version,
  enrollment, permission, or enforcement change is introduced. Rollback is the
  prior signed app with stored credentials and all device state preserved.
  CI also exposed two enforcement fixtures that never enabled enforcement and
  an overlong helper explanation; the fixtures now explicitly enable their
  isolated models, and the permission explanation uses the existing footer.
  The authorization prompt key now has explicit C-string lifetime through the
  system call, resolving a compiler pointer-lifetime warning without adding
  rights or another prompt.

## CI action version assertions (2026-10-12)

- [x] Accept numeric major, minor, and patch action tags in the unit-test
  diagnostics assertion. The pinned `actions/upload-artifact@v7.0.2` remains;
  failure-only upload, artifact name, and result-bundle path are still required.
  Focused Node script tests verify this correction; native build/lint checks are
  outside this fix's authorized validation scope. No app behavior changes.
  Rollback is the assertion change alone; action upgrades need not be reverted.

## Idle account-sync write budget (2026-10-12)

- [-] Replace idle protected HTTP polling with the existing authenticated socket.
  Separate liveness from semantic status, suppress only acknowledged or already
  in-flight identical reports, retry failed reports, and preserve the daemon's
  exact-version eligibility fence. A main-actor publication ledger has seven
  headless regressions and is connected to native publication. CI observed the
  transport regression before implementation: unchanged heartbeat18 replaced
  eligible version17; that regression now passes on CI 38302226143. That run also
  exposed a stale fixture: its supposed changed report changed only metadata.
  The fixture now changes phase and preserves its late-response assertions.
  The socket consumer, monotonic scheduler and independent channels are wired.
  Headless regressions cover an actual suspended connection boundary, handshake
  timeout until first pong, receive-loop hints/revocation, late-open cleanup,
  bounded reconnect jitter, coalescing and a full-day idle read budget (2,304
  protected reads versus 23,040 previously; this is not a live indexed-write count).
  Review found a delayed socket-refresh rejection can stop a replacement session;
  CI 38304524293 reproduced generation2 instead of1, then its generation fence
  was restored. Terminal rejection now intentionally reports once and stops all
  channels instead of producing duplicate failures. A wake/network observer now
  reconnects without UI, and headless RED/GREEN regressions cover immediate
  restoration and closing a dropped socket consumer. CI 38305592933 passed the
  stale socket-refresh fence and reproduced the new status POST refresh regression.
  Status publication now shares the single-refresh retry path. Teardown cancels
  owned refresh tasks and fences late credential writes; restored sockets retain
  their backoff history, with observed headless RED/GREEN coverage. Final native
  CI must verify these fixes before installation.
  Final review identified command/result ordering lost by independent tasks;
  CI 38308503697 cleanly reproduced forbidden command fetching after a failed
  result POST. Commands now await the same owned result-publication task as the
  result channel; unrelated channels remain independent. Cleanup precedes task
  completion so refreshed retries cannot rejoin cached failed work.
  CI 38307160113 exposed fixture teardown traffic and failed status refresh/cadence;
  CI 38308319780/38308503697 reproduced one stale operation instead of zero.
  - [x] Allow the hosted ordering test three seconds for its simulated result
    callback under scheduler load while retaining the exact expired-result,
    fresh-result, then command-fetch assertion. This adjusts test timing only;
    native result publication and device behavior are unchanged.
  The pre-operation generation/cancellation guard and fixture cancellation are
  fixed; full native CI is still required. No runtime timeout budgets were increased.
  CI 38309791533 exposed duplicate successful result uploads while the daemon
  awaits receipt verification. Connection-local acknowledged-result deduplication
  now preserves retryability and clears on reconnect. Authorized HTTP checks
  cancellation across challenge suspension; cadence fixtures await session
  invalidation before releasing handlers. Final hosted verification remains open.
  CI 38310819506 reproduced suppressed replacement delivery after receipt removal;
  suppression now requires the exact still-present candidate and never represents
  daemon acceptance. Protocol fixtures snapshot request handlers at construction
  as invalidation alone did not prevent a delayed startLoading handler race.
  CI 38311757940 passed those regressions and exposed the equivalent deferred
  handler race in the general transport fixture; its snapshot is now aligned.
  CI 38312352269 still failed both missing-handler cases, so snapshots alone
  were insufficient. CI 38313551603 traces now prove Foundation constructed
  cadence requests after session invalidation; cadence mock behavior is bound
  per session, with canceled tombstones instead of a next-test global lookup.
  CI 38314500184 passed all cadence cases but found the same cleared-handler
  defect in the general fixture. Both fixtures now bind per-session behavior;
  the reconnect regression explicitly replaces its own active mock behavior.
  Hosted green verification remains outstanding. Async fixture teardown cancels
  and joins currently owned operations, with a suspended-operation regression and request/session
  lifecycle diagnostics. The intentional reconnect race keeps immediate
  disconnect. Hosted GREEN remains open; normal
  interactive disconnect is unchanged.
  Native integration verification is still in progress;
  app-hosted tests are not run on this Mac because they can steal focus.
  Keep a 60-second independent command fallback inside the five-minute delivery
  TTL, coalesced event reconciliation and slower peer/wake polling. Failed sends,
  cancellation and reconnect cannot be mistaken for acknowledged synchronization.
  No wire/schema/version change. Do not ship deduplication without socket liveness:
  it would otherwise make an unchanged Mac appear offline. Installed acceptance
  and a measured indexed-write budget remain open. Rollback is the previous app
  build with enrollment preserved; no new remote lock is authorized.

Source: [`Documentation/plan.md`](./plan.md)
Test Matrix: [`Documentation/todo-test-matrix.md`](./todo-test-matrix.md)
Owner: Willie + Claude
Status legend: `[ ]` todo, `[-]` in progress, `[x]` done

> **v0.1 launch status (2026-08-01):** Core enforcement, flexible schedules,
> CLI, user-approved MCP requests, user-confirmed reflections, CI/release
> scaffolding, and the landing site are implemented. Release builds enable the
> local MCP integration and packaged privileged helper; CloudKit, Calendar, and
> WidgetKit remain disabled pending production Apple provisioning and signed-artifact
> validation. The helper still requires the signed install/reboot/uninstall checks
> in `Documentation/RELEASE.md`. The production license issuer is deployed and its envelope-v2
> health endpoint is live, but the landing sale gate remains closed: no
> production checkout-to-license delivery has been proven from a signed app
> release. Items below marked `[ ]` are external release gates or v0.2+ targets
> unless noted otherwise.

> **MCP guide compatibility:** Mintlify reserves `/mcp`. Keep the source page
> `mcp-guide` and the exact proxy alias from `/docs/mcp` to `/docs/mcp-guide`,
> including query strings. Accept the published source and complete proxy
> behavior before replacing the existing public guide.

> **Marketing capture safety:** `scripts/capture-marketing.sh` launches and
> captures only its own fixture process. It never kills an existing Curfew
> process or substitutes a full-screen desktop capture when no fixture window
> is found.

---

## 0. Foundation and Project Structure

- [-] Adopt the Studio Mintlify configuration, setup, and authoring standard while retaining Mintlify and product branding. Use the accessible docs primary orange `#b25e30` and preserve the approved light/dark themes. Publish reviewed `main/web/docs` source through the existing Git connection and retain `/docs/mcp` through the nonreserved `mcp-guide` alias. Use shared packages and frozen registry locks with repository Actions Read access. Accept navigation, anchors, assets, search and discovery on the protected marketing Worker preview before production cutover. See `Documentation/website.md`.

- [x] Bundle the pinned Chrome native messaging host with signed browser queues, atomic policy snapshots, stale-review rejection, heartbeat health, and uninstall cleanup. See [browser native host](browser-native-host.md). The keyless first-upload artifact is reproducible; creating the Web Store item and pinning its assigned `CURFEW_BROWSER_EXTENSION_ID` remain release work.
- [x] Isolate development and production Chrome host names, reject unsafe helper executables, bound complete signed queue records, and revoke active hosts before uninstall deletes their state.

- [x] Create `CurfewKit` SPM library for shared domain models (CurfewKit/Sources/CurfewKit/). App/widget/CLI/MCP all link it as a library product and depend on it via public types (`import CurfewKit`).
- [x] Convert app shell to a standard macOS app window (`LSUIElement = false`) with menu bar quick access.
- [x] Default debug/Xcode launch starts with enforcement disarmed unless explicitly enabled.
- [x] Add a dedicated app launch coordinator so app startup orchestration is isolated from scene composition.
- [x] Add targets for `curfew-mcp`, `curfew-ctl`, `curfew-daemon`, and the WidgetKit extension.
- [x] Keep synchronized app/Widget groups normalized, exclude target-owned `Info.plist` files from resources, and verify the package-backed Widget through its generated scheme.
- [x] Define the v0.1 Release entitlements: Apple Events and App Group present; iCloud, APS, and user-selected-file access intentionally absent. Exact signed-artifact validation remains a release gate, not an implementation TODO.
- [x] Define centralized app constants (`AppGroup`, bundle IDs, CloudKit record names via SharedPaths.swift).
- [x] Add feature flags with safe defaults off and an explicit `shippingV1` preset: WidgetKit/MCP/helper on, CloudKit/Calendar off.

## 1. Schedule + Enforcement Core

- [x] Implement weekly schedule model (per-day end time, unlock time, day-off support). The Settings/onboarding copy now frames these as "Work ends" and "Work resumes" so the editable times line up with the actual enforcement window.
- [x] Propose 22:00–06:00 on weekdays for a new install without rewriting saved schedules. Edits apply immediately while automatic scheduling is off; automatic lockouts require an explicit weekly-schedule choice before setup finishes.
- [x] Keep previously completed Studio Dev installs remote-only until they explicitly enable their saved weekly schedule. Show all seven effective rules and require separate confirmation if arming may lock now or within a minute; preserve active durable deadlines and authorized fixed-duration remote locks. App Intents, the local schedule tool, and the CLI must report observed enforcement and the inactive automatic schedule accurately.
- [x] Make onboarding's reviewed-weekly-schedule selection one state transition so the choice reliably enables Next after viewing the saved rules; the remote-only choice remains available.
- [x] Keep all seven effective rules and both automatic-schedule choices visible and clickable in the minimum first-run window; show the selected choice before Next advances.
- [x] Implement schedule presets: 9-to-5, Startup Hours, Half Day.
- [x] Enforce anti-bypass policy — stricter changes apply next day; weaker require 24-hour cooldown.
- [x] Add DST-safe local timezone handling and schedule resolution tests.
- [x] Add schedule summary sentence generation for Settings.
- [x] Add a single `EnforcementSnapshot` read model for UI surfaces.
- [x] Add "Apply to all days" action in schedule editor.

## 2. Warning Escalation

- [x] Implement warning stage engine for `T-30`, `T-15`, `T-5`, `T-2`, `T-1`, `T-0`.
- [x] Deliver warnings via `UNUserNotificationCenter` with categories/actions.
- [x] Add snooze (1 minute) action only for `T-30` and `T-15`.
- [x] Build click-through dim overlay windows with stage-specific opacity.
- [x] Add always-on-top floating timer for last 5 minutes.
- [x] Add advanced settings to customize warning intervals.

## 3. Lockout Experience

- [x] Build full-screen lockout windows on all displays and spaces.
- [x] Add `.screenSaver`-level window behavior and input capture.
- [x] Add keyboard shortcut interception during lockout (⌘⇥, ⌘Q, ⌘⌥Esc, …).
- [x] Implement rotating encouragement messages.
- [x] Implement lockout visual design (time, unlock time, optional stats card).
- [x] Respect accessibility settings: VoiceOver, reduce motion, reduce transparency; warning countdowns, lockout controls, and Settings tabs expose stable semantic accessibility values/identifiers for UI automation and assistive technology.

## 4. Shutdown Manager

- [x] Implement optional auto-shutdown delay setting (1-60 min, default 10).
- [x] Show lockout countdown UI for shutdown.
- [x] Request graceful app termination before shutdown.
- [x] Implement shutdown retry once after 60 seconds on failure.
- [x] Keep lockout active if shutdown ultimately fails.
- [x] Gate auto-shutdown UI/runtime behind Apple Events capability; release builds carry the entitlement while debug/ad-hoc builds hide the feature. The Settings panel and generated Info.plist now explain that Curfew asks `System Events` to shut down the Mac, and a denied Automation prompt now keeps lockout active without retrying while pointing users to **Privacy & Security → Automation → Curfew → System Events**.

## 5. Bypass Protection + Privileged Layer

> v0.1 ships an authenticated `SMAppService` LaunchDaemon. The legacy
> user-space respawn guard remains defense in depth, not the state bridge.

- [-] Package a real `curfew-daemon` helper for `SMAppService` install/status validation; jailbreak detection + shutdown enforcement remain deferred. The Xcode bundle phase now signs every embedded CLI/helper executable with the app's expanded signing identity, while explicitly unsigned CI builds skip that signing loop; an artifact-level test requires the daemon's non-empty TeamIdentifier to match Curfew's in signed builds. Signed-build install/reboot/uninstall validation remains an external release step. See `Documentation/RELEASE.md`. (v0.2)
- [-] Persist lockout state through the LaunchDaemon sentinel path; root-owned write semantics still need signed-build/manual validation. (`Documentation/RELEASE.md` now captures the exact manual checks; the actual proof still requires a signed build.) (v0.2)
- [-] Enforce coordinator-signed remote lock commands in the privileged daemon. The app stages only opaque `0.0.9` envelopes; the installed daemon wakes every 15 seconds, requires an authenticated account/device enrollment, fetches the bounded public JWKS from `curfew-sync.hypertext.studio`, verifies ES256 claims including the protocol `lock_device` kind, and feeds the effective deadline into the existing enforcement loop. A command is eligible only when its `statusVersion` and `scheduleDigest` exactly match the Mac's last locally recorded status publication; changing the local schedule invalidates an older coordinator snapshot before network delivery. Local MCP and remote MCP conform to one daemon-injected backend boundary: synchronization failures are isolated, durable deadlines remain enforceable during transport failure, and the strongest active deadline wins without transport-specific policy in the daemon loop. Inbox, result, and acknowledgement operations use no-follow directory descriptors, regular-file/link-count validation, bounded reads and enumeration, canonical hashed names, atomic rename, and root-owned Application Support directories rather than trusting the console user's tree. The daemon rejects partial oversized inbox batches for coordinator redelivery, atomically moves even nested or otherwise non-unlinkable overflow entries into a private sibling quarantine, and requires each decoded cursor to hash to its exact enumerated filename. This prevents poison-prefix starvation while ensuring authenticated sequence ordering covers the complete accepted batch. A durable two-phase exchange returns delivery acknowledgements and terminal results through the app, retaining them across offline retries until the daemon sees exact coordinator acceptance. When Curfew is running, that result is projected through the account-sync callback into the same stronger-only durable deadline and immediately presents the lockout surface. A proof-bound active remote override now suspends scheduled, wake-campaign, and daemon-issued lockouts for its exact enrolled device while preserving the durable deadline for automatic re-lock. Its independent 15-second poll cannot be stalled by other sync work, accepts the coordinator's whole-second or fractional UTC timestamps, and staggered stale-token failures share the already-rotated credentials instead of refreshing twice. The app mirrors the exact grant expiry into a separately signed daemon release without overwriting emergency break glass; the daemon accepts a valid bounded grant that began before a later lockout and stops honoring it at the coordinator's exact expiry. An authenticated no-active-override response clears both cached releases on the next poll, so cancellation or direct-grant revocation cannot leave the Mac open until the original expiry. The root-owned shadow is the authority while the login session is locked because macOS may data-protect the user's Application Support tree; model tests therefore inject temporary stores and never write synthetic deadlines into live user state. Debug and Release builds expose the helper install/status controls and continue app heartbeats to an installed helper; Debug targets staging while Release targets production. Signed-build installation and live coordinator proof remain incomplete. Rollback is to disable remote enrollment/transport while leaving the local daemon backend and durable local enforcement intact. (v0.0.2)
  The daemon's read-only status path now resolves both injected backends without transport synchronization. A released local candidate is filtered before deadline composition, so it cannot mask an active remote deadline; local shadow mirroring remains on the serialized status path while remote discovery stays on its separate queue. This changes no wire format or installed state. Package-level coverage runs without launching the app; signed-install and live coordinator acceptance are still required. Rollback restores the prior composition root and backend read method.
- [x] Implement user-space respawning LaunchAgent (`PersistentLockdown`) for v0.1 bypass deterrence.
- [x] Register login items for compatibility requirements. (v0.2)
- [x] Implement event tap behavior for keyboard shortcut interception during lockout.

## 6. Extension and Override Systems

- [x] Implement weekly extension budget (default 3/week, 15 min each).
- [x] Restrict extension requests to warning phase only.
- [x] Implement deliberate extension activation (hold-to-confirm, 2-second hold).
- [x] Implement extension reset day configuration (default Monday).
- [x] Enforce override limit (default 2/week).
- [x] `curfew-ctl override` CLI command.

## 7. "Convince Me" Unlock Flow

- [x] Add subtle lockout entry point: "Need to get back in?"
- [x] Enforce 5-minute cooldown before unlock request form.
- [x] Require minimum 50-character justification.
- [x] Add consequence confirmation with hold-to-confirm.
- [x] Grant time-limited unlock (default 30 min), then re-lock automatically.
- [x] Log timestamp/device/reason/granted duration for each override event.

## 8. Menu Bar UI + Core Screens

- [x] Build menu bar icon state system (green/amber/red/gray/lock).
- [x] Implement popover: countdown, schedule, extension action, quick links.
- [x] Build primary app window (Overview, Configuration, Getting Started).
- [x] Build Settings sections: schedule, enforcement, integrations, devices, license, advanced.
- [x] Build "This Week" retrospective in app UI.
- [x] All UI colors system dark mode adaptive (NSColor dynamic provider).
- [x] Native macOS TabView in Settings window; flat layout in sidebar configuration pane.

## 9. Calendar Integration (Pro)

- [x] Add EventKit permission flow (`CalendarMonitor.requestAccessAndSync()`).
- [x] Fetch today's non-all-day events, expose `todayEvents`, `hasCurrentEvent`, `nextEvent`.
- [x] Refresh every 5 minutes.
- [x] Gate behind `featureFlags.calendarEnabled` + `licenseGate.isProUnlocked`.
- [x] Surface auth status and grant-access button in Settings → Integrations.
- [x] Show calendar events on lockout screen and This Week view. (v0.2 UX polish)
- [x] Detect meeting overlaps 1 hour before curfew and offer extension prompt. (v0.2)

## 10. CloudKit Sync (Pro)

- [x] Per-record CloudKit schema (`Settings`, `Device`, `DeviceActivity`, `LockoutState`).
- [x] Last-write-wins conflict resolution on `modifiedAt`.
- [x] Graceful handling of missing container / unauthenticated (`CKError.isExpectedAbsence`).
- [x] Gate behind `featureFlags.cloudSyncEnabled` + `licenseGate.isProUnlocked`.
- [x] `cloudKitSyncEngine.push()` on every settings mutation.
- [x] `CKDatabaseSubscription` registered for silent-push sync on remote changes.
- [x] `DeviceRegistry` 60 s heartbeat + active-device detection (120 s freshness).
- [x] `LockoutState` published on phase transitions for warning handoff between devices.
- [x] Active-device-aware shutdown delay (active follows configured delay; idle uses 2 min).
- [ ] CloudKit container provisioned in App Store Connect. (`Documentation/RELEASE.md` lists the production container/schema validation steps; execution remains external.) (morning task)
- [x] Sync status UI in Settings → Devices.
- [x] Device list management (live list + last-seen + active pill).

## 11. Activity Log + Retrospective

- [x] SQLite storage with 52-week rolling retention (direct `sqlite3` C API, no GRDB).
- [x] Hours-based and combined curfew modes (lock after N hours of active work; per-day toggle in the schedule editor).
- [x] `WorkTimeAggregator` computes active-minutes-today from ActivityStore + idle windows.
- [x] `ThisWeekView` memoises the weekly rollup on `(weekStart, activityMutationCount)` so the tick loop stops rerunning the query every second.
- [x] Per-day schedule exception seam (`DayRuleException` struct) — Codable-compatible for future holiday pickers.
- [x] `ActivityRecorder` writes lifecycle/extension/override events.
- [x] `ActivityRollups` computes daily/weekly aggregates.
- [x] `IdleWatcher` detects idle periods (5-min cutoff).
- [x] "This Week" view in app UI.
- [x] CSV export. (v0.2)
- [x] Device-attributed insights. Surfaced in `ThisWeekView` when 2+ overrides exist and in `curfew_get_weekly_summary`'s `overrides_by_device` field.

## 11.5 Audit log

Distinct from §11: the activity store is a queryable rollup that feeds the
retrospective, so it records the dozen event kinds the UI aggregates. The audit
log is a low-level, append-only, human-readable record of what Curfew *did* —
including the decisions that never surface in the UI, such as a deferred
schedule change, a consent verdict on an MCP request, Accessibility trust lost
mid-lockout, and every action the root daemon takes. Format specification:
[`Documentation/audit-log.md`](./audit-log.md).

- [x] JSON Lines records with schema version, ISO-8601 timestamp with offset, per-stream sequence, writing stream, actor, event type, and before→after state.
- [x] Separate file per writer — app under `~/Library/Logs/Curfew/`, root daemon under `/Library/Logs/Curfew/` — so the two never interleave and no cross-privilege lock protocol is needed.
- [x] SHA-256 hash chain per stream, spanning rotations, recovered from the file on restart. Tamper-*evident*, not tamper-proof; the daemon stream is root-owned and therefore the stronger of the two.
- [x] Size + age rotation with a 25 MiB per-stream ceiling (5 MiB × 5 segments) and 90-day retention on rotated segments.
- [x] Redaction: reflection prose and override justifications are never written; a length and a truncated digest go in their place. MCP tool arguments are digested for the same reason.
- [x] Wired to enforcement phase transitions, lockout start/end with an end reason, schedule requested/deferred/applied/cancelled, extension and override grants and refusals with budget, MCP consent verdicts with the calling origin, app launch/quit/permission/respawn-guard state, presence, and the app-side auto-shutdown workflow.
- [x] Daemon wiring, split by layer: `main.swift` records what it *read* (deadline, heartbeat, live claims, break-glass release) and `DaemonEnforcementRuntime.apply` records what was *done* (shutdown issued, cancelled with a reason, held, stand-down, deferral window opening and closing). The same branch that calls an effect writes its record, so the log cannot report a cancellation that never happened.
- [x] Observation records extracted from `main.swift` into `DaemonAuditObserver` so they are reachable by tests. They were a private function in a top-level script and shipped one-directional: break-glass recorded its start and never its end. Every dimension is now asserted in both directions.
- [x] `daemon.shutdown_issued` is written from the launch result rather than before it, so a `/sbin/shutdown` that fails to start records only `daemon.shutdown_failed`. The log cannot assert a root shutdown that never happened.
- [x] Protected-work carve-out events: `protected_work.active` / `.cleared`, `break_glass.observed`, `daemon.shutdown_cancelled`, `daemon.shutdown_held`, `daemon.stand_down`, `daemon.deferral_opened` / `.closed`, plus the app-side `shutdown.deferred` and `shutdown.released_by_break_glass`.
- [x] MCP consent resolution is split by *who decided* (`approveMCPRequest`/`denyMCPRequest` for the consent sheet, `autoApproveMCPRequest`/`denyMCPRequestByPolicy` for the policy engine) so the actor is structural. The first shape shared one function between human clicks and automatic policy and recorded every policy refusal as a user decision, and every auto-approval twice.
- [ ] Attribute `curfew-ctl` separately from `curfew-mcp`. Needs a `client` field on `MCPPendingRequest`, which is a `curfew-protocols` change and therefore a three-repo ceremony.
- [ ] Surface the log from the app UI or `curfew-ctl` (e.g. `curfew-ctl audit --since`). Reading it today means `jq` on the file.

## 12. WidgetKit (Pro)

- [x] Small widget: phase-tinted Gauge ring with in-ring phase icon and time remaining.
- [x] Medium widget: phase + remaining + schedule window.
- [x] Large widget: full status, lock/unlock times, streak pill, 7-day sparkline.
- [x] Mirror widget settings + activity data into shared widget storage so the future extension can read state without the app's private defaults domain.
- [x] `CurfewWidgetProvider` reads mirrored settings/activity data from shared widget storage; timeline produces per-warning-stage entries (T-30/15/5/2/1/0) within the next hour plus 15-min coarse entries.
- [x] Gate behind `featureFlags.widgetKitEnabled` + `licenseGate.isProUnlocked`.
- [x] Xcode Widget Extension target wired in project.
- [x] Wire timeline updates to enforcement phase AND warning-stage transitions.

## 13. MCP Server (`curfew-mcp`)

- [x] `curfew-mcp` executable target (stdio MCP server, JSON-RPC 2.0).
- [x] Read tools: `curfew_status`, `curfew_schedule`, `curfew_budget`, `curfew_activity`, `curfew_request_status`, `curfew_get_time_remaining`, `curfew_get_weekly_summary`.
- [x] Read-only reflection tool: `curfew_get_reflections`; no MCP tool can write a user's reflections.
- [x] Write tools (queued by default): `curfew_request_extension`, `curfew_request_override`, `curfew_set_schedule`.
- [x] Streamable HTTP transport on localhost:9847 (opt-in; Settings → Advanced).
- [x] Unix-socket IPC seam between `curfew-mcp` and the running app (queue fallback today; POSIX listener in a follow-up).
- [x] Claude Desktop auto-detection and one-click registration from Settings.
- [x] `AIConsentPolicy`: queue (default), autoApprove, deny.
- [x] `MCPConsentSheet` for user approval of queued write requests.
- [x] Settings → Integrations: MCP toggle, Claude Desktop config copy, consent policy picker.

## 14. CLI (`curfew-ctl`)

- [x] `status` — enforcement phase, time remaining, override state (plain + JSON).
- [x] `schedule show` — today's and full weekly schedule.
- [x] `budget` — extension and override budgets remaining.
- [x] `activity` — recent activity log entries.
- [x] `override` — enqueue an override request for the running app to approve.
- [x] Bundled at `Curfew.app/Contents/Resources/curfew-ctl`.

## 18.1 Distribution scaffolding (you complete externally)

- [x] `web/worker/wrangler.toml.example` + `scripts/license-worker.mjs` — one
      template-only Worker path with caller-owned rendered config and no
      committed identifiers or secrets.
- [x] `Casks/curfew.rb` — Homebrew Cask formula with signed release URL and zap paths.
- [x] `scripts/gen-sparkle-keypair.sh` — uploads the private Ed25519 seed directly to the GitHub secret and prints only the public key.
- [x] `scripts/generate-appcast.sh` — CI-invoked Sparkle appcast builder.
- [x] `scripts/release-checklist.md` — exhaustive external-setup sequence.
- [x] `scripts/uninstall.sh` — standalone uninstaller mirroring the in-app flow.
- [x] In-app uninstall flow (Settings → Advanced → Uninstall).

## 15. Curfew Plus Licensing

- [x] Ed25519 offline license key verification (`LicenseGate` + `CryptoKit`).
- [x] License key format: `{base64url(payload)}.{base64url(signature)}`.
- [x] `LicenseView` in Settings — activate/deactivate, Pro status display.
- [x] `ProGate<Content>` generic view wrapper gates CloudKit, WidgetKit, Calendar.
- [x] `PurchasePromptView` — feature name, description, upgrade link.
- [x] Envelope v2: signed JSON bytes, `curfew-plus`, lifetime/subscription claims, expiry and refresh token.
- [x] `web/worker/` — pnpm-locked issuer source plus local tests and template-only Wrangler config.
- [x] `scripts/license-worker.mjs` — explicit-path keygen, fail-closed config validation, dry-run and HTTPS health verification.
- [x] Caller-owned rendered Worker configs resolve the entry point from the clone, so a fresh-clone dry-run and dashboard bundle do not need a repo-local config workaround.
- [x] `Documentation/license-worker-bootstrap.md` — fresh-clone bootstrap and rollout boundary.
- [x] Production Ed25519 public key embedded; the matching private seed is retained only outside the repository for Worker secret provisioning. The verifier is rotated whenever a prior signer is unavailable or exposed; an exposed draft is discarded before it can reach Worker runtime. The matching Worker secret must be rotated with the deployed app verifier before distribution.
- [x] Initial-release app UI has no hosted checkout destination. Existing keys can
      still activate locally; a future checkout change must follow the separate
      production purchase-to-license verification gate.
- [ ] Production Curfew Plus Stripe products, Worker secrets, webhook, and
      purchase-to-license delivery verified. Keep the landing sale gate closed
      until this external launch gate is complete.
- [x] `node scripts/license-worker.mjs keygen` — envelope-v2 Ed25519 keypair generation.
- [x] `web/worker/src/` — Cloudflare Worker: Stripe webhook → signed key.
- [x] Placeholder public key replaced with the embedded release public key; release CI rejects the all-zero sentinel if it returns. Matching private-key availability remains part of Worker deployment evidence.

## 16. Onboarding

- [x] First-launch getting-started window.
- [x] Persist one-time first-launch setup state.
- [x] First-run flow: welcome, schedule, budgets, permissions, confirmation.
- [x] Onboarding completion now requires opening live schedule settings and acknowledging permissions guidance before finish.
- [x] Anti-bypass: onboarding mutations route through `queueScheduleUpdate`.
- [x] Onboarding relaunch from Settings.

## 17. Distribution and Operations

- [x] `.github/workflows/ci.yml` — format + lint + test + build on push/PR.
- [x] `.github/workflows/release.yml` — archive + sign + notarize + DMG on tag push.
- [x] `scripts/build-dmg.sh` — `create-dmg` wrapper.
- [x] MIT `LICENSE` file.
- [x] README rewrite: three-horizon pitch, MCP setup, CLI usage, Pro features, architecture.
- [x] `CONTRIBUTING.md`, `PRIVACY.md`, `Documentation/ARCHITECTURE.md`, `Documentation/RELEASE.md`.
- [x] Signed-build validation runbook for shutdown, Widget, helper, Sparkle, notarization, and DMG installation lives in `Documentation/RELEASE.md`.
- [-] Standardize the landing frontend on native Astro public/dist builds and the pinned Worker tools. Manual staging must select exact successful main website/docs output, use its separate credential, and verify main before publication. Accept isolated routing, staff Access protection, bindings, Mintlify proxy behavior and native rollback before production cutover. Coordinate the signed appcast publication destination with the native release owner; a first signed app release is not required for frontend migration.
  - Administer managed Custom Domains separately from restricted Worker deployment configuration. Preserve account/coordinator routes and verify domain association, selected-version bindings, TLS and public delivery. Pages is not a frontend recovery dependency.
  - [x] Accept the marketing Account navigation handoff to the existing environment-specific portal without redirecting credentials, request bodies or authentication callbacks. Keep site and portal routes on separate hosts; overlapping ownership must fail closed instead of looping.
  - [x] Publish the accepted Mintlify proxy configuration on the production marketing Worker after cutover approval. Preserve the HTML compatibility asset and existing account service ownership.
- [x] Account-era landing contract — every public header links to the optional
      same-origin account portal, Android is labeled as coming soon, and the
      privacy, security, retention, purchase, recovery, and remote-unlock
      boundaries are published without implying that Google Play Services are
      required. Product behavior checks remain in CI.
- [x] Mintlify documentation source lives in `web/docs/`.
- [-] Publish reviewed `main/web/docs` source through the existing Mintlify Git
  connection. Preserve guide bookmarks, canonical URLs and the MCP alias.
  Accept navigation, anchors, assets, search and browser behavior on protected
  Worker staging before the approved public cutover. Preserve the existing
  public documentation through preview acceptance.
- [ ] Apple Developer credentials in GitHub secrets. (external launch gate)
- [x] Cloudflare Pages production deployment and `curfew.hypertext.studio`
      DNS/TLS. The public site returned HTTPS 200 on 2026-08-01; checkout
      remains intentionally gated pending the separate production delivery
      proof.
- [ ] Homebrew Cask. (v0.2)
- [-] Sparkle autoupdate scaffolding present; framework wiring + signed appcast
  flow still pending. v0.1 releases publish only the notarized DMG. (v0.2)
- [x] Support an isolated `curfew-license-staging.hypertext.studio` license
      Worker configuration for Stripe test-mode staging, with a distinct KV
      namespace and secrets; alternate Worker hostnames fail closed.
- [x] Stripe Sandbox staging proof: an isolated `$1` test-only payment link
      completed with Stripe's `4242` test card; the fresh
      `checkout.session.completed` and `invoice.paid` deliveries both returned
      `200`, and the issued license was retrieved from the staging Worker. No
      live Stripe card, live payment link, or production Worker was used.

## 17.5 Enforcement audit closure (2026-05-18)

Every finding in `audir-our-core-feature-vectorized-sutherland.md` is closed
in this branch. The audit's M1 (uninstall during lockout) was reclassified
as an opt-in feature per the user's product direction and is not blocking.

### Phase 1 — trivial bypasses (v0.1.x)
- [x] **C1** — `CURFEW_SKIP_ENFORCEMENT` is honored only in Debug; Release always arms.
- [x] **C2** — `PersistentLockdown` auto-installs in Release via the new `RespawnGuardControlling` seam; Debug uses `NoOpRespawnGuard`.
- [x] **C5** — `SchedulePolicyEngine.classifyChange` covers `mode` and `hoursLimitMinutes`; mode flips and hours-budget bumps trigger the 24-hour cooldown.
- [x] **C7** — `applyPendingScheduleIfNeeded` defers `.weaker` pending changes during active lockout.
- [x] **M3** — Accessibility-trust state is read from `AXIsProcessTrusted` at
      launch, on each enforcement tick, and whenever the app becomes active;
      the Overview banner deep-links to System Settings. Interactive builds now
      reject an unresolved signing identity instead of producing an ad-hoc app
      whose changing code hash makes an enabled TCC row misleading.

### Phase 2 — v0.2 hardening
- [x] **C3** — Privileged daemon now enforces: detects stale app heartbeat during lockout and invokes `/sbin/shutdown -h +1` as root.
- [x] **C4** — Daemon shadow-copies the durable record to `/Library/Application Support/Curfew/lockout-deadline.json` so a user delete of the user-side file can't end-run the deadline.
- [x] **C6** — `request_override` removed from the MCP tool surface; the friction model (cooldown + reason + hold) stays in-app where it belongs.
- [x] **M2** — `LockoutKeyInterceptor` blocks Cmd-W/H/M/backtick, F3/F4/F11/F12 alongside the existing Cmd-Tab/Q/Space/Opt-Esc set.
- [x] **M4** — Daemon issues shutdown directly via `/sbin/shutdown`; AppleScript path stays as fallback when daemon isn't installed.
- [x] **M5** — `LockoutDeadlineStore` persists the active window; the model overrides the engine back to `.locked` when the deadline hasn't passed.
- [x] **M6** — `MCPRequestSigner` HMACs every queue entry with a per-install secret; unsigned/forged requests bypass `.autoApprove` and fall to the consent sheet.
- [x] **M7** — `onSettingsReceived` defers a `.weaker` remote schedule into `pendingScheduleChange` when the device is locked.
- [x] **M8** — `ExtensionBudgetTracker` reconstruction preserves `lastResetBoundary` via the new `seedLastResetBoundary` init param.

### Phase 3 — minor + arch
- [x] **m1** — T-30/T-15 docstring matches the actual notification-only behavior (overlay starts at T-5).
- [x] **m2** — `ActivityStore` opens with WAL + NORMAL synchronous; mid-write power loss rolls back instead of corrupting rows.
- [x] **m3** — `mostRecentResetBoundary` returns `nil` on pathological calendar arithmetic instead of falling back to today.
- [x] **m4** — `Weekday(from:)` logs a warning before its Monday fallback so unexpected calendars produce telemetry.
- [x] **m5** — Widget shared state carries a live `WidgetEnforcementSnapshot` written on every phase transition.
- [x] **m6** — License re-verifies on day rollover so a tampered UserDefaults can't keep Pro alive indefinitely.
- [x] **A1** — `LockoutDeadlineRecord` carries a backward-compatible UUID; the daemon's active deadline is authoritative over missing or weaker user-side state.

## 17.6 On-device presence detection (2026-08-08)

Closes the two founding-document claims that HID idleness alone could not
support: "Curfew can detect whether I am actually at my computer working" and
"if I am distracted, Curfew will warn me to get back to work". Full
specification — captured / derived / retained, consent, limitations — is in
`Documentation/presence-detection.md`.

- [x] **P1** — `PresenceFusion` crosses `IdleWatcher`'s verdict with a camera
  person signal into four states: `working`, `present_idle`, `absent`,
  `unknown`. HID activity wins outright; `unknown` is the honest answer when
  there is no camera signal and is never collapsed into `absent`.
- [x] **P2** — `VisionCameraPresenceSensor` detects a human shape on-device with
  `VNDetectHumanRectanglesRequest`. No identification, no face print, no image
  written or transmitted; frames exist for one Vision call and only a boolean
  survives.
- [x] **P3** — `PresenceMonitor` is the sole caller of `start()`, gated on the
  user's setting **and** live TCC authorization, rechecked every tick so a
  revocation in System Settings takes the camera down within a second.
- [x] **P4** — `PresenceDetectionPolicy` defaults to `cameraEnabled: false`, and
  every decode path (including a settings blob predating the feature) falls back
  to that default. No migration turns the camera on.
- [x] **P5** — `NSCameraUsageDescription` set on both Debug and Release app
  configurations; `enablePresenceDetection()` prompts before persisting intent,
  so a refused grant never leaves a stored intent to run a camera.
- [x] **P6** — `CameraLiveIndicator` renders in Settings and the menu-bar
  popover only while a session is live, alongside the system's own green light.
- [x] **P7** — `DistractionWarningPolicy` nudges a sustained present-but-idle
  user during `working` / `warning` only, never at an empty chair, never during
  lockout or a day off, and at most once per repeat window.
- [x] **P8** — Five audit events (`presence.state_changed`,
  `presence.camera_started` / `_stopped`,
  `presence.camera_authorization_changed`, `presence.distraction_warned`) follow
  the existing envelope. `presence.changed` is unchanged so existing parsers keep
  working. No record can carry image data.
- [x] **P9** — Observation staleness (20 s) decays a wedged capture session to
  `unavailable` rather than pinning a verdict; a future-dated reading is
  rejected so a backwards clock step cannot extend a reading's life.

Risk and rollback: the feature is inert until switched on, so the rollback is
the shipped default. Reverting the commit removes the camera code entirely; a
persisted `presence.cameraEnabled: true` on an older build decodes into an
unknown key and is ignored.

## 17.7 Task-scoped browser enforcement (2026-09-08)

This slice adds Curfew's local policy authority, direct Docket client, signed
native host, Chrome extension, and local Settings controls. Signed-app/Web Store
release verification remains a separate delivery task. The
architecture and privacy limits are in `Documentation/browser-enforcement.md`.

- [x] Normalize only HTTP and HTTPS destinations. Curfew removes credentials,
      query strings, fragments, and default ports before a destination reaches
      policy or review. All stored scopes use one validated constructor. Invalid
      or cross-origin recommendations cannot broaden access.
- [x] Build the allowlist from the configured Docket web origin, task
      references, and mappings that select exactly one task, project, or label.
- [x] Retain the current task whenever Docket returns a null active-work task.
      Read that exact task even when tracking says running or paused. End the
      session when any active-work task is completed, canceled, or archived.
      End a retained session when its exact task returns an `archivedAt`
      timestamp. Missing and unauthorized task resources fail closed.
- [x] Revoke grants when the task changes. Limit grants to 30 minutes and
      denial cooldowns to five minutes.
- [x] Permit one 15-minute break for each transition into paused or idle. A
      running observation cancels the break and creates eligibility for a later
      pause or idle transition.
- [x] Fail closed for unknown destinations when Docket or Athena is unavailable.
      Curfew retains known scopes while it marks the connection unhealthy.
- [x] Register a public OAuth client with Docket on first use. Store the issued
      client identifier and rotating tokens in the separate
      `studio.hypertext.curfew.docket` Keychain service. Reject duplicate callback
      security parameters and responses over 32 KiB. Match the flavor-specific
      callback with AuthenticationServices' `Callback.customScheme` API.
- [x] Cache Docket credentials once per process without making refresh recovery
      depend on a complete access-token record. A stored rotating refresh token
      remains usable when the access token or expiration is absent.
- [x] Poll `docket://hub/active-work` every 30 seconds without a session and
      every five seconds while Curfew retains a session. Reject responses whose
      Docket observation time moves backward.
- [x] Parse one real Streamable HTTP SSE message. Require JSON-RPC 2.0, the
      negotiated MCP version, and the request's exact identifier. Coalesce
      concurrent initialization. Limit MCP responses to 1 MiB. Retry once after
      a 401 or dead session, and fail closed after the second failure.
- [x] Bind an Athena result to the session that requested it. Discard a late
      grant, challenge, or denial after a task switch without changing the new
      task's grants or cooldowns.
- [x] Write `browser.destination_reviewed` for each accepted Athena result.
      Store only the hostname, decision, and scope kind. Discarded stale-session
      results and private review text never reach the audit log.
- [x] Expose only the task ID and title in browser policy snapshots. Keep base
      scopes separate from temporary grants, and evaluate grant and break expiry
      against the current time after cache restoration. Keep Docket descriptions,
      project summaries, labels, and raw references inside Curfew.
- [x] Connect the policy coordinator to the app lifecycle and signed persistent
      policy snapshot through the flavor-isolated native host. Persist only the
      retained session, organization, and task identifiers needed to resolve an
      idle restart without weakening fail-closed behavior for old records or
      failed exact-task reads.
- [x] Build the `@curfew/chrome-extension` MV3 package. Block only top-level HTTP
      and HTTPS navigation, install a missing base block before validated allow
      rules, replace a persisted ruleset atomically, wake at grant or break
      expiry, long-poll signed policy revisions with one watcher, retain the
      30-second refresh as recovery and heartbeat fallback, route blocked tabs
      through opaque request IDs, and retain one original justification only
      while its targeted challenge can continue across reload. Keep startup
      alive after cached storage or DNR restoration fails, install block-only
      recovery when Chrome permits it, and request fresh policy without a
      manual extension reload.
- [x] Package 16, 32, 48, and 128 pixel Chrome icons as transparent-padded
      exports of the shipping Curfew app icon. Reject icon drift in tests.
      Require a separate, matching Web Store public key and item ID for
      production builds. Produce an upload ZIP containing only the current
      production build files.
- [x] Add one Task Browser Enforcement panel. Persist the two setup facts and
      validated mappings locally. Show authorization, poll, extension, host,
      active-task, and readiness state. Show `Never` before Chrome sends its
      first heartbeat instead of formatting the store's sentinel date. Keep the
      toggle gated until setup has succeeded once, and expose the reducer's one
      fixed 15-minute break.
- [x] Add Debug-only Settings and blocker fixtures that use temporary or
      in-memory state. Remove blocker fixture data from production output.
- [-] Ship and verify the Chrome extension and native messaging host with a
      signed app. The Web Store draft, production extension identity, Settings
      acceptance, uninstall cleanup, and release rollback drill remain open.

## 18. Verification (v0.1 release candidate)

- [-] Prove remote account enrollment and signed phone-to-Mac lock/unlock with
      an isolated Hypertext Studio development app. The additive `StudioDev`
      configuration builds `Curfew Studio Dev.app` with distinct app/widget IDs,
      App Group, daemon label, local state, Keychain services, and callback
      scheme; Debug and Release identities are unchanged. A Studio-bundled
      helper recovers its flavor from the app even if launch environment is
      missing or conflicting. Studio Dev does not claim the personal Chrome
      native host, cannot issue or cancel root shutdown, yields remote lock
      acceptance and daemon effects to a live higher-priority Curfew, and
      uninstalls only its own state. Studio uninstall unregisters its daemon
      and login item before erasing state; if either unregister fails, it
      leaves the app and saved state in place with an actionable error.
      Focused tests and an unsigned artifact build cover these boundaries.
      The release-contract test also checks that both Debug and StudioDev
      compile embedded tools for staging while Release does not.
      The Studio App ID and App Group are registered in Apple Developer;
      provisioned company signing and installation of the isolated Studio Dev
      app have been observed. Its account enrollment reached the Recovery Key
      acknowledgement. As of 2026-10-12, launchd reports the Studio helper
      registered with a 15-second interval and last exit code zero. Codex's
      authenticated MCP connection previously reported the Mac online with fresh native
      status after curfew-sync PR #42. The previously authorized command
      `d5c310ce-7bcf-4ce8-9cd0-87c98ba3a50a` has an applied receipt at
      `07:00:55Z`, with deadline `07:05:55Z`; the app audit stream records
      leaving the locked phase at that deadline. This does not establish
      visible blocking, Claude phone execution, or remote unlock. Those
      remain unverified; do not send another lock to repeat this check
      without renewed user direction. An unsigned build alone is not a
      release or runtime proof. Operationally, install only the correctly
      provisioned Studio app after comparing the built team, entitlements,
      destination, and personal install. Rollback removes only the Studio
      bundle and its flavor-scoped state; do not run the production uninstall
      script or change the existing personal App IDs. The protocol consumer
      now pins the separately released 0.0.11 contract; this is not signed
      installation or phone-to-Mac proof.
      Latest signed-update verification supersedes the earlier readiness result:
      the installed app is offline, the existing helper registration lacks its
      authenticated XPC endpoint, and Codex requires fresh OAuth authorization.
      Reconnect navigation fails in both Chrome and the hidden in-app browser,
      while ordinary sign-in loads. Staging logs identify D1 daily write quota
      exhaustion in authorization and token refresh; retry saved credentials
      after the quota reset before requiring another sign-in.
      Preserve the running helper and protected state until trusted maintenance
      is available; see the current findings in
      `Documentation/remote-mcp-acceptance.md`. No new control command was sent.
      Superseding acceptance on 2026-10-13: after the signed Studio Dev app
      launched armed and healthy, a separately authorized five-minute Codex
      Staging command had an applied daemon receipt, a live locked report, an
      installed-app `lockout.started` event, and an opaque full-screen Curfew
      window. At the deadline, the report returned to working, the app logged
      `lockout.ended`, and that window disappeared. This proves physical
      enforcement and natural release for the signed dev app and Codex staging
      connector; it does not prove Claude-phone execution, remote unlock, or a
      downloadable production release. Do not repeat device-control commands
      without new authorization. See `Documentation/remote-mcp-acceptance.md`.
- [-] Make local status readers report observed enforcement rather than a
      schedule-only prediction. During the verified remote lock,
      `curfew-ctl status` said `working`; local MCP's `curfew_status` and
      `curfew_get_time_remaining` use the same independent engine evaluation.
      A shared, freshness-bounded app/daemon status source must account for
      remote deadlines, active releases, Curfew-off state, and cross-flavor
      enforcement ownership. When observation is unavailable, report that
      limitation instead of claiming the schedule prediction is live status.
      Test the actual CLI/MCP outputs against controlled persisted observations,
      then verify a signed installed build without another control command.
      No existing remote command or account schema needs to change; preserve
      current command state and the separate coordinator status path on rollback.
      The app now publishes a freshness-bounded, flavor-isolated, user-owned
      observation after its enforcement tick settles. The CLI and local MCP
      read that observation and say `unknown` when Curfew is off, another flavor
      owns lockout, or the observation is stale. The publisher coalesces stable
      one-second ticks and refreshes every 15 seconds; readers expire at 60
      seconds. Package regressions failed first for the missing reader APIs,
      then passed for the CLI JSON formatter, MCP handlers, and disarmed status.
      Adversarial review added failing-first coverage for a standby process
      clobbering the lock owner, degraded protection, and hours-based mode;
      maintenance pause now publishes unavailable status instead of leaving
      the prior snapshot fresh. A hosted app test was compiled headlessly;
      hosted CI and a signed installed read-only check
      remain before this item can be marked complete. Rollback removes only
      the advisory status mirror and readers; daemon enforcement and remote
      command state do not depend on it.
- [x] Pin both SwiftPM entry points to the immutable pre-1.0
      `curfew-protocols` 0.0.11 release. A Swift bridge test exercises the new
      one/all-device unlock scopes and a release-contract check rejects
      Xcode/SPM pin drift. Rollback of either consumer alone would make unlock
      consent incompatible; roll forward together or disable remote consent.
- [x] Keep every user-facing release surface in the `0.0.x` line. The Xcode
      targets and Homebrew cask now agree on `0.0.1`, with a release-contract
      regression preventing an accidental `1.x` or minor-version jump.
- [-] Enroll macOS devices through browser OAuth, mandatory server-side AAL2,
      generated first-party scopes, ES256 device proof, and separate Recovery
      Key acknowledgement or restore. Passkey-first and configurable Apple
      account behavior are reflected in the product copy. A single compile-time
      endpoint set now keeps the app, OAuth exchange, sync transport, account
      portal, MCP resource, daemon JWKS trust, and account-key Keychain namespace
      together for staging or production. The Dev app's Debug configuration
      selects staging by default, including every embedded tool, so an installed
      development build cannot silently target the unresolved production hosts.
      Staging remains restricted to the Debug app and its own helper label plus
      user/root state paths; Release rejects the staging flag. Native
      authorization now preserves the user's normal browser session instead of
      forcing an ephemeral one, so an existing account and its passkey provider
      remain available during enrollment. The app now owns a claimed HTTPS OAuth
      callback through Associated Domains. The account service publishes both
      the `webcredentials` association required by AuthenticationServices and
      the narrow universal link used when the user finishes a copied
      authorization URL in another browser profile; a public client ID and
      private-use scheme are not treated as proof that the caller is Curfew.
      Native authorization also uses the concrete Settings window that
      initiated enrollment, retains it for the authorization lifetime, and
      fails immediately when no attached window exists instead of fabricating
      an invalid presentation anchor and leaving a spinner running. It uses the
      current callback-based AuthenticationServices initializer rather than the
      deprecated callback-scheme initializer. Controller and service
      single-flight guards prevent repeated activation from replacing an active
      system session or orphaning its completion. While that session is live,
      Settings exposes its exact PKCE- and state-protected authorization URL so a user can copy it
      into the browser profile that actually stores their passkey instead of
      being trapped in macOS's default profile. The URL disappears as soon as
      browser authorization ends, before device enrollment begins, and its temporary pasteboard value is removed
      unless the user has since copied something else. Claimed HTTPS callbacks
      from an ordinary browser tab are routed into only the active transaction
      after exact origin, callback-path, and one-time-state validation; the former
      custom scheme is rejected. AppKit delivers a claimed HTTPS link from an
      external browser as a web-browsing user activity, so the delegate now
      forwards that activity's URL into the same one-time router. SwiftUI may
      instead deliver the link to a scene's URL handler, so each app scene also
      forwards URLs to that router. The older URL-open delegate remains for
      URL-open delivery. The router checks the effective HTTPS port as well as
      host, path, and state. This fixes a copied-link sign-in that could finish
      in the browser while Settings waited forever. A signed Studio build passes
      local build checks; the real browser callback and device enrollment still
      need runtime verification.
      If the activity path regresses, the copied-link option can be disabled
      without weakening callback validation or the system sign-in session.
      If the browser reaches the HTTPS callback
      instead of returning to Curfew, Settings offers Cancel sign-in so the
      user can start a fresh authorization without quitting the app. Cancelling
      stops the active browser session, rejects any in-flight token result,
      clears the temporary sign-in link, and re-enables sign-in. The enrollment
      UI now keeps
      browser authorization and device enrollment as separate states: once the
      browser callback succeeds, Settings reports that it is connecting the Mac;
      token exchange or local credential failure is
      reported as a native connection failure, never as a failed passkey or
      unfinished browser sign-in. If the first device connection fails before
      registration, Curfew keeps a small authorized-connection checkpoint and
      offers a retry after relaunch without repeating browser sign-in. It reads
      the current OAuth credentials from Keychain rather than copying tokens
      into that checkpoint; an unreadable credential stops enrollment.
      Expired access tokens are refreshed even on this first registration path.
      If the saved OAuth credential is missing or the server rejects its
      refresh, Curfew clears only that pre-registration authorization marker
      and offers a fresh sign-in instead of trapping the user in retries.
      A later device-registration or recovery checkpoint takes precedence and
      is never discarded by that escape path. Actual Keychain read failures
      still leave the saved connection unavailable rather than inventing an
      empty account.
      For these later checkpoints, a rejected or missing refresh credential
      offers a separate same-account sign-in. The new token is staged until
      UserInfo confirms the original account from the coordinator-accepted
      token or registration receipt. A different account leaves saved keys,
      Recovery Key, checkpoint, and old credentials untouched. A legacy
      pre-receipt checkpoint without an account identity fails closed and
      asks for support. This avoids registering an old device under a new
      account while still making recoverable sign-in failures actionable.
      Cancellation after a same-account OAuth grant is written now restores
      the checkpoint's prior client ID and token pair before another attempt.
      This prevents the UI from requiring reauthorization while Keychain
      silently holds the cancelled grant. No wire format or release identity
      changes. A failed intermediate Keychain write restores the original token
      pair; if rollback itself fails, the access token is cleared and Settings
      reports storage unavailable instead of suggesting another sign-in.
      On relaunch, an unfinished device registration with either OAuth token
      missing explicitly requires same-account sign-in instead of presenting
      a normal retry. The storage warning now avoids claiming the saved account
      is unchanged when a Keychain rollback could have failed; local schedule
      and enforcement remain independent of that account credential state.
      An enrolled Mac now publishes signed device status from confirmed account
      polls while the first local schedule is still unset. This keeps the
      account's online indicator and remote-command eligibility aligned with
      the running app without starting local enforcement early. Once setup is
      complete, the existing 1 Hz enforcement tick owns status heartbeats.
      A running enrolled Mac must also keep the bounded account heartbeat when
      Curfew is disarmed: its display clock continues without local lockout
      effects, and the outbound report marks enforcement state unknown rather
      than claiming that a scheduled lock is active. Without this path the
      coordinator marks a still-running Mac offline after two minutes. The
      status report does not arm Curfew or prove a remote lock can be enforced.
      Rollback is the previous signed app; the coordinator will again age out
      a disarmed Mac until it resumes authenticated status publication.
      A Mac that has already completed enrollment can now renew rejected OAuth
      credentials against its saved account identity without registering a new
      device or rotating its Recovery Key. Settings offers this same-account
      sign-in only when saved credentials need renewal, even if the old ready
      marker disappeared; a revoked device instead directs the user to check
      account access. Settings warns when the privileged helper is absent or
      its root-owned heartbeat is stale, or Studio Dev must yield to a live
      higher-priority Curfew app, so sign-in alone is not presented as remote
      lock readiness. Reconnect is single-flight, leaving an in-progress
      browser session cancellable after rapid taps. The signed Studio
      Dev installation previously produced live authenticated status, helper
      registration, and an applied coordinator receipt. The latest signed
      update is installed but its authenticated helper connection and current
      Codex OAuth session are not working; see the acceptance ledger above.
      A witnessed physical lockout was completed through Codex staging on
      2026-10-13; phone-side assistant execution and remote unlock remain open.
      Unit tests, launchd state, and a receipt alone cannot establish those
      outcomes. See
      `Documentation/remote-mcp-acceptance.md`. Rollback is
      the previous app build while preserving the existing device enrollment;
      do not delete its Recovery Key or device record to force another sign-in.
      Roll back this polling-triggered heartbeat if it causes unexpected status
      traffic; the account page would again show an unscheduled Mac offline.
      Rollback is the previous app build, but damaged Keychain state still needs
      repair before retrying enrollment.
      New pre-receipt checkpoints with opaque access tokens now obtain the
      coordinator-verified UserInfo subject before saving the registration
      request, so a failed registration can still offer identity-bound
      reauthorization. If UserInfo is unavailable, the authorized-connection
      marker remains retryable rather than saving an unanchored device
      checkpoint. The extra request affects only tokens without a usable
      subject hint; rollback must not discard an already saved checkpoint.
      When the coordinator already holds a different recovery envelope,
      Curfew retains the registered-device receipt and account identity in a
      separate existing-key checkpoint, without retaining the newly generated
      Recovery Key. An expired credential during existing-key restoration
      offers the same identity-bound sign-in, then returns to the Recovery Key
      form; an incorrect key still stays at that form. This checkpoint must
      survive relaunch and must not be replaced by the display-only record.
      Before device registration, Curfew persists
      the exact OAuth-bound request inputs, Recovery Key, and encrypted envelope;
      it adds the authenticated receipt before finalization. Ambiguous registration,
      expired-token, upload-failure, and relaunch paths resume that checkpoint
      once at a time without another OAuth or passkey ceremony while the saved
      credential remains valid; an unrecoverable credential requires the
      same-account sign-in above. The app keeps
      the receipt-backed checkpoint while it shows the generated Recovery Key,
      rather than replacing it with the older display-only record (which lost
      the receipt and blocked confirmation),
      offers Copy and Save-to-File actions so the user need not transcribe it,
      and uploads the encrypted envelope only after the user selects “I saved
      the Recovery Key.” The clipboard is cleared after one minute if its
      contents have not changed; an exported plaintext file is created with
      owner-only permissions. Neither action is proof that the user retained
      the key. Curfew cannot report ready before the coordinator accepts the
      envelope. An incorrect Curfew Recovery Key leaves the Mac at the same
      recovery-entry step with a retry message instead of starting sign-in
      again. These local state-transition tests do not replace signed-device
      staging proof; rollback should preserve saved checkpoints and Keychain
      credentials so a completed browser grant is not discarded. Reverting
      the same-account retry UI without preserving these checkpoints would
      leave registered Macs at a dead-end if their refresh credential expires;
      release verification must exercise an expired grant and a wrong-account
      attempt on a signed Studio build before claiming remote enrollment works.
      It must also exercise an opaque-token registration failure and same-account
      recovery, because local tests cannot prove coordinator availability.
      Coordinator acceptance is checkpointed as a durable completed-enrollment
      mirror before the recovery setup is removed. That marker remains until an
      explicit account reset, and a newer marker takes precedence over stale
      settings, so a process exit or settings-write failure cannot silently
      return the Mac to an unenrolled or older enrollment state.
      A Keychain read error or corrupt local enrollment checkpoint now leaves
      Settings in a distinct saved-connection warning state instead of
      pretending the account is empty. New sign-in is refused while that state
      is unreadable, preventing replacement of an unfinished enrollment. The
      user can retry a read without deleting keys or changing saved settings;
      a successful read resumes the exact saved step. This does not stop an
      independently running sync connection or claim remote control is off.
      Persistent corruption needs support-led recovery; rollback must preserve
      the fail-closed sign-in policy rather than restoring the old `try?`
      fallback.
      A destructive uninstall erases the entire flavor-specific account and
      Docket OAuth Keychain services, including this durable marker, OAuth
      credentials, device identity, and dynamically named private keys, so
      enrollment cannot resurrect after reinstall and the development app
      cannot clear production. Curfew terminates after presenting the cleanup
      result so its live settings model cannot recreate deleted enrollment.
      Production uninstall also removes the older flavor-neutral coordinator
      assertion credential; Dev deliberately preserves that production-owned
      item until it can be retired or migrated to a flavor-specific service.
      After enrollment, Settings observes the live account-sync engine instead
      of treating saved enrollment as proof of a working connection. It explains
      connecting, encrypted-waiting, synchronized, offline, and rejected states in
      plain language, keeps local-schedule protection explicit during failures,
      and directs assistant/device permission changes to the web account.
      A read-only remote-command poll cannot claim queued encrypted changes were
      saved, including after an offline or rejected connection recovers. The
      connection is healthy only after account-state, direct-unlock, and any
      attempted status-publication work succeed. Network failures are shown as
      reconnecting; missing, revoked, or rejected credentials remain an
      account-access error that requires sign-in. Out-of-order status responses
      cannot overwrite the health of the newest published status, and an old
      polling session cannot report into a newly reconnected account session.
      Accessibility trust is also re-polled whenever Curfew becomes active,
      so the Today warning clears after the user grants access in System
      Settings even when Curfew's enforcement timer is off.
      Settings now leads with the account path used for phone-based remote
      control and labels the separate desktop-only assistant integration in
      plain language. Its copy matches the shipped local tool boundary: an
      assistant may read explicitly listed data and request changes, but cannot
      grant an override, end an active lockout, or disable enforcement. It also
      states that reflection text is shared with the assistant when requested
      instead of incorrectly promising that it never leaves the Mac. Turning
      local AI access off now makes the standalone MCP server return no tools
      and refuse cached tool calls, so an existing Claude Desktop entry cannot
      keep reading data. The page also discloses that the separately controlled
      protected-work tool may postpone shutdown without approval while leaving
      the lockout itself intact.
      In-repo tests pass; live account recovery and staging proof remain
      external release gates.
      If Copy or Save fails, the Recovery Key remains visible and Curfew does
      not acknowledge it automatically. Rolling back the export controls must
      retain the existing saved-key acknowledgement and envelope checkpoint.
      Rolling back cancellation would restore the missed-callback spinner dead
      end; cancellation is safe only before device enrollment begins.
      Rollback may disable native enrollment, but must not restore the
      unregistered callback, guessed-window behavior, or concurrent sessions.
- [x] `just check` passes (format + lint + tests + Debug build).
- [x] `xcodebuild archive` succeeds unsigned locally.
- [x] `./curfew-ctl status` prints live state.
- [x] `./curfew-mcp` responds to `tools/list` over stdio.
- [ ] Paste test license → Pro features unlock; remove → re-gate.
- [ ] Lockout smoke test: set curfew 5 min ahead, observe overlay, recover via override.
- [ ] MCP smoke test: paste Claude Desktop config, run `curfew_status` from Claude.
- [x] Landing page links all resolve. Fixed `hypertext-studio/curfew` → `TheHypertextStudio/curfew` across README, Cask, landing, CONTRIBUTING, generate-appcast.
- [x] Marked the forward-looking PRD and Sparkle/appcast checklist steps so v0.1
  cannot be mistaken for a released sync/updater product; regression coverage
  lives in `scripts/release-entitlements.test.mjs`.
- [x] Make CI demo captures prove the named screen. The screenshot job now
  forwards unsigned build settings and propagates UI-test failures instead of
  uploading a green artifact after a failed test. A regression assertion
  requires the Settings image to contain the account panel. The existing
  `curfew-settings.png` artifact showed Today, and the first targeted hosted
  rerun found no window containing the account panel. Its accessibility tree
  confirmed that Today was the only Curfew window: the old AppKit responder
  selector did not open the SwiftUI Settings scene. Curfew now registers the
  active scene's `openSettings` action for Settings links. Requests made before
  scene appearance are coalesced and delivered when the action registers,
  including account setup and fixture launch, rather than silently dropped.
  Focused routing tests pass;
  hosted CI run `35947559952` passed after the deferred-opening change, and
  its exported `curfew-settings.png` visibly shows Integrations and the Curfew
  Account panel. This is unsigned fixture proof, not signed account-enrollment
  proof. Failure bundles contain
  only synthetic demo-fixture account state; the failure-only artifact can be
  removed if it adds unnecessary CI storage.
  Rollback must not restore the failure-masking `xcodebuild || true` path.
- [x] Corrected the signed-build guard to validate Xcode's resolved certificate
  identity. The prior guard inspected only the requested `CODE_SIGN_IDENTITY`
  label, allowing an ad-hoc `Curfew (Dev)` binary when the local development
  certificate was revoked. Unsigned CI/demo builds remain explicitly supported;
  interactive builds now fail with the recovery action before producing a TCC-
  unstable app. Rollback is the single build-phase predicate change.
- [x] Retire Node 20 GitHub Actions runtimes from Curfew CI and release workflows.
      Checkout, cache, artifact upload, and release actions now use their
      current Node 24-compatible release generations. Hosted CI verifies the
      workflows; no deprecation-only tests or scripts are maintained.
      Recheck upstream runtime support when deliberately upgrading these
      actions; reverting to the previous generations restores a runtime that
      GitHub has removed.
- [x] Updated the forward-looking PRD and release checklist to distinguish the
  shipping v0.1 WidgetKit, MCP, helper, and Sparkle scope from deferred CloudKit
  and Calendar work; regression coverage lives in `scripts/release-entitlements.test.mjs`.
- [ ] Complete every pending row in `Documentation/release-evidence/v0.1.0.md` against the published DMG.

## 19. UI simplification and visual acceptance

- [x] Replace Settings toolbar tabs with General, Limits, Warnings, Connections,
  Advanced, and About; retain legacy section raw identifiers.
- [x] Use native grouped forms, conditional durations, and disclosed technical
  setup. Show only build-enabled Plus benefits and connections.
- [x] Clarify readiness versus active enforcement; simplify setup, schedule,
  assistant consent, purchase, and shutdown copy.
- [x] Make assistant configuration copy feedback visible and registration status
  refresh immediately; route pending-request review to the main consent sheet.
- [x] Isolate Debug review models from enforcement, shared queues, widgets,
  helper services, assistant configuration, and real settings/history.
- [x] Make disabled shared buttons visibly subdued and suppress press animation
  and scaling under Reduce Motion; preserve existing enabled/disabled rules.
- [x] Remove forced uppercase and letterspaced overlines from Settings, Journal,
  weekly activity, and calendar labels. Use ordinary case throughout.
- [x] Refine Settings with neutral surfaces, a compact aligned sidebar, and
  collapsed connection details; keep General actions visible at minimum size.
- [x] Remove duplicate helper attention copy so Setup remains visible in a
  minimum-size degraded General window; retain diagnostics behind disclosure.
- [x] Show assistant read access before enabling its connection.
- [x] Preserve native arrow-key Settings navigation and synchronize sidebar
  selection so repeated Manage AI Access actions return to Connections.
- [x] Replace the exhausted override entry button with an explicit allowance message.
- [x] Expose the warning timer container for direct, asserted captures without
  including unrelated desktop content. Preserve its countdown and behavior.
- [-] Verify the complete state inventory and capture actual windows in both
  appearances and sizes. See `ui-state-review.md`; user visual acceptance and
  signed-build/system checks remain independent gates.

- [x] Unify Settings and workspace color roles: warm gray surfaces, readable clay
  links, and coordinated filled controls. Keep sky controls on the shared palette.
  Appearance-resolved contrast and palette integration tests fail first and pass.

- [x] Correct selected-row contrast by preserving native selection foregrounds;
  use shared supporting-text colors in Settings. Consolidate remaining warning
  and static lockout palettes; prevent desktop bleed through the warning timer.
- [x] Add hostless background theme verification; twelve tests pass without an app
  host, window manipulation, or UI automation. Keep native accent assets aligned
  with filled-control tokens through a numerical integration check.
- [-] Visually accept the final unified palette and accessibility behavior.
  UI tests/captures and the full app-hosted suite remain deferred at the user's
  request to keep the desktop untouched; background Debug, lint, format and
  targeted tests pass. Release remains blocked by signing configuration.

- [x] Use shared contrast roles in setup and reflection forms; keep selected
  rating/mood labels and hold-progress text readable. Check input contrast over
  a worst-case white backdrop and preserve opaque fills under Reduce Transparency.

## Integration with current main (2026-10-10)

- [x] Include the 25 earlier commits as requested, preserving main's account,
  recovery, browser, protected-work, remote-command, and Studio Dev features.
  Shared source and package tests now live under `CurfewKit/`; protocol remains
  pinned to main's 0.0.11 contract. No cross-repository wire changes.
- [x] Bring account, presence, protected-work and browser Settings into the same
  grouped-form hierarchy. Keep camera privacy visible and technical controls in
  disclosures. Healthy and failure indicators consume shared semantic colors.
- [x] Connect authenticated daemon transport to the existing single policy/effects
  pipeline. Preserve protected-work holds, cancellation, independent signed remote
  authority, and Studio Dev shutdown suppression. Keep network discovery off the
  serial local-control queue. Derive peer identity from signed team and exact role;
  isolate Mach services and root persistence by build flavor.
- [x] Persist local wake-release tombstones; make completion retries idempotent.
  Retain the app's durable wake identity until acknowledgement, allowing terminal
  wake state to unlock presentation while failed completion retries. Keep the
  compatibility file heartbeat during helper upgrades. Local overrides retain
  durable authority. Corrupt local transport storage degrades that transport while
  independent enforcement continues and the damaged file remains intact.
- [-] Complete integrated background build, format and lint checks; run hosted
  unit/interaction/capture suites only on remote CI. Local launches and UI tests
  remain prohibited by the user's request. Remote CI UI checks are authorized.
- [-] Inspect and share remote screenshots of the integrated branch; obtain final
  visual feedback. Existing local captures predate this integration. Signed helper
  registration/authentication and real-system permission/enforcement acceptance
  still require a dedicated signed-build session, never this background session.

Operational impact: this merge includes package and authenticated-helper work,
not only color changes. No release, helper registration or system permission
mutation is part of verification. Roll back through reviewed commits; preserve
root release tombstones and existing account data when diagnosing an installation.

Authenticated liveness integration: after authenticated arming or a matching heartbeat, legacy heartbeat files cannot keep that window alive. Unmigrated legacy windows retain file fallback. `AuthenticatedDaemonControlTests` covers persistence and binding to the current window; signed transport verification remains a remote/system acceptance gate.

Remote CI follow-up: screenshot extraction preserves the original failed UI-test exit status before attempting export. Authenticated liveness accepts a still-active local source during delayed stronger remote-deadline delivery, without changing effective authority or accepting unknown IDs. Regression checks cover both cases.

Landing integration: restored the account navigation and Android coming-soon notice after the directory migration; removed stale claims that Plus sync is currently available. All 30 script/landing/release-policy tests pass and run in CI.

Fixture safety review: demo Settings uses an ephemeral account secret store and inert enrollment services; synthetic camera authorization cannot prompt TCC or open Camera Settings. Real account checkpoints, recovery keys, network enrollment, and camera access stay outside captures. ThemeConsistencyTests includes a fixture-wiring regression (14 theme/UI-source tests total). Assistant disclosure includes activity access.

Remote full-suite follow-up: package endpoints now derive app/widget service isolation from their bundle identity when app-only compilation flags cannot propagate into SwiftPM; standalone tools retain their explicit service flag. Setup tests inject Accessibility trust, consent-copy expectations use the approved shorter labels, and the browser uninstall test waits for actual enqueue under loaded CI.

Remote capture correction: fully fitting native forms may expose a scrollbar with zero range. Bottom captures now verify the lowest text/control bounds as well as scrollbar position, and accommodate native wheel direction; long clipped panes still fail. The initial remote General capture was visually inspected and shared inline; it is interim evidence until final-head recapture.

The independent `landing/` package owns Astro source and native Workers hosting. Root commands and `just landing` use that package directly; backend workspace setup does not publish the frontend.

Visual inspection found the isolated runner Dock overlapping Today’s primary action. Screenshot CI now hides and delays only its own Dock before capture; no local desktop preferences change. A workflow regression check protects this capture setup, and unobstructed recaptures are required.

Remote interaction follow-up: assistant-access checks include the disclosed activity scope. Browser mapping checks scroll the disclosure into view and assert its expanded state before editing. CI preserves interaction result bundles separately from capture results, so failed control queries include their accessibility tree and screenshots. No local UI execution is required.

Capture review also found that Connections state screenshots showed only the top account/browser sections while their asserted AI/calendar/sync content was below the viewport. Each affected state now includes a second bottom capture; top captures remain for context. Native disclosure interaction targets the leading arrow, consistent with the existing helper-details capture.

Remote visual review found black override-reason text on a dark input in light appearance. The override editor now binds the shared atmospheric foreground and contrast-tested input surface, matching reflection inputs. `ThemeConsistencyTests/overrideInputPalette` was observed failing first; existing input contrast tests cover both appearances and transparency modes. Override rules, cooldown, hold, and persistence stay unchanged. Recapture the affected override states before merge.

Full-resolution Today review found washed-out schedule labels over the bright sky/page fade. The hero now uses the shared atmospheric text scrim and supporting-text role, backed by the same contrast-tested surface as reflection/override inputs. `todayHeroPalette` was observed failing first; the existing white-backdrop checks establish at least 4.5:1 for both text roles. Recapture Today in both appearances and window sizes.

The shared sky text scrim also protects lockout status and recovery controls. Faint per-view text-opacity variants were replaced with the shared supporting-text role, including shutdown failure, cooldown, validation, and exhausted-budget messages. `lockoutAtmosphericPalette` was observed failing before implementation. This changes presentation only, with no enforcement or exception-policy change.

Remote browser interaction recording showed the destination disclosure inheriting its section identifier and not opening under automation. It now has a unique accessibility target and explicit transient expansion binding. `browserDisclosureAccessibility` was observed failing first; the interaction test verifies the actual mapping removal control appears and exercises removal. No stored setting or browser enforcement rule changes.

The browser disclosure uses the same labeled button pattern as Manual setup: the entire row opens it, it participates in keyboard navigation, and VoiceOver receives Expanded/Collapsed. This avoids native Form chevron-only hit areas. The source regression was observed failing for the button action and accessibility value before implementation.

The remote AX lookup demonstrated section-level identifier propagation overriding browser child identifiers. The retained panel identifier now belongs to its heading, leaving the disclosure, enforcement switch, and break action individually addressable. The regression checks require this header scope; remote interaction remains the acceptance gate.

### UI state consistency and meaningful consent

- [x] Today distinguishes a scheduled lock period from running protection. The
  first-run action opens setup instead of enabling an unreviewed schedule.
- [x] Completed setup opens a review with live on/off status and Done; missing
  Accessibility access has its actual repair action. Closing review never arms
  enforcement or resets settings.
- [x] Assistant consent previews configured extension duration or the requested
  weekday, lock/unlock times, day off, and existing schedule delay. Unavailable
  extensions, malformed proposals, resolved requests, and legacy overrides cannot
  be approved from the sheet. Existing application and approval rules remain.
- [x] Replace build-rejection jargon with an explanation of the failed verified
  connection. Protection warnings name the missing capability instead of claiming
  a scheduled lockout is currently running. An interrupted keyboard connection
  no longer offers an unrelated permission action when permission is present.
- [-] Recapture these revised states on the isolated runner and inspect them.
  Local UI tests and launches remain prohibited by the user. No new permissions,
  stored identifiers, wire formats, licensing, or enforcement deadlines change.
  Rollback is presentation-only; retain the existing state/application policies.
- [x] Browser settings separate the enabled preference from connection readiness,
  breaks, and active work. Default copy is plain language; diagnostic timestamps
  and component health move under Connection details. Existing setup, policy,
  break budgets, and browser controls remain unchanged.
- [x] Consent discloses pending schedule edits that approval cancels or replaces,
  including discarded weekdays and the restarted waiting period. A weaker change
  can wait beyond 24 hours while a lockout is active.
- [x] Hide stopped legacy iCloud/device status when account sync is enrolled.
- [x] Calendar refresh rechecks read access and clears inaccessible events;
  calendar overlap advice only suggests an extension when eligible. Read-only
  authorization checks do not request permission. The injected test provider and
  lazy event store let revoked-access checks run without real calendar access.
- [-] Remote captures now include off-during-scheduled-lock, completed setup review,
  revoked permission in setup review, and malformed assistant requests, across both
  appearances and sizes. Assertions must confirm each state before capture. Automatic
  shutdown availability copy points to the supported app without build jargon.
- [-] Remote image review found default workspace captures clipped by the runner's
  1024px display. Configure only the isolated runner from advertised display modes
  large enough for default windows. Captures now compare image and window dimensions
  and fail on clipping. This script refuses to run outside GitHub Actions; it must
  never change the user's display. Recapture the final matrix before acceptance.

### Account readiness consistency after main integration

- [-] Implement guarded background-protection reconnect for the legacy Studio Dev
  registration. The serialized replacement workflow now has seven hostless
  regressions, including cancellation and overlap. The cancellation failures
  were observed before correction; overlap characterizes the existing guard.
  It waits for unregister
  completion and never resumes producers after admission, registration, or XPC
  verification failure. A canceled run attempts replacement after removal but
  cannot resume producers; final activation is synchronous and nonthrowing.
  Strict deadline admission now validates the remote device binding and each
  local/control/shadow source, rejecting malformed or mixed control formats.
  The mixed-format bypass regression failed before the decoder correction.
  Trusted legacy inspection, producer-drain integration, and the signed-app
  reconnect action are implemented. Repair requires enforcement Off and blocks
  new arming throughout admission. Two manager regressions failed before the
  admission ordering and arming guards were corrected. The first installed
  attempt removed the obsolete registration, but macOS rejected replacement
  with error 1; installed-runtime acceptance remains open. Authorization now
  shares one exact-path read-only context across both fresh inspections and
  explains the request as Curfew, rather than prompting as authopen twice.
  Preserve all enrollment, deadlines, replay cursors, and receipts. This is not
  evidence that the installed helper has been repaired.

  Update: the user completed repair at 22:53 Pacific on October 12. The installed
  app reports Connected, launchd exposes the expected endpoint, and the daemon
  heartbeat advances. Native account renewal remains open. The installation
  action now waits for connection verification, removing the rapid action-label
  changes the user observed. Installed acceptance of this last UI change remains.

- [-] Publish observed enforcement rather than a disabled schedule prediction.
  Disarmed devices without an active durable deadline use the existing unknown
  protocol phase and null deadlines. The regression reproduced the false locked
  report before correction. Verify the installed report through Codex after
  background protection reconnects; no lock or unlock test is authorized.

- [-] Refresh the account device's enforcement snapshot on its 60-second
  heartbeat even when the phase is unchanged. The enrolled Studio Dev Mac was
  online through routing while Codex retained an older status report. The
  publication ledger suppressed timestamps as duplicate metadata after the
  first acknowledgement. It now permits a due heartbeat while still coalescing
  in-flight and early duplicates; the regression failed before the fix. This
  changes no command, lockout, credential, or wire shape. Verify a fresh report
  from the installed signed update through read-only Codex listing before
  marking installed acceptance complete. Rollback reverts the ledger condition.

- [-] Review contradictory account and protection states. Remote locks require both a fresh daemon heartbeat and an authenticated ready connection, while Studio Dev still yields to a live higher-priority Curfew owner. Settings refreshes signed status on opening, activation, and the existing heartbeat interval. Pending approval opens the macOS approval pane; installed connection failures route to General; installation is offered only when needed. Account messages describe an unchanged schedule instead of claiming protection is active.

- [-] Arm enforcement on ordinary signed Studio Dev launches. The authorized
  staging MCP command on 2026-10-13 returned an applied daemon receipt, but the
  next native report was working with no lockout: StudioDev compiles with
  `DEBUG`, so the app launched its display-only timer without the developer
  opt-in environment variable. The verified Studio Dev bundle now follows
  Release's armed launch policy; personal Debug remains opt-in and genuinely
  loaded XCTest hosts remain disarmed. Demo-fixture and environment-only test
  markers cannot disarm Studio Dev or spoof its identity. The shared test-host
  predicate also requires a loaded XCTest runtime for both signed Studio Dev
  and Release, so spoofed environment markers cannot skip the event tap and
  other enforcement effects.
  `StudioDevLaunchBehaviorTests` and the existing Debug/Release tests cover
  those boundaries; the new assertions failed before the correction. The
  company-signed update is installed and its launch audit now records
  `enforcementArmed: true` with health `active`. A separately authorized
  physical lock was subsequently observed through Codex staging; see the
  acceptance ledger. Phone execution, remote unlock, and downloadable
  production acceptance remain open.
  No wire, account, command, or deadline format changes are involved. Rollback
  is the launch-policy change; do not replay the expired command.

- [x] Keep the morning reflection interactive while enforcement ticks. The
  signed Studio Dev app exposed a one-second full-screen refresh that reset
  typing and made buttons difficult to click: its overlay coordinator replaced
  the `NSHostingView` and raised the window on every tick. The first installed
  correction stopped remounting, but typing still failed because a plain
  borderless `NSWindow` cannot become key. Existing windows now retain SwiftUI
  state, and the daybreak window is key-eligible; only a changed display frame
  or hidden window needs AppKit work. Both `DaybreakOverlayReconciliationTests`
  regressions were added failing-first. The signed update was installed on
  Studio Dev Mac, and the owner confirmed that typing and both form buttons
  work without resetting. No reflection answers, schedule, remote command,
  or wire data are migrated; rollback is the daybreak-window change.

Hostless coverage: `PrivilegedHelperManagerTests.remoteReadinessRequiresAuthenticatedConnection` rejects unavailable, unauthorized, stale, and failed registration despite a fresh heartbeat file. `PresentationStateTests` checks recovery routing and copy. The new assertions failed before the fix; CI retains full app behavior and screenshot checks. No local UI execution or app launch. This changes readiness presentation and recovery routing, not enforcement rules, persisted identifiers, or the wire format. Rollback is the readiness/copy change; signed helper and real macOS approval verification remain separate.

Account rejection copy now distinguishes expired sign-in, explicit server access denial, and local remote-update failures. A version without background protection explains availability without directing to a hidden General section. `AccountStatusPresentationTests` exercises actual status-to-copy resolution in the hostless suite; both regressions failed before correction. The existing sync status enum is extracted unchanged for hostless coverage, with no identifier or wire changes.

Final recovery-copy review: Today’s off state describes following the local schedule without promising that independent remote controls cannot lock the Mac. Uninstall failure uses the product action as its heading, with specific diagnostics retained. Unavailable remote locks offer Get Curfew using the shared production website origin rather than a duplicated URL. `PresentationStateTests.offAndRecoveryCopy` failed first; the unavailable-feature screenshot asserts its website action. Enforcement, uninstall order, and account behavior are unchanged.

- [-] Verify the native menu-bar popover on the isolated runner: shared atmospheric
  contrast tokens, state-specific setup action, accessible live status, and actual
  popover captures in both appearances. Visual feedback remains pending.

- [x] Hide the menu extension action when Curfew is off, including scheduled
  warning states; regression observed failing first and isolated UI fixture added.

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

- [x] Reject exhausted AI extension grants in both manual and automatic approval.
  Both actual-model regression cases failed on remote run 38114876113 before
  implementation. Granting minutes now requires successful tracker consumption;
  rejection refreshes the displayed allowance and records a denied extension.
  Consent explains the weekly limit and disables approval; remote verification
  of the final guard and its four visual captures remains required before merge.

## Website visual identity release

- [x] Group current legal headings and publication/effective metadata, keep the
  update notice concise, and label archived privacy-table values on narrow
  screens without changing archived policy prose.

- [x] Bring the Curfew landing, legal pages, Download, and Support onto one
  token-based, responsive light/dark design shell in the current Astro site.
  Preserve the existing policy text and Mintlify integration.
- [x] Remove the standalone MCP fixture from marketing. The connection diagram
  and copy identify Claude, ChatGPT, and Codex without claiming a captured
  conversation.
- [ ] Add a real assistant-host conversation capture after an actual Curfew tool
  interaction is available and reviewed.
- [ ] Confirm account route ownership and the full hosted sign-in/recovery flow
  before presenting the account UI as a production-ready entry point.
- [-] Replace broken marketing guide links with published Mintlify destinations
  and add the missing installation, schedule, exception, and account guides.
  Accept hosted Mintlify publication and landing links through the selected
  frontend. Keep the old first-party HTML guide for existing bookmarks until the
  Mintlify subpath proxy is accepted.

- [x] Use the same native hosting configuration for local website preview and
  Workers deployment, with Mintlify enabled in staging and an explicit local HTML
  guide mode for the existing browser fixture.
- [x] Retire Pages publication, preview and middleware compilation. Retain ordinary
  static artifacts and package genuine signed feeds through native Workers builds;
  preserve account, licensing, sync and native release ownership.

## 19. User-facing documentation and Plus launch

- [x] Replace Mintlify developer guides with setup, daily-use, Plus, integration,
      and recovery help. Preserve `/licensing`, `/mcp-guide`, and `/cli` bookmarks.
- [x] Explain activation in Settings → About, confirmation-page key delivery,
      offline/subscription access, deactivation versus cancellation, and support.
- [x] Correct purchase-confirmation help and errors; a failed key fetch must not
      claim that payment succeeded or that the key is in a receipt email.
- [x] Add failing-first documentation regression coverage in
      `scripts/user-docs.test.mjs` for user journeys, local links, activation,
      recovery, assistant privacy, and upcoming-feature availability.
- [x] Audit all 15 guides and purchase-confirmation copy for self-narration,
      redundant explanations, and unnecessary comparisons. Keep direct product
      facts, instructions, and consequential limits; add an editorial regression.
- [ ] Complete the signed-release, provider, visual, commercial-policy, and
      hosted-site acceptance rows in `Documentation/user-docs-launch.md` before
      publishing Plus launch claims. Source content and local checks are not
      acceptance of a working purchase or enabled CloudKit/Calendar features.
- [ ] Reconcile the app's email-key hint and historical privacy/terms copy with
      actual delivery, network activity, and owner-reviewed launch terms.

## Domain migration to thecurfew.app

- [x] Document protected owner-testing phases, Apple-first authenticator/recovery bootstrap, private policy input/expiry, socket and write deadlines, retained cf D1 migration history and isolated staging rehearsal.

- [-] Centralize environment configuration, remove protocol hostname constants, adopt pinned cf, derive native/web/service endpoints, and retire old traffic. See `domain-migration.md`.
- [ ] Complete authenticated provider preflight, account recovery audit, signed release, backups, coordinated production cutover and live acceptance. Local changes do not establish deployment.

- [x] Bind signed candidate provenance to the shared endpoint manifest and retain the newer release credential cleanup and unsigned quality checks.
- [x] Inventory Cloudflare access through the pinned CLI using existing CI credentials without changing infrastructure or printing secret values.

- [x] Document the Email Sending CLI exception, readiness validation before production mutations, and the cf Durable Object rollback constraint in the domain migration runbook.

- [x] Keep the public policy announcement below the navigation at wide and narrow widths; keep current policy copy focused on user choices, rights, sharing, and retention. Version changed stylesheets by their content so normal reloads receive the correction.

## 20. Plus activation and purchase restoration

- [-] End checkout with **Activate in Curfew**, verify and save the signed key,
      and show the result in Settings → About. Keep manual key entry available.
- [-] Offer **Restore Purchase…** using proof at the purchase inbox, bounded
      requests, short-lived links, current subscription keys, and safe retries.
- [x] Reject unpaid completed checkouts. Backfill old paid purchases by resending
      their already processed, signed Stripe event without replacing the key.
- [x] Reject other product payments; restore renewed/canceled subscriptions and
      legacy lifetime keys. Preserve fresh activations during background refresh
      and prevent canceled restore requests from closing a subsequent sheet.
- [x] Render opt-in, sender-restricted recovery configuration for the existing
      issuer deployment; keep recovery disabled until provider setup is selected.
- [x] Repair historical paid periods through signed invoice replay, decode UTF-8
      legacy inboxes, and select immutable periods during concurrent delivery.
      Cancel queued native activation before making a redemption request.
- [x] Pair development activation and subscription refresh with the fixed staging
      issuer; production continues to use its fixed production issuer.
- [x] Replace the unreliable manual-key disclosure with an accessible button
      and identify its text field; hosted UI test passes at `8399b8a4`.
- [x] Host purchase acceptance on the existing website staging Worker at its
      dedicated hostname; deploy a checksum-verified static artifact without
      transferring package or Cloudflare credentials.
- [x] Identify the retained staging signer through public-only health metadata
      and verify the actual paid sandbox envelope against it. Pin development
      builds to that signer; keep production trust fixed to its original key.
- [x] Select license trust, issuer and URL scheme from build identity, ignoring
      inherited helper flavor overrides in the production app.
- [x] Deploy restricted staging restore email and verify actual inbox delivery
      with SPF, DKIM and DMARC passing. Native restoration remains pending.
- [x] Verify the real Stripe test-mode checkout, inbox restoration and native
      Debug activation, including an inactive cold launch and saved entitlement
      after normal relaunch.
- [x] Verify owner-clicked activation and retained entitlement in the exact
      signed Studio Dev candidate, using its existing signing profile.
- [x] Verify signed native restoration from its real inbox link. The owner-clicked
      handoff shows active, verified lifetime access in the exact candidate.
- [-] Configure the GitHub production release path. Known team/account IDs are
      saved; the authenticated Studio notarization issuer is now configured.
      Approved dedicated Apple signing/notarization credentials are configured;
      Release app/widget/verifier now use the verified Studio team. Deployment-token
      setup, Sparkle pair verification and the Workers appcast path remain.
- [x] Derive the Release updater public key from its retained signing seed,
      verify the exported app embeds it, and sign the appcast before publishing
      the DMG. Production-secret execution and website publication remain pending.
- [x] Save and verify the required Curfew SKU metadata on both existing live
      Stripe payment links before the issuer's strict paid-checkout guard ships.
- [x] Configure the owner-approved Pages-only production publication credential
      in Curfew Actions; verify account status and access to the existing project.
- [ ] Verify the existing Stripe Test mode resources, webhook and staging-only
      storage before further purchase acceptance. Keep shared settings untouched;
      an additional general sandbox is optional for this existing integration.
      Deploy the locally tested expected-mode guard only after the intended
      provider bindings are reviewed. Live Stripe changes and production
      purchase-service publication require explicit owner direction.
- [x] Add local webhook/configuration rejection for wrong-mode signed events,
      replay/backfill, malformed flags and missing mode configuration before KV
      access. Staging Worker Build passes at `e6fc60c9`; runtime mode read-back
      and webhook acceptance remain pending.
- [x] Add a read-only, sanitized Stripe-mode health field for runtime staging
      verification without exposing credentials or purchase data. Ten mode/signer
      cases fail first and pass locally; hold the diagnostic push for review.
- [x] Isolate the lifecycle reconciliation fixture's license store from the real
      saved sandbox purchase; retain its free-to-Plus assertions.
- [ ] Ship the verified client/service/site together, then update published help
      to the new flow. Keep the public sale gate closed until purchase acceptance.
      `Documentation/plus-activation.md` records boundaries and remaining proof.

## Plus activation deployment integration

- [x] Derive activation and renewal origins from the installed build's deployment
  profile and preserve retired-host denial and deployment health identity.
- [x] Include the restricted restore sender, matching portal, isolated rate limits,
  and explicit payment mode in the native license deployment configuration.
- [-] Validate the integrated app and website candidate, then complete signed
  distribution and hosted purchase/restore acceptance before advertising the flow.

- [x] Retain separate production/staging website artifacts and verify purchase
  issuer/scheme pairing before staging deployment and production publication.
- [x] Validate restore portals against the issuer's deployment profile and pair
  local purchase pages with the native development app's retained staging issuer.
- [x] Pin the purchase environment in local website deployment commands and reject
  mismatched checkout or restore pages before invoking provider build/deploy. Pin
  the provider asset directory to the same verified output.
- [x] Route staging purchase recovery to the protected frontend independently of
  the account portal, with validated and isolated purchase origin configuration.
- [x] Use the purchase website for native purchase entry and checkout
  confirmation. Reject test credentials in the legacy production bootstrap
  before any provider access.
