# Privacy

Curfew is designed to store everything locally and request only the permissions it uses.

## What Curfew stores

| Data | Where | Retention |
|------|-------|-----------|
| Schedule, budgets, preferences | `~/Library/Preferences/studio.hypertext.curfew.plist` plus `~/Library/Group Containers/group.studio.hypertext.curfew/Curfew/widget-settings.json` for widget mirroring | Until you uninstall |
| Override and extension events | `~/Library/Group Containers/group.studio.hypertext.curfew/Curfew/activity.sqlite3` | 52 weeks rolling |
| Activity log (lock/unlock/idle events) | Same SQLite database | 52 weeks rolling |
| Audit log (what Curfew did and why) | `~/Library/Logs/Curfew/curfew-app.jsonl`, plus `/Library/Logs/Curfew/curfew-daemon.jsonl` when the privileged helper is installed | 90 days, or 25 MB per file, whichever comes first |
| License key (Pro) | `~/Library/Preferences/studio.hypertext.curfew.plist` | Until you deactivate |
| Presence verdict (opt-in camera) | Memory only — one yes/no answer plus a timestamp | Until the next reading, or until the camera stops |

## The audit log

Curfew keeps a plain-text record of its own decisions — phase changes, lockout
start and end, schedule changes and the cooldown applied to them, grants and
refusals, consent verdicts on AI requests, and every action the privileged
daemon takes. It exists so you can answer "what did Curfew do to my Mac last
night, and why" without trusting the app's own UI to tell you.

It never contains your reflection entries and never contains your override
justifications. For an override, Curfew records that you wrote one, how long it
was, and a short fingerprint — never the words. The full format is documented
in [`Documentation/audit-log.md`](Documentation/audit-log.md).

Nothing reads this file. It is written and never sent anywhere.

## Camera presence detection (opt-in, off by default)

Curfew can check the camera for a person, so it can tell whether you stepped
away or are sitting there reading. **This is off unless you turn it on**, in
Settings → Enforcement → Presence. A fresh install, an upgrade from a version
that didn't have it, and a restored backup all leave it off; there is no
migration that turns it on.

While it is on:

- **Captured:** video frames, about one analysed every two seconds, held in
  memory only for as long as it takes to look at them. Frames arriving in
  between are discarded without being read.
- **Derived:** one yes-or-no answer — was a human shape visible — and the time
  it was taken. Curfew detects a person; it does not identify one. There is no
  face print, no template, and nothing to compare a face against.
- **Retained:** that yes-or-no answer, until the next one replaces it. Images
  are never written to disk, never encoded, and never leave your Mac.
- **Recorded:** changes between working, present-but-idle, and away go to the
  audit log, along with every time the camera starts and stops. Images never do.

Turning it off ends the capture session and releases the camera. macOS shows
its own green camera light whenever any app is using the camera; Curfew also
shows its own indicator in the menu-bar popover and in Settings while its
session is live, so you can tell which app turned the light on.

Full detail, including what the feature deliberately cannot do, is in
[`Documentation/presence-detection.md`](Documentation/presence-detection.md).

## What Curfew does NOT do

- No analytics, telemetry, or crash reporting.
- No network requests except: iCloud sync (Pro, opt-in) and license key verification (one-time, offline after first check).
- No access to your files, browser history, or app content.

## Permissions requested

| Permission | Why |
|------------|-----|
| Calendars (Pro) | Read today's events for contextual display. Never written to. |
| Notifications | Warning countdowns and lockout alerts. |
| Accessibility (optional) | Keyboard shortcut interception during lockout. |
| Camera (optional, off by default) | Detect whether a person is at the Mac. Requested only when you turn presence detection on. No images stored or sent; nobody is identified. |

## iCloud sync (Pro)

When enabled, Curfew writes four record types to **your private CloudKit database**:

- `Settings` — schedule, budgets, preferences, warning intervals.
- `Device` — per-Mac registration (device name, first-seen / last-seen).
- `DeviceActivity` — a 60-second heartbeat so the other Macs you use can tell which is active. Contains only a timestamp and an active boolean; no cursor tracking, no app activity, no keystrokes.
- `LockoutState` — current phase + warning timestamps so a Mac joining mid-warning aligns with whichever Mac entered warning first.

Heartbeats older than 7 days are pruned. All other records survive until you sign out of iCloud or uninstall. Hypertext Studio has no access — everything lives in your personal iCloud account, encrypted by Apple.

## MCP server

When `curfew-mcp` is running, AI assistants can read your enforcement state and request changes. Write operations require your explicit approval (configurable in Settings → Integrations). No data leaves your machine through this path.

## Contact

Questions: hello@hypertext.studio
