# Curfew Implementation TODOs

Source: [`Documentation/plan.md`](./plan.md)
Test Matrix: [`Documentation/todo-test-matrix.md`](./todo-test-matrix.md)
Owner: Willie + Claude
Status legend: `[ ]` todo, `[-]` in progress, `[x]` done

> **v0.1 launch status (2026-08-01):** Core enforcement, flexible schedules,
> CLI, user-approved MCP requests, user-confirmed reflections, CI/release
> scaffolding, and the landing site are implemented. Release builds enable only
> the local MCP integration; CloudKit, Calendar, WidgetKit, and the privileged
> helper remain disabled pending production Apple provisioning and signed-artifact
> validation. The production license issuer is deployed and its envelope-v2
> health endpoint is live, but the landing sale gate remains closed: no
> production checkout-to-license delivery has been proven from a signed app
> release. Items below marked `[ ]` are external release gates or v0.2+ targets
> unless noted otherwise.

> **Public MCP guide:** `landing/docs.html` is the current public setup guide. It
> uses a documentation shell (section navigation plus an article column), not
> the marketing-page layout.
> The repository-owned Mintlify source under `docs/` remains unpublished until
> a deliberate deployment source is configured; it must stay aligned with the
> public guide in the meantime.

> **Marketing capture safety:** `scripts/capture-marketing.sh` launches and
> captures only its own fixture process. It never kills an existing Curfew
> process or substitutes a full-screen desktop capture when no fixture window
> is found.

---

## 0. Foundation and Project Structure

- [x] Create `CurfewKit` SPM library for shared domain models (Sources/CurfewKit/). App/CLI/MCP all depend on it via public types.
- [x] Convert app shell to a standard macOS app window (`LSUIElement = false`) with menu bar quick access.
- [x] Default debug/Xcode launch starts with enforcement disarmed unless explicitly enabled.
- [x] Add a dedicated app launch coordinator so app startup orchestration is isolated from scene composition.
- [x] Add targets for `curfew-mcp`, `curfew-ctl`, and WidgetKit extension. (`curfew-mcp`, `curfew-ctl`, and `CurfewWidget` are wired in Xcode. Privileged helper → v0.2)
- [-] Configure entitlements: App Group, CloudKit, notifications, accessibility-related requirements. (The conservative v0.1 Release carries only App Group and Apple Events for the shipped core. CloudKit and APS stay out until their feature flags are enabled after external provisioning + manual signed-build validation in `Documentation/RELEASE.md`.)
- [x] Define centralized app constants (`AppGroup`, bundle IDs, CloudKit record names via SharedPaths.swift).
- [x] Add feature flags for deferred modules (widget/cloud/MCP/calendar/privileged helper) with safe defaults off.

## 1. Schedule + Enforcement Core

- [x] Implement weekly schedule model (per-day end time, unlock time, day-off support). The Settings/onboarding copy now frames these as "Work ends" and "Work resumes" so the editable times line up with the actual enforcement window.
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
- [x] Respect accessibility settings: VoiceOver, reduce motion, reduce transparency.

## 4. Shutdown Manager

- [x] Implement optional auto-shutdown delay setting (1-60 min, default 10).
- [x] Show lockout countdown UI for shutdown.
- [x] Request graceful app termination before shutdown.
- [x] Implement shutdown retry once after 60 seconds on failure.
- [x] Keep lockout active if shutdown ultimately fails.
- [x] Gate auto-shutdown UI/runtime behind Apple Events capability; release builds carry the entitlement while debug/ad-hoc builds hide the feature. The Settings panel and generated Info.plist now explain that Curfew asks `System Events` to shut down the Mac, and a denied Automation prompt now keeps lockout active without retrying while pointing users to **Privacy & Security → Automation → Curfew → System Events**.

## 5. Bypass Protection + Privileged Layer

> v0.1: `PersistentLockdown` ships a user-space respawning LaunchAgent using
> `KeepAlive.PathState`. Not automatically installed; v0.2 hardens with SMAppService.

- [-] Package a real `curfew-daemon` helper for `SMAppService` install/status validation; jailbreak detection + shutdown enforcement remain deferred. (Packaging/UI are in-repo; signed-build install/reboot/uninstall validation remains an external release step. See `Documentation/RELEASE.md`.) (v0.2)
- [-] Persist lockout state through the LaunchDaemon sentinel path; root-owned write semantics still need signed-build/manual validation. (`Documentation/RELEASE.md` now captures the exact manual checks; the actual proof still requires a signed build.) (v0.2)
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
- [x] `scripts/gen-sparkle-keypair.sh` — local Ed25519 keygen with paste-into-Info.plist instructions.
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
- [x] Signed-build validation runbook for shutdown, widget, privileged helper, and CloudKit lives in `Documentation/RELEASE.md`. (Actual Apple-credential execution is still tracked by the remaining unchecked release/provisioning items.)
- [x] Landing page (`landing/`) — Cloudflare Pages deploy target.
- [x] Account-era landing contract — every public header links to the optional
      same-origin account portal, Android is labeled as coming soon, and the
      privacy, security, retention, purchase, recovery, and remote-unlock
      boundaries are published without implying that Google Play Services are
      required. Approved Curfew service hostnames are enforced in CI.
- [x] Mintlify documentation source lives in `docs/`.
- [ ] Connect and publish the Mintlify source, then configure the Pages
      `/docs` reverse proxy and complete the required custom-domain TXT
      verification. Keep the current hosted content intact until its
      replacement is explicitly authorized. (external launch gate)
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
- [x] **M3** — Accessibility-trust state polled each tick; Overview banner deep-links to System Settings.

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
- [x] **A1** — `LockoutDeadlineRecord` is now the single source of truth for "am I locked"; overlay/sentinel/daemon all derive from it.

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

## 18. Verification (v0.1 release candidate)

- [x] Pin both SwiftPM entry points to the immutable pre-1.0
      `curfew-protocols` 0.2.3 release.
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
- [x] Restored CI demo-capture artifacts by forwarding the screenshot job's
  unsigned build settings into `scripts/extract-screenshots.sh`.
