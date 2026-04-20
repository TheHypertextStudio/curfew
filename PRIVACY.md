# Privacy

Curfew is designed to store everything locally and request only the permissions it uses.

## What Curfew stores

| Data | Where | Retention |
|------|-------|-----------|
| Schedule, budgets, preferences | `~/Library/Preferences/studio.hypertext.curfew.plist` plus `~/Library/Group Containers/group.studio.hypertext.curfew/Curfew/widget-settings.json` for widget mirroring | Until you uninstall |
| Override and extension events | `~/Library/Group Containers/group.studio.hypertext.curfew/Curfew/activity.sqlite3` | 52 weeks rolling |
| Activity log (lock/unlock/idle events) | Same SQLite database | 52 weeks rolling |
| License key (Pro) | `~/Library/Preferences/studio.hypertext.curfew.plist` | Until you deactivate |

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
