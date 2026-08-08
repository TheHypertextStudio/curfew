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
