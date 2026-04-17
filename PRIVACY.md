# Privacy

Curfew is designed to store everything locally and request only the permissions it uses.

## What Curfew stores

| Data | Where | Retention |
|------|-------|-----------|
| Schedule, budgets, preferences | `~/Library/Application Support/Curfew/` (UserDefaults + SQLite) | Until you uninstall |
| Override and extension events | Same SQLite database | 52 weeks rolling |
| Activity log (lock/unlock/idle events) | Same SQLite database | 52 weeks rolling |
| License key (Pro) | `~/Library/Application Support/Curfew/` | Until you deactivate |

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

When enabled, your schedule and settings are stored in your private iCloud database (CloudKit). Hypertext Studio has no access to this data — it lives in your personal iCloud account, encrypted by Apple.

## MCP server

When `curfew-mcp` is running, AI assistants can read your enforcement state and request changes. Write operations require your explicit approval (configurable in Settings → Integrations). No data leaves your machine through this path.

## Contact

Questions: hello@hypertext.studio
