# Curfew

**A hard stop for your Mac.** Set a schedule. When the clock runs out, your machine locks you out — warnings, then an overlay, then an optional shutdown. No willpower required.

Curfew is the first product from [Hypertext Studio](https://hypertext.studio), a product design lab working under the motto *mens et manus* — mind and hand.

> Curfew is in active development. v0.1 covers the core commitment loop (schedule → warnings → lockout → overrides) on a single Mac. Multi-device sync, AI-controlled gating, and an MCP server are on the roadmap — see [Roadmap](#roadmap).

---

## Why it exists

Willpower loses against interesting problems. Every focus app that relies on *remembering to stop* eventually becomes a todo app with extra steps.

Curfew takes a different approach: **you make the decision once, while you're thinking clearly, and the machine enforces it later**. Schedule changes that weaken the rules sit in a 24-hour cooldown before taking effect. Overrides cost a deliberate "convince me" flow with a typed justification and a hold-to-confirm. Accidental escape gets boring fast.

## What it does today

- **Weekly schedule** with per-day lock/unlock times, day-off support, and three starting presets (9-to-5, Startup Hours, Half Day).
- **Graduated warnings** at T-30, T-15, T-5, T-2, and T-1, each with configurable intervals and per-stage notification behavior.
- **Full-screen lockout** on every display and space, with keyboard-shortcut interception for the usual bypass attempts (⌘⇥, ⌘Q, ⌘⌥Esc, …).
- **Extension budget** (default: 3 × 15 minutes per week) with hold-to-confirm so accidental taps don't burn a slot.
- **"Convince me" overrides** (default: 2 × 30 minutes per week) with a 5-minute cooldown, 50-character minimum justification, and a persistent event log.
- **Optional auto-shutdown** after lockout with retry-once semantics.
- **This Week retrospective** — rolling summary of lockouts held, extensions/overrides used, and current streak.
- **Menu bar quick access** + first-launch onboarding that walks through schedule, budget, and permissions.

## Roadmap

On the way, in rough order:

- **MCP server** — expose `curfew.status`, `curfew.budget`, `curfew.request_extension`, and friends so AI assistants (Claude, Cursor, …) can negotiate with your focus rules from within a coding session.
- **`curfew-ctl`** — CLI for scripting and automation.
- **CloudKit sync + device-attributed retrospective** — keep one budget across multiple Macs.
- **WidgetKit widgets** — countdown + streak on the desktop.
- **Calendar awareness** — detect meetings that overlap curfew and proactively surface extension prompts.
- **Privileged helper via `SMAppService`** — stronger bypass protection with root-owned state; v0.1 uses a user-space enforcement path that's honest about its limits.
- **Reflection gates** beyond end-of-day — morning intent, midday check-in, evening retrospective.

## Install & run

Requires macOS 15+ and Xcode 26+.

```bash
git clone https://github.com/hypertext-studio/curfew
cd curfew
open Curfew.xcodeproj
```

Press ⌘R to run. First launch opens a Getting Started window that walks through schedule, budgets, and permissions.

**Debug launches are safe by default** — enforcement stays disarmed unless you set `CURFEW_ENABLE_ENFORCEMENT=1`. Release builds arm on launch; set `CURFEW_SKIP_ENFORCEMENT=1` to disable for QA.

## Development

This repo supports using [`just`](https://github.com/casey/just) to run every common developer task from the command line without invoking `xcodebuild` directly.

```bash
brew install just swiftlint swiftformat
just --list      # show every recipe
just check       # full ship-gate: format + lint + tests + Debug build
just test        # unit suite only
just format      # apply SwiftFormat in place
just dev         # build + launch the app
just kill        # kill any running Curfew process
```

`just check` is also what CI runs on every push.

Contributor expectations and the full test-driven workflow live in [`AGENTS.md`](AGENTS.md).

## Architecture at a glance

- `Curfew/Core/` — pure domain logic (schedule engine, budget tracker, warning stages, activity log, override policy). No UI dependencies; unit-tested in isolation.
- `Curfew/App/` — the `@MainActor` app model, routing, overlay coordinator, key interceptor, shutdown workflow, and notification bridge.
- `Curfew/UI/` — SwiftUI views for the main window, settings, lockout overlay, and onboarding flow.
- `CurfewTests/` — ~90 unit tests covering every Core module and the observable behavior of the app model.

The code carries `*-module.md` summaries in each directory and inline doc comments on every type and non-trivial property.

## License

Curfew is released under the [MIT License](LICENSE). © Hypertext Studio.

Contributions, bug reports, and design critique are all welcome — open an issue or a pull request.
