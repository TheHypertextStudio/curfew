# Curfew

**A hard stop for your Mac.** Set a schedule. When the clock runs out, your machine locks you out — warnings, then a full-screen overlay, then an optional shutdown. No willpower required.

Curfew is the first product from [Hypertext Studio](https://hypertext.studio), a product design lab working under the motto *mens et manus* — mind and hand.

---

## What it does

### Today (v0.1) — hard end-of-day gates

- **Weekly schedule** with per-day lock/unlock times, day-off support, and three presets (9-to-5, Startup Hours, Half Day).
- **Graduated warnings** at T-30, T-15, T-5, T-2, T-1 with configurable intervals and per-stage notifications.
- **Full-screen lockout** across every display and Space, with keyboard-shortcut interception (⌘⇥, ⌘Q, ⌘⌥Esc, …).
- **Extension budget** — 3 × 15 min per week, hold-to-confirm so accidental taps don't burn a slot.
- **"Convince me" overrides** — 2 × 30 min per week, 5-min cooldown, 50-char minimum justification, persistent log.
- **Optional auto-shutdown** after lockout with retry-once semantics.
- **This Week retrospective** — lockouts held, extensions/overrides used, current streak.
- **`curfew-ctl` CLI** — scriptable access to every status/override/budget operation. See [`curfew-ctl` usage](#curfew-ctl) below.
- **`curfew-mcp` MCP server** — AI assistants can negotiate with your focus rules from within a coding session. See [MCP setup](#mcp-setup) below.
- **Menu bar quick access** + first-launch onboarding.

### Near term (v0.2) — stronger enforcement
- Privileged helper via `SMAppService` (root-owned state, harder to bypass).
- Localization, Sparkle autoupdate.

### Long term — reflection gates
Morning intent, midday check-in, evening retrospective — lifecycle gates beyond just end-of-day. Design seams are already in the code (`gateKind` field in the activity log; generic MCP verbs).

---

## MCP setup

`curfew-mcp` is a stdio MCP server bundled with Curfew. It lets AI assistants read your enforcement state and, with your approval, request extensions or overrides.

**Available tools:**

| Tool | Type | What it does |
|------|------|------|
| `curfew.status` | read | Current phase, time remaining, override state |
| `curfew.schedule` | read | Full weekly schedule |
| `curfew.budget` | read | Extensions and overrides remaining this week |
| `curfew.activity` | read | Recent activity log entries |
| `curfew.request_extension` | write* | Ask for a time extension |
| `curfew.request_override` | write* | Request a full override with a reason |
| `curfew.request_status` | read | Poll a queued write request for approval/denial |

Focus-session tools (`curfew.start_focus_session`, `curfew.end_focus_session`) are planned for v0.2 once the focus-mode schema stabilises.

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

Restart Claude Desktop. Run `curfew.status` to verify.

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
| **CloudKit multi-device sync** | — | ✓ |
| **WidgetKit widgets** | — | ✓ |
| **Calendar integration** | — | ✓ |

Pricing: **$19 early-bird / $29 list**. License key is verified offline via Ed25519 — no account required after purchase.

---

## Install & run

Requires **macOS 15+** and **Xcode 26+** (Swift 6).

```bash
git clone https://github.com/hypertext-studio/curfew
cd curfew
open Curfew.xcodeproj
```

Press ⌘R to run. First launch opens Getting Started, which walks through schedule, budgets, and permissions.

**Debug launches are safe by default** — enforcement stays disarmed unless you set `CURFEW_ENABLE_ENFORCEMENT=1`. Release builds arm on launch.

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
Curfew/Core/     Pure domain logic — schedule engine, budget tracker, warning stages,
                 activity recorder, override policy. No UI imports; fully unit-tested.

Curfew/App/      @MainActor app model, routing, overlay coordinator, key interceptor,
                 shutdown workflow, notification bridge, CloudKit sync, CalendarMonitor.

Curfew/UI/       SwiftUI views — main window, settings, lockout overlay, onboarding.

CurfewWidget/    WidgetKit extension (Pro). Small/medium/large. Reads shared UserDefaults.

Sources/
  curfew-ctl/    ArgumentParser CLI. Symlinks shared Core files; no library module.
  curfew-mcp/    MCP server (stdio transport). Same symlink strategy.

CurfewTests/     ~90 unit tests covering every Core module and app model behavior.
```

Each directory has a `*-module.md` summary and every type carries doc comments.

---

## License

[MIT](LICENSE) © Hypertext Studio.

Bug reports, design critique, and pull requests are welcome — open an issue.
