# Curfew Implementation TODOs

Source: [`Documentation/plan.md`](./plan.md)
Test Matrix: [`Documentation/todo-test-matrix.md`](./todo-test-matrix.md)
Owner: Willie + Claude
Status legend: `[ ]` todo, `[-]` in progress, `[x]` done

> **v0.1 status (2026-04-17):** Core enforcement, CLI, MCP server, Pro licensing,
> CloudKit sync, WidgetKit, CalendarMonitor, CI/release workflows, and landing page
> are complete. Items below marked `[ ]` are v0.2+ targets unless noted otherwise.

---

## 0. Foundation and Project Structure

- [x] Create `CurfewKit` SPM library for shared domain models (Sources/CurfewKit/). App/CLI/MCP all depend on it via public types.
- [x] Convert app shell to a standard macOS app window (`LSUIElement = false`) with menu bar quick access.
- [x] Default debug/Xcode launch starts with enforcement disarmed unless explicitly enabled.
- [x] Add a dedicated app launch coordinator so app startup orchestration is isolated from scene composition.
- [x] Add targets for `curfew-mcp`, `curfew-ctl`, and WidgetKit extension. (Privileged helper → v0.2)
- [-] Configure entitlements: App Group, CloudKit, notifications, accessibility-related requirements.
- [x] Define centralized app constants (`AppGroup`, bundle IDs, CloudKit record names via SharedPaths.swift).
- [x] Add feature flags for deferred modules (widget/cloud/MCP/calendar/privileged helper) with safe defaults off.

## 1. Schedule + Enforcement Core

- [x] Implement weekly schedule model (per-day end time, unlock time, day-off support).
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

## 5. Bypass Protection + Privileged Layer

> v0.1: `PersistentLockdown` ships a user-space respawning LaunchAgent using
> `KeepAlive.PathState`. Not automatically installed; v0.2 hardens with SMAppService.

- [x] Implement privileged helper and LaunchDaemon via `SMAppService`. (v0.2)
- [x] Persist lockout state in root-owned path. (v0.2)
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

- [x] Single `CKRecord` in private database — `payload: Data` + `modifiedAt: Date`.
- [x] Last-write-wins conflict resolution on `modifiedAt`.
- [x] Graceful handling of missing container / unauthenticated (`CKError.isExpectedAbsence`).
- [x] Gate behind `featureFlags.cloudSyncEnabled` + `licenseGate.isProUnlocked`.
- [x] `cloudKitSyncEngine.push()` on every settings mutation.
- [ ] CloudKit container provisioned in App Store Connect. (morning task)
- [x] Sync status UI in Settings → Devices. (v0.2)
- [ ] Device list management. (v0.2)

## 11. Activity Log + Retrospective

- [x] SQLite storage with 52-week rolling retention (direct `sqlite3` C API, no GRDB).
- [x] `ActivityRecorder` writes lifecycle/extension/override events.
- [x] `ActivityRollups` computes daily/weekly aggregates.
- [x] `IdleWatcher` detects idle periods (5-min cutoff).
- [x] "This Week" view in app UI.
- [x] CSV export. (v0.2)
- [ ] Device-attributed insights. (v0.2)

## 12. WidgetKit (Pro)

- [x] Small widget: phase icon + time remaining + phase label.
- [x] Medium widget: phase + remaining + schedule window.
- [x] Large widget: full status, lock/unlock times.
- [x] `CurfewWidgetProvider` reads shared UserDefaults, refreshes every 5 minutes.
- [x] Gate behind `featureFlags.widgetKitEnabled` + `licenseGate.isProUnlocked`.
- [ ] Xcode Widget Extension target wired in project. (requires Xcode UI)
- [x] Wire timeline updates to enforcement phase transitions. (v0.2)

## 13. MCP Server (`curfew-mcp`)

- [x] `curfew-mcp` executable target (stdio MCP server, JSON-RPC 2.0).
- [x] Read tools: `curfew.status`, `curfew.schedule`, `curfew.budget`, `curfew.activity`, `curfew.request_status`.
- [x] Write tools (queued by default): `curfew.request_extension`, `curfew.request_override`.
- [ ] Write tools: `curfew.start_focus_session`, `curfew.end_focus_session`. (v0.2 — focus-mode schema TBD)
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

## 15. Pro Licensing

- [x] Ed25519 offline license key verification (`LicenseGate` + `CryptoKit`).
- [x] License key format: `{base64url(payload)}.{base64url(signature)}`.
- [x] `LicenseView` in Settings — activate/deactivate, Pro status display.
- [x] `ProGate<Content>` generic view wrapper gates CloudKit, WidgetKit, Calendar.
- [x] `PurchasePromptView` — feature name, description, upgrade link.
- [x] `scripts/gen-license-keypair.sh` — Ed25519 keypair generation.
- [x] `scripts/issue-license.ts` — Cloudflare Worker: Lemonsqueezy webhook → signed key.
- [ ] Placeholder public key replaced with production key. (morning task)
- [ ] Lemonsqueezy store + product + webhook configured. (morning task)

## 16. Onboarding

- [x] First-launch getting-started window.
- [x] Persist one-time first-launch setup state.
- [x] First-run flow: welcome, schedule, budgets, permissions, confirmation.
- [x] Anti-bypass: onboarding mutations route through `queueScheduleUpdate`.
- [x] Onboarding relaunch from Settings.

## 17. Distribution and Operations

- [x] `.github/workflows/ci.yml` — format + lint + test + build on push/PR.
- [x] `.github/workflows/release.yml` — archive + sign + notarize + DMG on tag push.
- [x] `scripts/build-dmg.sh` — `create-dmg` wrapper.
- [x] MIT `LICENSE` file.
- [x] README rewrite: three-horizon pitch, MCP setup, CLI usage, Pro features, architecture.
- [x] `CONTRIBUTING.md`, `PRIVACY.md`, `Documentation/ARCHITECTURE.md`, `Documentation/RELEASE.md`.
- [x] Landing page (`landing/`) — Cloudflare Pages deploy target.
- [ ] Apple Developer credentials in GitHub secrets. (morning task)
- [ ] Cloudflare Pages deployment. (morning task)
- [ ] Homebrew Cask. (v0.2)
- [x] Sparkle autoupdate. (v0.2)

## 18. Verification (v0.1 release candidate)

- [x] `just check` passes (format + lint + tests + Debug build).
- [x] `xcodebuild archive` succeeds unsigned locally.
- [x] `./curfew-ctl status` prints live state.
- [x] `./curfew-mcp` responds to `tools/list` over stdio.
- [ ] Paste test license → Pro features unlock; remove → re-gate.
- [ ] Lockout smoke test: set curfew 5 min ahead, observe overlay, recover via override.
- [ ] MCP smoke test: paste Claude Desktop config, run `curfew.status` from Claude.
- [ ] Landing page links all resolve.
