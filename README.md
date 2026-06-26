# Curfew

**A hard stop for your Mac.** Define the work rhythm that fits your life — not only a standard job — and Curfew enforces its end with warnings, a full-screen overlay, and optional shutdown. No willpower required.

It's a commitment device, not a kernel-level lock: a determined user with a terminal can still get around it. The point is to make stopping the easy default, not to make it impossible.

Curfew is the first product from [Hypertext Studio](https://hypertext.studio), a product design lab working under the motto *mens et manus* — mind and hand.

---

## What it does

### Today (v0.1) — flexible work rhythms and hard end-of-work gates

- **Weekly schedule** with per-day work-end/resume times, day-off support, hours-based modes, and three editable presets (9-to-5, Startup Hours, Half Day).
- **Graduated warnings** at T-30, T-15, T-5, T-2, T-1 with configurable intervals and per-stage notifications.
- **Full-screen lockout** across every display and Space, with keyboard-shortcut interception (⌘⇥, ⌘Q, ⌘⌥Esc, …).
- **Extension budget** — 3 × 15 min per week, hold-to-confirm so accidental taps don't burn a slot.
- **"Convince me" overrides** — 2 × 30 min per week, 5-min cooldown, 50-char minimum justification, persistent log.
- **Optional auto-shutdown** after lockout with retry-once semantics.
- **This Week retrospective** — lockouts held, extensions/overrides used, current streak.
- **`curfew-ctl` CLI** — scriptable access to every status/override/budget operation. See [`curfew-ctl` usage](#curfew-ctl) below.
- **`curfew-mcp` MCP server** — AI assistants can negotiate with your focus rules from within a coding session. See [MCP setup](#mcp-setup) below.
- **User-confirmed reflections** — optional morning intentions and evening retrospectives use user-editable prompts, stay on the Mac, and are available to AI only through read-only MCP/CLI access.
- **Menu bar quick access** + first-launch onboarding.

Deferred Pro surfaces stay conservative in default/debug builds until their
signed-release entitlement and provisioning path has been validated.

### Near term (v0.2) — stronger enforcement
- Privileged helper via `SMAppService` (packaging landed; signed install/recovery validation still required).
- Localization, Sparkle autoupdate.

### Near term — reflection depth
Morning intent and evening retrospective are available now. Midday check-ins and on-device AI-generated prompt suggestions remain future work; agents will never write a user's reflections.

---

## MCP setup

`curfew-mcp` is a stdio MCP server bundled with Curfew. It lets AI assistants read your enforcement state and, with your approval, request extensions or overrides.

**Available tools:**

| Tool | Type | What it does |
|------|------|------|
| `curfew_status` | read | Current phase, time remaining, override state |
| `curfew_schedule` | read | Full weekly schedule |
| `curfew_budget` | read | Extensions and overrides remaining this week |
| `curfew_activity` | read | Recent activity log entries |
| `curfew_get_time_remaining` | read | Compact `{ minutes, phase, mode, trigger }` payload |
| `curfew_get_weekly_summary` | read | Device-attributed weekly rollup |
| `curfew_get_reflections` | read | User-authored reflections only; agents cannot write them |
| `curfew_request_extension` | write* | Ask for a time extension |
| `curfew_set_schedule` | write* | Update a single weekday (cannot weaken today without cooldown) |
| `curfew_request_status` | read | Poll a queued write request for approval/denial |

Two transports: stdio (default, used by Claude Desktop) and loopback-only Streamable HTTP on `127.0.0.1:9847` (opt-in, Settings → Advanced).

\* Write operations queue for user approval by default (configurable in Settings → Integrations → AI Consent Policy).

**Add to Claude Desktop:**

Open Curfew → Settings → Integrations, click "Copy Claude Desktop Config", and paste into `~/Library/Application Support/Claude/claude_desktop_config.json` under `mcpServers`.

Or manually:

```json
{
  "mcpServers": {
    "curfew": {
      "command": "/Applications/Curfew.app/Contents/Resources/curfew-mcp",
      "args": []
    }
  }
}
```

Restart Claude Desktop. Run `curfew_status` to verify.

---

## `curfew-ctl`

Command-line interface for scripting and power users.

```bash
# Current enforcement phase, time remaining, active override
curfew-ctl status
curfew-ctl status --json

# This week's schedule
curfew-ctl schedule show

# Extension and override budgets
curfew-ctl budget

# Recent activity log
curfew-ctl activity
curfew-ctl activity --days 7

# Request an override (prompts for confirmation)
curfew-ctl override --reason "shipping a fix, need 30 more minutes"
```

`curfew-ctl` is bundled at `Curfew.app/Contents/Resources/curfew-ctl`. Add it to your `$PATH`:

```bash
ln -s /Applications/Curfew.app/Contents/Resources/curfew-ctl /usr/local/bin/curfew-ctl
```

---

## Curfew Pro

Pro adds features with ongoing infrastructure cost. Upgrade at [curfew.hypertext.studio](https://curfew.hypertext.studio).

| Feature | Free | Pro |
|---------|------|-----|
| Schedule, warnings, lockout | ✓ | ✓ |
| Extension / override budgets | ✓ | ✓ |
| This Week retrospective | ✓ | ✓ |
| `curfew-ctl` CLI | ✓ | ✓ |
| `curfew-mcp` MCP server | ✓ | ✓ |
| **CloudKit multi-device sync** | — | Not enabled until production container validation |
| **WidgetKit widgets** | — | Not enabled until signed-release validation |
| **Calendar integration** | — | Not enabled until signed-release validation |

Pricing: **$20 flat**. License key is verified offline via Ed25519 — no account required after purchase.

---

## Install & run

Requires **macOS 26+** and **Xcode 26+** (Swift 6). The first release is
Tahoe-only; supporting earlier macOS versions is a deliberate future product
and compatibility decision.

```bash
git clone https://github.com/TheHypertextStudio/curfew
cd curfew
open Curfew.xcodeproj
```

Press ⌘R to run. First launch opens Getting Started, which walks through schedule, budgets, and permissions.

**Debug launches are safe by default** — enforcement stays disarmed unless you set `CURFEW_ENABLE_ENFORCEMENT=1`. Release builds arm on launch.

Release-only validation for shutdown, WidgetKit, the privileged helper, and
CloudKit is documented in [`Documentation/RELEASE.md`](Documentation/RELEASE.md).

---

## Development

This repo uses [`just`](https://github.com/casey/just) as a command runner — a simpler `make` that lets you run every common task without invoking `xcodebuild` directly.

```bash
brew install just swiftlint swiftformat
just --list       # show all recipes
just check        # format + lint + tests + Debug build (CI gate)
just test         # unit suite only
just format       # apply SwiftFormat in place
just dev          # build + launch
just kill         # kill any running Curfew process
```

`just check` is the full ship-gate — same command CI runs on every push. All PRs must pass it.

Contributor expectations and the TDD workflow live in [`AGENTS.md`](AGENTS.md).

---

## Architecture

```
CurfewKit/           Local Swift package (its own subfolder, so opening the repo
                     folder in Xcode resolves to Curfew.xcodeproj, not a package).
                     Curfew.xcodeproj links its CurfewKit library product into the
                     app, widget, and CLI tools — every consumer `import CurfewKit`.
  Sources/CurfewKit/   Pure domain logic, storage, settings, and MCP queue types —
                       schedule engine, budget tracker, warning stages, override
                       policy, activity store. No UI; fully unit-tested.
  Sources/curfew-ctl/    ArgumentParser CLI — reads shared storage; enqueues overrides.
  Sources/curfew-mcp/    MCP server (stdio transport, JSON-RPC 2.0).
  Sources/curfew-daemon/ Root-enforced shutdown when the app dies mid-lockout.

Curfew/Core/Features/  App-only features that depend on Apple frameworks —
                       IdleWatcher, LicenseGate, CalendarMonitor, CloudKit sync.

Curfew/App/      @MainActor app model, routing, overlay coordinator, key interceptor,
                 shutdown workflow, notification bridge, MCP request monitor.

Curfew/UI/       SwiftUI views — main window, settings, lockout overlay, onboarding.

CurfewWidget/    WidgetKit extension. Links CurfewKit and imports the Domain/Storage/
                 Settings types it needs; signed release/App Group validation still
                 requires a provisioned build.

CurfewTests/     Unit tests covering every CurfewKit module and app model behavior.
```

Each directory has a `*-module.md` summary and every type carries doc comments.

---

## License

[MIT](LICENSE) © Hypertext Studio.

Bug reports, design critique, and pull requests are welcome — open an issue.
