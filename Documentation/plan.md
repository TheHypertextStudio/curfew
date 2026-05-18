# Curfew — Product Requirements Document

**Version:** 1.0
**Author:** Willie
**Last Updated:** February 2026
**Status:** Draft

> **Repo split:** as of May 2026, Curfew is three repos — `curfew` (this one, the macOS app), `curfew-sync` (the Cloudflare Sync coordinator), and `curfew-protocols` (the versioned wire-format contract). This PRD covers the **product** scope, which spans all three. Where this doc mentions implementation details for the Sync coordinator (F-section TBD), the canonical implementation spec is `curfew-sync/Documentation/ARCHITECTURE.md`. MCP tool schemas referenced as inline Swift types are migrating to `curfew-protocols`; see `AGENTS.md` for the migration discipline.

---

## Executive Summary

Curfew is a macOS-native app that enforces healthy work-life boundaries by hard-locking users out of their computers at a configurable time each day. Unlike existing digital wellbeing tools that offer gentle suggestions easily dismissed, Curfew acts as a commitment device — a contract between your present self and your future self. It escalates from friendly reminders to a full-screen lockout, optional shutdown, and bypass-resistant persistence across restarts. Curfew syncs across all of a user's Macs via CloudKit, tracks cumulative work time across devices, and exposes an MCP server interface for AI assistant integration. The app is open source and distributed as a notarized `.dmg`.

---

## Problem Statement

Knowledge workers routinely override their own intentions to stop working. Existing tools (Screen Time, Focus modes, website blockers) rely on the user's willpower at the moment of decision — the exact moment willpower is lowest. There is no mainstream macOS tool that functions as a hard enforcer: one that respects the decision you made at 9 AM when it's 9 PM and you're "just finishing one more thing."

Curfew solves this by treating your schedule as a binding commitment, not a suggestion.

---

## Target Users

- Knowledge workers and developers who struggle to stop working
- Remote workers without natural office-closing signals
- Founders and freelancers with no external structure
- Anyone recovering from or preventing burnout
- Users who want AI-assisted time management via MCP-compatible tools

---

## Design Philosophy

### Core Principles

1. **Hard enforcement, humane delivery.** The lockout is non-negotiable, but the experience should feel like a caring friend, not a prison warden. Every screen, notification, and animation should communicate: *"You did great work. Now rest."*

2. **Commitment over willpower.** Users configure their schedule when they're rational (morning, weekend, setup). The app honors that decision even when the user wants to override it at 11 PM.

3. **Progressive escalation.** Curfew never surprises. It gives ample, escalating warnings so the user always has time to save work and wrap up gracefully.

4. **Transparency over obscurity.** The app is open source. It asks for specific permissions and explains exactly why. The bypass protection exists to create friction against impulse, not to trap the user — there is always an emergency escape hatch, but it's deliberately inconvenient.

5. **Native and minimal.** No Electron. No menubar clutter. It should feel like it shipped with macOS.

---

## Platform Requirements

- **OS:** macOS 14 (Sonoma) minimum, macOS 15 (Sequoia) recommended
- **Architecture:** Universal Binary (Apple Silicon + Intel)
- **Distribution:** Notarized `.dmg` via GitHub Releases (primary), Homebrew Cask (secondary), landing page at curfew.app
- **Updates:** Sparkle framework with appcast hosted on GitHub Releases
- **Signing:** Apple Developer ID (Developer ID Application + Developer ID Installer certificates)
- **Notarization:** Apple notarytool via automated CI pipeline
- **Frameworks:** SwiftUI, AppKit, WidgetKit, CloudKit, UserNotifications, EventKit, ServiceManagement, XPC

---

## Feature Specification

### F1: Schedule Configuration

**Description:** Users define their work window and lockout period through a clean, intuitive settings interface.

**Requirements:**

- Configurable work-end time (e.g., 6:00 PM) per day of the week
- Configurable unlock time (e.g., 8:00 AM next day) per day of the week
- Support for different schedules on different days (weekday vs. weekend)
- "Day off" toggle per day (no enforcement)
- Quick-set presets: "9-to-5," "Startup Hours (8 AM–8 PM)," "Half Day"
- All times stored in local timezone with proper DST handling
- Schedule changes take effect the next day (cannot weaken today's schedule today — this is a core anti-bypass principle)
- Optional: schedule lock that requires a cooldown period (e.g., 24 hours) before changes apply

**UX Notes:**

- Settings UI uses a weekly calendar grid, similar to Calendar.app's week view
- Each day is a row; drag handles adjust start/end times visually
- A summary sentence below: *"Tomorrow, work ends at 6:00 PM and resumes at 8:00 AM."*

---

### F2: Warning Escalation System

**Description:** A series of progressively urgent notifications and visual cues that prepare the user to stop working.

**Requirements:**

| Time Before Lockout | Behavior |
|---|---|
| T-30 min | Standard macOS notification: *"30 minutes of work time left."* |
| T-15 min | Persistent notification + menu bar icon turns amber. *"15 minutes — start wrapping up."* |
| T-5 min | Screen overlay at 10% opacity (subtle dimming). Notification with sound: *"5 minutes. Save your work now."* |
| T-2 min | Screen overlay at 25% opacity. Gentle chime. *"2 minutes remaining."* |
| T-1 min | Screen overlay at 40% opacity. Audible countdown tone. *"1 minute. Final save."* |
| T-0 | Full lockout screen transition (animated fade-in over 3 seconds). |

- Warning intervals are user-configurable (advanced settings)
- Each warning includes a "Snooze 1 min" action (but only at T-15 and T-30; not available in the final 5 minutes)
- Warnings are delivered via `UNUserNotificationCenter` with appropriate categories and actions
- Screen overlay is a borderless `NSWindow` at `.floating` level (not `.screenSaver` — that's reserved for lockout)
- Overlay is click-through during warning phase (user can still work, just sees the dim)

**UX Notes:**

- The dimming effect should feel like a sunset — warm amber tint, not harsh darkening
- A small floating timer appears in the corner during the last 5 minutes, always on top
- Sound design: soft, warm tones — not alarm-like. Think meditation bell, not fire alarm.

---

### F3: Full-Screen Lockout

**Description:** An immersive, beautiful full-screen experience that replaces the desktop and prevents further work.

**Requirements:**

- Covers all displays, all Spaces, all fullscreen apps
- `NSWindow` at `.screenSaver` level with `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
- Window is non-movable, non-resizable, borderless, and captures all mouse/keyboard input
- Blocks system keyboard shortcuts during lockout: Cmd+Tab, Cmd+Q, Cmd+Space, Cmd+Option+Esc, Ctrl+arrow keys
- Implemented via `CGEvent.tapCreate` at the session level for key interception
- Displays:
  - Current time (large, elegant typography)
  - Unlock time: *"Your computer unlocks at 8:00 AM"*
  - A warm, encouraging message (randomly selected from a curated list)
  - Animated background (subtle gradient shift, particle effects, or generative art)
  - If shutdown is enabled: countdown to shutdown
- The lockout screen supports Dark/Light mode and respects system appearance
- Accessibility: VoiceOver reads the lock message and unlock time. Reduce Motion preference disables animations.

**Sample Messages (rotating):**

- *"Great work today. Tomorrow is another day."*
- *"The best code is written by a rested mind."*
- *"You've earned this. Go live your life."*
- *"Nothing in your inbox is more important than your health."*
- *"Shut the laptop. Open a book."*
- *"Future you will be grateful."*

**UX Notes:**

- The transition into lockout should feel like a calm exhale, not a slammed door
- Background animation: slow-moving aurora borealis effect or gentle particle field
- Typography: SF Pro Display, large weight, generous spacing
- Consider showing a "today's stats" card: hours worked, tasks completed (if integrated)

---

### F4: Shutdown Manager

**Description:** Optionally shuts down the computer after lockout to save energy and reinforce the boundary.

**Requirements:**

- Configurable delay after lockout (default: 10 minutes, range: 1–60 minutes)
- Lockout screen shows countdown: *"Shutting down in 9:42..."*
- Shutdown uses `osascript -e 'tell app "System Events" to shut down'` or equivalent AppleScript/NSAppleScript call
- User can disable auto-shutdown entirely (lockout remains active)
- Graceful handling: sends `NSWorkspace.shared.requestTermination()` to all apps before shutdown, giving them time to auto-save
- If shutdown fails (unsaved document dialog blocks it), retry once after 60 seconds, then give up and remain in lockout

**UX Notes:**

- The shutdown countdown should feel like a gentle wind-down, not a threat
- Display: *"Your Mac is going to sleep in 10 minutes. Sweet dreams."*
- Use "sleep" language even if performing a full shutdown — it's friendlier

---

### F5: Bypass Protection

**Description:** Ensures the lockout persists across restarts, force-quits, and login attempts.

**Requirements:**

**Persistence Layer:**

- A privileged helper tool installed via `SMAppService` (macOS 13+) that runs as a LaunchDaemon
- The daemon starts at boot (before user login) and checks the current schedule
- If the current time falls within a lockout window, the daemon activates the lockout immediately upon user login
- Daemon state is stored in `/Library/Application Support/Curfew/` (root-owned, not user-writable)

**Anti-Circumvention:**

- Lockout state is written to a root-owned plist; the user process reads but cannot modify it
- The daemon monitors the main Curfew app process; if it's killed, the daemon reactivates lockout independently
- Login items are registered via `SMAppService.register()` for macOS 13+ compatibility
- Event tap blocks Force Quit dialog (Cmd+Option+Esc) during lockout

**Emergency Override:**

- A clearly documented escape hatch exists: boot into Recovery Mode, or use a specific Terminal command with `sudo` that requires the user's admin password and writes a cooldown flag
- The override is logged and shown in the weekly summary: *"Emergency override used on Tuesday at 11:32 PM"*
- Override command: `sudo curfew-ctl override --reason "emergency"` (installed as a CLI companion)
- Overrides are limited: maximum 2 per week by default (configurable). After that, the CLI command refuses.

**Mac App Store Compatibility:**

- Curfew is distributed outside the Mac App Store as a notarized `.dmg` to avoid sandbox restrictions that would undermine the core enforcement model.
- The app is code-signed with a Developer ID certificate and notarized via Apple's notarization service, so it passes Gatekeeper without warnings.
- If a sandboxed App Store version is considered in the future, it would be a separate, clearly labeled "Curfew Lite" with disclosed limitations.

---

### F6: macOS Widget (WidgetKit)

**Description:** A home screen / Notification Center widget showing remaining work time.

**Requirements:**

- Supports Small, Medium, and Large widget sizes
- **Small:** Circular countdown timer (hours:minutes remaining), color-coded (green → amber → red)
- **Medium:** Countdown timer + today's schedule (start/end) + extensions remaining
- **Large:** Countdown + schedule + mini weekly bar chart of hours worked
- Updates via `TimelineProvider` with entries at each warning interval
- Shared data via App Group (`group.com.curfew.shared`) using a lightweight JSON file or UserDefaults suite
- Widget is interactive on macOS 14+: tap to open settings, long-press for quick actions
- Respects system appearance (light/dark) and accessibility settings

**UX Notes:**

- The countdown should use a custom circular progress ring, not just text
- Color transitions should be smooth (animated gradient from green to amber to red)
- When in lockout, widget shows: *"Locked until 8:00 AM 🌅"*
- When on a day off, widget shows: *"Day off. Enjoy! ☀️"*

---

### F7: Extension System

**Description:** A limited budget of time extensions to respect user autonomy while maintaining commitment.

**Requirements:**

- Weekly budget: configurable number of extensions (default: 3 per week)
- Each extension: configurable duration (default: 15 minutes)
- Extensions can only be requested during the warning phase (T-30 to T-0), not after lockout
- Requesting an extension shifts the lockout time forward by the extension duration
- UI: a prominent but not intrusive button in the warning overlay: *"Need 15 more minutes? (2 left this week)"*
- Once the budget is spent, the button is disabled with text: *"No extensions remaining this week."*
- Extensions reset on a configurable day (default: Monday at unlock time)
- Extension usage is logged and shown in the weekly summary

**UX Notes:**

- The extension button should require a deliberate action (e.g., press and hold for 2 seconds) to prevent accidental activation
- After using an extension, show: *"Extension activated. New curfew: 6:15 PM. You have 1 extension left this week — use it wisely."*

---

### F8: Calendar Integration

**Description:** Optionally adjusts the schedule based on calendar events.

**Requirements:**

- Reads events from the system calendar via EventKit
- If a meeting is scheduled to end after the configured curfew time, offer to auto-extend (costs 1 extension)
- Detection runs 1 hour before curfew and checks for events overlapping the lockout boundary
- User receives a notification: *"You have 'Team Standup' ending at 6:15 PM. Use an extension to cover it?"*
- Calendar integration is opt-in and requires explicit calendar access permission
- Only reads event times and titles — does not access attendees, notes, or other fields
- Supports multiple calendar sources (iCloud, Google, Exchange)

---

### F9: MCP Server Interface

**Description:** Exposes Curfew's state and controls as MCP (Model Context Protocol) tools, enabling AI assistants to participate in time management. This is Curfew's most differentiated feature — it turns a personal productivity tool into something an AI assistant can actively reason about and act on.

#### F9.1: Configuration

**Transport: stdio (primary)**

The MCP server is a standalone Swift executable (`curfew-mcp`) bundled inside the app at `Curfew.app/Contents/MacOS/curfew-mcp`. It reads JSON-RPC from stdin and writes to stdout, following the standard MCP stdio transport spec. Users add it to their MCP client like any other server:

```json
// Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json
// Claude Code: added via `claude mcp add`
{
  "mcpServers": {
    "curfew": {
      "command": "/Applications/Curfew.app/Contents/MacOS/curfew-mcp",
      "args": []
    }
  }
}
```

The binary lives inside the app bundle so it stays versioned with the app and requires no separate installation. Curfew's Settings UI includes an "Integrations" tab with a one-click "Copy MCP config" button that places the correct JSON snippet on the clipboard.

**Transport: Streamable HTTP (secondary)**

For remote MCP clients, custom integrations, or multi-process setups, Curfew optionally exposes the same tools over Streamable HTTP on `localhost:9847` (configurable port). This is disabled by default and enabled in Settings under "Advanced > MCP Server > Enable network access." It binds only to `localhost` — no remote access unless the user explicitly configures it. The Streamable HTTP transport follows the MCP Streamable HTTP specification (2025-03-26).

**Auto-configuration:**

On first launch, Curfew detects whether Claude Desktop is installed (checks for the config file at `~/Library/Application Support/Claude/claude_desktop_config.json`) and offers to register itself automatically: *"Claude Desktop detected. Add Curfew as an MCP server?"* This removes all manual configuration for the most common use case.

#### F9.2: Technical Implementation

**SDK:** The server is built using the official MCP Swift SDK ([`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk), currently v0.11.x), which implements the 2025-03-26 MCP specification. This is the canonical Swift SDK maintained under the `modelcontextprotocol` GitHub organization.

**Package dependency:**

```swift
// In the CurfewMCP target's Package.swift
dependencies: [
    .package(
        url: "https://github.com/modelcontextprotocol/swift-sdk.git",
        from: "0.11.0"
    )
]
```

**Server structure (conceptual):**

```swift
import MCP
import ServiceLifecycle
import Logging

let logger = Logger(label: "com.curfew.mcp")

let server = Server(
    name: "curfew",
    version: "1.0.0",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

// Register tool listing
await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: CurfewTools.allTools)
}

// Register tool execution
await server.withMethodHandler(CallTool.self) { params in
    try await CurfewTools.handle(params)
}

// Start stdio transport
let transport = StdioTransport(logger: logger)
let mcpService = MCPService(server: server, transport: transport)
let serviceGroup = ServiceGroup(services: [mcpService], logger: logger)
try await serviceGroup.run()
```

**Data access:** The MCP server process does not run its own scheduling logic. It reads from the same shared data layer as the rest of the app:

- **App Group `UserDefaults` suite** for the current schedule
- **SQLite database** (App Group container) for usage history, extension budget, and override logs
- **Local state plist** (`/Library/Application Support/Curfew/state.plist`) for current lockout status

For write operations (`request_extension`, `set_schedule`), the server writes to the SQLite database and signals the main Curfew app process via a Unix domain socket at `~/Library/Application Support/Curfew/mcp.sock`. The main app picks up the change and propagates to CloudKit. This means the MCP server works even if the menu bar app isn't running — reads always succeed. Write operations queue and execute when the main app process is available.

**Build target:** The `curfew-mcp` executable is a separate target in the Xcode project / Swift Package, sharing a `CurfewShared` library (data models, database access, socket communication) with the main app. It compiles to a lightweight binary (~2–5 MB) with no UI dependencies.

#### F9.3: Tools

| Tool | Description | Parameters | Returns |
|---|---|---|---|
| `get_status` | Current enforcement state | None | `{ state: "working" \| "warning" \| "locked" \| "day_off", device: string }` |
| `get_time_remaining` | Minutes until lockout (accounts for hours-based mode and cross-device time) | None | `{ minutes: int, mode: "fixed" \| "hours" \| "combined", trigger: "time" \| "hours" }` |
| `get_schedule` | Full schedule for a given date | `date?: string` (ISO date, defaults to today) | `{ end_time: string, unlock_time: string, mode: string, hours_limit?: int }` |
| `get_weekly_summary` | Hours worked, extensions, overrides with device attribution | `week_of?: string` (ISO date, defaults to current week) | `{ days: [DaySummary], total_hours: float, extensions_used: int, overrides_used: int, streak: int }` |
| `request_extension` | Request a time extension if budget allows | `reason: string` | `{ granted: bool, new_end_time?: string, remaining_budget: int, message: string }` |
| `set_schedule` | Update schedule for a future date (cannot weaken today) | `date: string, end_time: string, unlock_time?: string, mode?: string` | `{ success: bool, effective_date: string, message: string }` |
| `get_extension_budget` | Remaining extensions this week (shared across all devices) | None | `{ remaining: int, total: int, resets_on: string }` |
| `get_devices` | All synced devices with current status | None | `{ devices: [{ name: string, model: string, status: "active" \| "idle" \| "offline", hours_today: float }] }` |
| `get_total_hours_today` | Cumulative work hours across all devices | `date?: string` (ISO date) | `{ total_hours: float, by_device: [{ name: string, hours: float }] }` |
| `get_override_log` | Recent overrides with device, time, and reason | `limit?: int` (default 10) | `{ overrides: [{ timestamp: string, device: string, reason?: string, duration_minutes: int }] }` |
| `get_streak` | Current streak of days without extensions or overrides | None | `{ days: int, since: string, longest_ever: int }` |

The tool set is deliberately read-heavy. The only write operations are `request_extension` and `set_schedule`, both of which respect the same constraints as the UI: you cannot weaken today's schedule, and extensions draw from the shared cross-device budget. The MCP server cannot be used to bypass enforcement — it is a window into the system, not a backdoor.

#### F9.4: Use Cases

**1. Time-aware task prioritization (the core pitch)**

The AI assistant knows how much time the user has left and can help make decisions accordingly. When the user asks *"I have three PRs to review, a bug to fix, and a design doc to write — what should I focus on?"*, the assistant calls `get_time_remaining`, sees 90 minutes remain, and reasons about what's achievable: two PR reviews and the bug fix, deferring the design doc. Without Curfew, the assistant has no concept of the user's time budget. With it, every prioritization response is grounded in reality.

**2. Proactive time awareness during long sessions**

If the assistant is in a long conversation (debugging, writing, planning), it can periodically check `get_time_remaining` and interject naturally: *"By the way, you have 20 minutes before curfew. Want to wrap up this refactor at a good stopping point, or should I help you request an extension?"* This is contextually aware time management — not a dumb timer notification.

**3. Extension negotiation**

The `request_extension` tool takes a `reason` parameter. The assistant can act as a mediator between the user and their own commitment: *"You have 1 extension left this week. The deploy failure looks like it's in the staging config — I can draft a rollback PR that your teammate could merge tomorrow. Want to do that instead of burning your last extension?"* The assistant helps find alternatives to overriding the user's commitment.

**4. Smart schedule adjustment**

The `set_schedule` tool lets the assistant help plan ahead: *"I have a product launch next Thursday. Can you push my curfew to 9 PM that day?"* The assistant can also surface patterns over time: *"You've extended past 8 PM three times this month. Want me to move your default curfew to 7 PM on weekdays to compensate?"*

**5. End-of-day ritual automation (MCP composability)**

An MCP client like Claude Code can combine Curfew's time signal with other MCP servers to trigger end-of-day workflows. At T-15, the assistant automatically: creates a WIP commit and pushes the branch (GitHub MCP server), writes a handoff note summarizing where the user left off and what to pick up tomorrow, and posts a status update to Slack (Slack MCP server). Curfew provides the *when*; other MCP servers provide the *what*. This composability is the key architectural insight.

**6. Cross-device context**

The `get_devices` and `get_total_hours_today` tools let the assistant understand the user's work holistically: *"You've worked 6.5 hours today across your Mac Studio and MacBook. You have 1.5 hours left in your hours budget. Your Mac Studio has been idle for 2 hours — looks like you switched to the MacBook after lunch."*

**7. Weekly review co-pilot**

The `get_weekly_summary` tool with device attribution feeds a structured reflection conversation: *"Here's your week: 42 hours across 5 days, averaging 8.4 hours. You used 2 extensions — both on Wednesday, both on your MacBook. You had a 9-day streak before that. Want to dig into what happened Wednesday?"* The assistant turns raw data into a conversation about habits.

**8. Holistic planning with other MCP tools**

If the user also has calendar, task management (Linear, Todoist), and communication (Slack, email) MCP servers connected, the assistant can synthesize across all of them: *"You have 3 meetings tomorrow totaling 2.5 hours, 4 Linear tickets in your sprint, and curfew at 6 PM. That leaves roughly 4.5 hours of focus time. Here's a suggested block schedule..."* Curfew becomes the time constraint that makes all other planning concrete.

---

### F10: Onboarding Experience

**Description:** A first-run experience that sets up the user's schedule and explains how Curfew works.

**Requirements:**

- Multi-step onboarding flow (4–5 screens):
  1. **Welcome:** *"Curfew helps you stop working on time. Not tomorrow. Today."* Brief explanation of the commitment model.
  2. **Schedule Setup:** Interactive weekly schedule picker. Pre-filled with "9-to-5" as default.
  3. **Extension Budget:** Explain the extension system. Let user pick budget (1–5/week) and duration (10, 15, 30 min).
  4. **Permissions:** Request notification permission, calendar access (optional), accessibility access (for event tap — required for full lockout).
  5. **Confirmation:** Summary of chosen schedule. *"Starting tomorrow, Curfew will enforce this schedule. Ready?"* Large "Activate" button.
- Onboarding only runs on first launch. Can be re-accessed from Settings.
- Schedule changes made during onboarding take effect the next day (consistent with the anti-bypass principle).

**UX Notes:**

- Each screen should have a single focus — no overwhelming the user with options
- Use animation to demonstrate the warning escalation visually
- The tone should be warm and slightly humorous: *"We're not your boss. We're the friend who tells you to go home."*

---

### F11: Weekly Retrospective

**Description:** A summary view showing work patterns and Curfew interactions over the past week.

**Requirements:**

- Accessible from the menu bar app: *"This Week"* section
- Shows:
  - Daily hours worked (bar chart)
  - Average daily work time
  - Extensions used (count and when)
  - Emergency overrides (count and when)
  - Days off taken
  - Streak: consecutive days of respecting curfew without extensions
- Data stored locally in SQLite via the shared App Group container
- Retention: 52 weeks of history (1 year)
- Export: CSV export of historical data

**UX Notes:**

- The retrospective should feel like a fitness app summary — encouraging, not judgmental
- Celebrate streaks: *"12 days without an extension. You're building a great habit."*
- If override usage is high: *"You've used 4 overrides this month. Consider adjusting your schedule to better fit your needs."* (Helpful, not preachy.)

---

### F12: Menu Bar Presence

**Description:** A minimal, persistent menu bar item that serves as the app's primary interface.

**Requirements:**

- Displays a small icon (clock glyph) in the menu bar at all times when the app is running
- Icon changes color based on state:
  - Green: more than 1 hour remaining
  - Amber: less than 1 hour remaining
  - Red: less than 15 minutes remaining
  - Gray: day off or outside work hours
  - Lock icon: during lockout
- Clicking the icon opens a popover with:
  - Large countdown timer
  - Today's schedule
  - Extension button (if in warning phase)
  - Quick link to Settings
  - Quick link to Weekly Retrospective
- Built with `MenuBarExtra` (macOS 13+) with SwiftUI popover content
- No Dock icon — menu bar only (`LSUIElement = true`)

---

### F13: CloudKit Sync

**Description:** Synchronizes schedule, lockout state, and usage data across all of a user's Macs via iCloud.

**Requirements:**

**Data Model (CloudKit Private Database):**

- **`Schedule` record:** The canonical work schedule. One record, shared across all devices. Fields: per-day work-end times, unlock times, extension budget, extension duration, active days. Conflict resolution: last-write-wins using CloudKit `recordChangeTag`. Safe because schedule changes don't take effect until the next day.
- **`LockoutState` record:** Current enforcement state. Fields: `isLocked` (bool), `lockoutStarted` (datetime), `unlockTime` (datetime), `extensionsUsedThisWeek` (int), `overridesUsedThisWeek` (int), `lastModifiedBy` (device ID). Updated by whichever device triggers the state change.
- **`Device` record:** One per device. Fields: device name, model identifier, last seen timestamp, Curfew version. Written on first launch and updated on each app launch.

**Sync Flow:**

- When any device enters lockout (T-0), it writes `isLocked: true` to the `LockoutState` record in CloudKit
- All other devices subscribe via `CKSubscription` (or `CKDatabaseSubscription` for batch efficiency) and receive silent push notifications on state changes
- On receiving a lockout notification, each device reads the updated state and activates its own lockout immediately
- Extensions and overrides update the shared `LockoutState` record — the budget is global, not per-device

**Offline / Sleep Handling:**

- If a device is asleep or offline when lockout triggers, it checks CloudKit state on wake or network reconnect
- If the current time still falls within the lockout window, lockout activates retroactively
- A local fallback schedule is cached so enforcement works even without network connectivity — CloudKit is the source of truth, but the local cache ensures the device is never unprotected

**Architecture Constraint:**

- The privileged helper (LaunchDaemon) runs as root and cannot directly access CloudKit (which requires a user session)
- The user-space app process handles all CloudKit communication and writes the canonical state to the local shared file (`/Library/Application Support/Curfew/state.plist`)
- The daemon reads that file; on wake or network reconnect, the app process syncs with CloudKit first, updates the local state, then the daemon acts

**Privacy:**

- CloudKit private database: data is encrypted and accessible only to the user's iCloud account
- No third-party servers, no account creation, no data leaves iCloud
- If the user is signed out of iCloud, sync is disabled and each device operates independently
- Settings UI shows sync status: *"Synced across 2 devices"* or *"Sign in to iCloud to sync across your Macs"*

**UX Notes:**

- Settings includes a "Devices" section listing all synced Macs with their last-seen time
- A device can be removed from sync (stops enforcing the shared schedule and operates independently)
- First-launch onboarding includes a sync step: *"Curfew found 1 other Mac on your iCloud account. Sync your schedule across both?"*

---

### F14: Unified Work Timer

**Description:** Tracks cumulative work time across all devices, enabling enforcement based on total hours worked rather than (or in addition to) a fixed clock time.

**Requirements:**

**Cross-Device Time Tracking:**

- Each device reports active work minutes to a shared `WorkSession` record in CloudKit
- Active time is measured by detecting user input (keyboard/mouse activity) — idle periods longer than 5 minutes (configurable) are excluded
- The widget and menu bar show total work time across all devices, not just the local device
- Example: 4 hours on Mac Studio + 3 hours on MacBook = 7 hours total displayed everywhere

**Hours-Based Curfew Mode:**

- In addition to the existing fixed-time mode ("lock at 6 PM"), support an hours-based mode: *"Lock after 8 hours of work"*
- Combination mode: *"Lock at 6 PM OR after 8 hours, whichever comes first"*
- Hours-based mode uses the unified cross-device work timer as its input
- When the hours limit is approaching, the same warning escalation system (F2) activates, with messages adjusted: *"7 hours 30 minutes worked today. 30 minutes remaining."*

**Session Reporting:**

- Each device writes periodic heartbeats (every 60 seconds while active) to a `DeviceActivity` CloudKit record
- Fields: device ID, timestamp, active (bool)
- The app aggregates these into daily totals stored in the `DayRecord` SQLite database (synced via CloudKit or computed locally from shared records)

**UX Notes:**

- Schedule configuration UI adds a toggle: "Time-based" vs. "Hours-based" vs. "Combined"
- The menu bar popover shows: *"5h 23m worked today (across 2 devices) · 2h 37m remaining"*
- The widget (Medium/Large) shows a breakdown: which device contributed how many hours

---

### F15: Active Device Awareness

**Description:** Each device knows which other devices are currently in use, enabling smarter UI and coordinated enforcement.

**Requirements:**

- Each device writes a heartbeat to CloudKit every 60 seconds while the user is active (shares the `DeviceActivity` record from F14)
- A device is considered "active" if its last heartbeat is within the past 2 minutes
- Idle devices show contextual information about the active device:
  - Menu bar popover: *"Currently working on Mac Studio · 2h 14m today"*
  - Widget: *"Active on Mac Studio · 47 min remaining"*
  - Lockout screen (if idle device is locked but active device is still in its work window): *"Your Mac Studio is still active. Curfew in 47 minutes."*

**Coordinated Shutdown Sequencing (F4 integration):**

- When auto-shutdown is enabled and multiple devices are present:
  - The **active device** (most recent input) follows the configured shutdown delay
  - **Idle devices** shut down immediately or after a shorter delay (default: 2 minutes after lockout)
  - This prevents the active device from shutting down while the user is still saving work on it

**Warning Handoff:**

- If the user switches devices during the warning phase (T-30 to T-0), the new device picks up the escalation at the correct point
- The `LockoutState` CloudKit record includes a `warningPhaseStarted` timestamp
- Any device joining mid-warning reads this timestamp and calculates which escalation stage to display, rather than restarting from T-30

**UX Notes:**

- The "Devices" section in Settings shows real-time status: a green dot for active, gray for idle/offline
- Device names are pulled from the macOS sharing name (`SCDynamicStoreCopyComputerName`)

---

### F16: Device-Attributed Override Logging

**Description:** Extensions and overrides are logged with the device that requested them, enabling location-aware behavioral insights.

**Requirements:**

- Every extension request and emergency override records:
  - Timestamp
  - Device name and model
  - Reason (if provided via the "Convince Me" flow or CLI `--reason` flag)
- The weekly retrospective (F11) includes device attribution:
  - *"You used 2 overrides this week — both on MacBook Pro"*
  - *"Extensions: 1 on Mac Studio (Tuesday), 1 on MacBook Pro (Thursday)"*
- Over time, the retrospective can surface patterns: *"You override most often on your MacBook Pro in the evenings. Consider leaving it in another room after curfew."*

**UX Notes:**

- The insight about device-specific patterns should only appear after 2+ weeks of data — not on the first override
- Tone remains helpful, not accusatory: the app is surfacing data, not passing judgment

---

### F17: User-Facing Unlock Request ("Convince Me")

**Description:** A deliberate, friction-heavy unlock flow accessible from the lockout screen that forces reflective engagement before granting a time-limited override.

**Requirements:**

**Flow:**

1. **Entry point:** A small, understated link at the bottom of the lockout screen: *"Need to get back in?"* — deliberately low-contrast, not a prominent button.
2. **Cooldown timer:** Tapping the link starts a 5-minute countdown before the unlock process becomes available. Screen displays: *"Still sure? Unlock available in 4:32..."* The user must wait. Most impulses die in 5 minutes.
3. **Written justification:** After the cooldown, a text field appears: *"Explain why you need to get back on your computer right now."* Minimum 50 characters required. This activates the reflective/rational part of the brain — the user must articulate a reason, and writing it out often makes them realize it can wait.
4. **Confirmation with consequences:** After submitting, a final screen: *"This will count as 1 of your 2 weekly overrides. Your weekly summary will log this at 11:47 PM on MacBook Pro. Proceed?"* A press-and-hold button (3 seconds) to confirm — not a tap.
5. **Time-limited unlock:** The override grants 30 minutes (configurable, default 30, range 15–60). After the granted period, lockout resumes automatically. If the user needs more time, they must go through the entire flow again — but are now on their last override for the week.

**Budget Integration:**

- Uses the same weekly override budget as the CLI emergency override (F5) — they are the same pool
- If no overrides remain, the flow ends at step 1 with: *"No overrides remaining this week. See you in the morning."*
- Override count is synced across devices via CloudKit (F13)

**Logging:**

- The full override event is logged: timestamp, device, written justification, time granted
- Justifications are stored locally only (never synced to CloudKit) for privacy
- The weekly retrospective shows override count and timing but not the written justifications (those are for the user's own reflection, not for display)

**UX Notes:**

- The 5-minute cooldown is the most important part — it's the gap between impulse and action
- The text field should feel like journaling, not a form: large, comfortable, no character counter visible until under 50 characters
- After the override period ends and lockout resumes, the screen says: *"Welcome back. Hope you got what you needed."* — no judgment

---

## Non-Functional Requirements

### Performance

- CPU usage < 1% during idle monitoring
- Memory footprint < 30 MB for main app, < 10 MB for helper daemon
- Widget timeline generation < 100ms
- Lockout screen renders at 60fps (animations)
- No perceptible delay between T-0 and lockout activation

### Security

- All IPC between app and privileged helper uses XPC with proper entitlements
- Schedule data integrity verified with HMAC to prevent tampering
- No network calls except CloudKit sync (iCloud-encrypted) and optional update checks (Sparkle framework)
- No analytics, telemetry, or crash reporting that sends data externally (privacy-first)
- Override justifications stored locally only — never synced to CloudKit or transmitted

### Accessibility

- Full VoiceOver support for all UI elements including lockout screen
- Respect `reduceMotion` preference (disable animations, use fade transitions)
- Respect `reduceTransparency` preference (solid backgrounds instead of blurred overlays)
- All text meets WCAG AA contrast ratios
- Keyboard navigable settings UI
- Dynamic Type support where applicable

### Localization

- English (US) at launch
- Architecture supports localization via `.strings` files and `String(localized:)`
- All user-facing strings are externalized from day one
- Date and time formatting uses `DateFormatter` with locale-aware settings

---

## Distribution & Installation

### Installation Flow

1. **Primary: Direct Download (`.dmg`)**
   - User downloads `Curfew-x.x.x.dmg` from curfew.app or GitHub Releases
   - Opens `.dmg`, drags Curfew.app to `/Applications`
   - On first launch, macOS Gatekeeper verifies the notarization — no "unidentified developer" warning
   - Onboarding flow begins, including privileged helper installation (prompts for admin password once)

2. **Secondary: Homebrew Cask**
   - `brew install --cask curfew`
   - Homebrew handles download, extraction, and placement in `/Applications`
   - First launch still triggers onboarding and privileged helper installation

### Signing & Notarization

- App is signed with a Developer ID Application certificate
- Privileged helper is signed with a Developer ID Application certificate and includes an `SMAuthorizedClients` entry linking it to the main app
- `.dmg` is created with `create-dmg` (includes background image, Applications symlink, Retina icon layout)
- Entire `.dmg` is submitted to Apple's notarization service via `notarytool`
- Stapled notarization ticket attached to the `.dmg` for offline Gatekeeper verification

### Auto-Updates (Sparkle)

- Sparkle framework embedded in the app bundle
- Appcast XML (`appcast.xml`) hosted on GitHub Pages or alongside GitHub Releases
- Update checks on launch and every 24 hours (configurable)
- Updates are signed with EdDSA (Sparkle's default) for integrity verification
- The privileged helper has its own update path — when the main app updates and detects a helper version mismatch, it prompts for re-installation
- Users can disable auto-update checks in Settings

### CI/CD Pipeline (GitHub Actions)

```
Push tag (v1.0.0)
  → Build universal binary (Xcode, xcodebuild)
  → Sign with Developer ID (via Keychain on runner)
  → Create .dmg (create-dmg)
  → Notarize (notarytool submit, notarytool wait)
  → Staple (stapler staple)
  → Generate Sparkle appcast entry (generate_appcast)
  → Upload to GitHub Releases
  → Update Homebrew Cask formula (PR to homebrew-cask)
```

### Uninstallation

- Curfew includes an "Uninstall" button in Settings that:
  - Removes the privileged helper and LaunchDaemon
  - Removes `/Library/Application Support/Curfew/`
  - Removes the Login Item registration
  - Optionally deletes user data (schedule, history)
  - Quits the app
- A standalone uninstall script (`uninstall.sh`) is also provided in the GitHub repository for manual removal
- The Homebrew Cask `uninstall` stanza handles cleanup automatically

### Pricing

- **Free and open source** (MIT or similar permissive license)
- No in-app purchases, no subscriptions, no telemetry
- Optional sponsorship via GitHub Sponsors — not promoted within the app itself

---

## Technical Architecture Summary

```
┌────────────────────────────────────────────────────────────┐
│                        User Layer                          │
│                                                            │
│  Menu Bar App ◄──► Settings UI ◄──► Onboarding             │
│       │              │                                     │
│       ▼              ▼                                     │
│  WidgetKit Ext    Retrospective View                       │
│       │                                                    │
├───────┼────────────────────────────────────────────────────┤
│       │           Application Layer                        │
│       ▼                                                    │
│  ┌──────────────────────────────┐  ┌────────────────────┐  │
│  │     Schedule Manager         │  │  CloudKit Sync     │  │
│  │     Warning Coordinator      │◄►│  Manager           │  │
│  │     Extension Manager        │  │                    │  │
│  │     Calendar Bridge          │  │  - Schedule sync   │  │
│  │     Unified Work Timer       │  │  - Lockout state   │  │
│  └──────────┬───────────────────┘  │  - Device registry │  │
│             │                      │  - Activity beats  │  │
│        XPC / IPC                   └────────┬───────────┘  │
│             │                               │              │
├─────────────┼───────────────────────────────┼──────────────┤
│             │        Privileged Layer        │              │
│             ▼                               │              │
│  ┌──────────────────────────────┐           │              │
│  │     Privileged Helper        │◄──── LaunchDaemon        │
│  │     Screen Locker            │      (root, persistent)  │
│  │     Event Tap Manager        │           │              │
│  │     Shutdown Controller      │           │              │
│  └──────────────────────────────┘           │              │
│                                             │              │
├─────────────────────────────────────────────┼──────────────┤
│                     External Interfaces     │              │
│                                             ▼              │
│  MCP Server (stdio) ◄──► AI Assistants   iCloud           │
│  CLI (`curfew-ctl`) ◄──► Terminal        (CloudKit        │
│                                           Private DB)     │
└────────────────────────────────────────────────────────────┘
```

---

## Data Storage

| Data | Location | Access | Synced |
|---|---|---|---|
| User schedule | App Group shared container (`UserDefaults` suite) | App, Widget, MCP Server | ✅ CloudKit (private DB, `Schedule` record) |
| Lockout state | `/Library/Application Support/Curfew/state.plist` | Daemon (write), App (read) | ✅ CloudKit (private DB, `LockoutState` record) |
| Device registry | CloudKit private DB (`Device` record) | App | ✅ CloudKit |
| Device activity heartbeats | CloudKit private DB (`DeviceActivity` record) | App | ✅ CloudKit |
| Usage history | SQLite database in App Group container | App, Widget, MCP Server | ❌ Local only |
| User preferences | `UserDefaults` (standard) | App | ❌ Local only |
| Extension/override budget | SQLite + CloudKit `LockoutState` record | App, MCP Server | ✅ CloudKit (count only) |
| Override justifications | SQLite database in App Group container | App | ❌ Local only (privacy) |

---

## Milestones

### M1: Foundation (Weeks 1–3)

- Menu bar app shell with SwiftUI popover
- Schedule configuration UI (basic: single daily schedule)
- Notification-based warnings (T-30, T-15, T-5, T-1)
- Basic lockout screen (full-screen overlay, no bypass protection)

### M2: Enforcement (Weeks 4–6)

- Privileged helper tool with XPC communication
- LaunchDaemon persistence
- Event tap for keyboard shortcut blocking
- Shutdown manager
- Emergency override CLI
- "Convince Me" user-facing unlock request flow

### M3: Intelligence (Weeks 7–9)

- Extension system with weekly budget
- Calendar integration (EventKit)
- Per-day schedule configuration
- Warning escalation with screen dimming overlay

### M4: Multi-Device (Weeks 10–12)

- CloudKit sync: schedule, lockout state, device registry
- Unified cross-device work timer
- Active device awareness and heartbeat system
- Hours-based and combined curfew modes
- Device-attributed override logging
- Coordinated shutdown sequencing
- Warning handoff across devices

### M5: Polish (Weeks 13–15)

- WidgetKit extension (all three sizes) with cross-device data
- Weekly retrospective view with charts and device attribution
- Onboarding flow (including multi-device sync step)
- Lockout screen animations and message rotation
- Accessibility audit and VoiceOver support

### M6: Distribution & Launch (Weeks 16–18)

- MCP server implementation and testing
- CI/CD pipeline: GitHub Actions for build → sign → notarize → release
- Sparkle auto-update integration
- `.dmg` creation with polished installer design
- Homebrew Cask formula submission
- GitHub repository setup (README, LICENSE, CONTRIBUTING)
- Landing page at curfew.app
- Hacker News launch post

---

## Open Questions

1. **Should schedule weakening have a cooldown?** Current design says changes take effect next day. Should making the schedule *less* strict (e.g., moving curfew from 6 PM to 9 PM) require a 24–48 hour cooldown to prevent in-the-moment weakening?

2. **Multi-user Mac support?** Should each macOS user account have independent schedules? (Probably yes, but adds complexity to the daemon.)

3. **Touch ID / password for extensions?** Should requesting an extension require biometric auth to add friction? Or does the press-and-hold gesture provide enough?

4. **Focus Mode integration?** Should Curfew automatically activate a macOS Focus Mode during lockout to silence notifications?

5. **Should a sandboxed "Curfew Lite" App Store version exist?** A limited version without bypass protection could broaden reach, but might dilute the brand promise. Defer until post-launch demand is clear.

6. **Apple Watch companion?** A watchOS widget showing time remaining could be valuable for users who step away from their desk. Out of scope for v1 but worth planning the data architecture for.

---

## Success Metrics

- **GitHub:** 500+ stars within first month of launch
- **HN:** Front page, 100+ points
- **Homebrew:** Accepted into homebrew-cask within first month
- **Retention:** 60%+ of users still active after 30 days
- **Behavioral:** Users report reduced average work hours within 2 weeks of adoption (measured via optional in-app survey)

---

*Curfew: Because the best productivity hack is knowing when to stop.*

---

## Appendix A: Architecture & Design Diagrams

### A1: Full Application Architecture

Detailed view of all processes, their privilege levels, communication channels, and data stores.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   USER SPACE (runs as logged-in user)                                       │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        MAIN APP PROCESS                             │   │
│   │                     (Curfew.app, LSUIElement)                       │   │
│   │                                                                     │   │
│   │  ┌─────────────┐  ┌──────────────┐  ┌───────────────────────────┐  │   │
│   │  │  Menu Bar    │  │  Settings    │  │  Onboarding               │  │   │
│   │  │  (SwiftUI    │  │  Window      │  │  Window                   │  │   │
│   │  │  MenuBarExtra│  │  (SwiftUI)   │  │  (SwiftUI)                │  │   │
│   │  │  popover)    │  │              │  │                           │  │   │
│   │  └──────┬───────┘  └──────┬───────┘  └─────────┬─────────────────┘  │   │
│   │         │                 │                     │                    │   │
│   │         └─────────┬───────┴─────────────────────┘                    │   │
│   │                   ▼                                                  │   │
│   │  ┌────────────────────────────────────────────────────────────────┐  │   │
│   │  │                    CORE SERVICES                               │  │   │
│   │  │                                                                │  │   │
│   │  │  ScheduleManager ─── Canonical schedule logic, next-day rules  │  │   │
│   │  │  WarningCoordinator ─ Escalation timing, overlay management    │  │   │
│   │  │  ExtensionManager ── Budget tracking, request validation       │  │   │
│   │  │  CalendarBridge ──── EventKit queries, meeting detection       │  │   │
│   │  │  WorkTimer ───────── Active-time tracking, idle detection      │  │   │
│   │  │  CloudKitSync ────── Push/pull state, subscriptions, conflict  │  │   │
│   │  │  NotificationMgr ─── UNUserNotificationCenter scheduling       │  │   │
│   │  │                                                                │  │   │
│   │  └───────┬──────────────────────┬─────────────────────────────────┘  │   │
│   │          │                      │                                    │   │
│   │          │ XPC                  │ Unix Socket                        │   │
│   │          │ (Mach IPC)           │ (mcp.sock)                         │   │
│   │          ▼                      ▼                                    │   │
│   └──────────┼──────────────────────┼────────────────────────────────────┘   │
│              │                      │                                        │
│   ┌──────────┼───────┐   ┌─────────┼──────────┐   ┌──────────────────────┐  │
│   │  WidgetKit       │   │  curfew-mcp         │   │  curfew-ctl          │  │
│   │  Extension       │   │  (MCP Server)        │   │  (CLI tool)          │  │
│   │                  │   │                      │   │                      │  │
│   │  TimelineProvider│   │  stdio ◄──► Client   │   │  sudo override       │  │
│   │  reads shared    │   │  HTTP  ◄──► Client   │   │  schedule query      │  │
│   │  App Group data  │   │                      │   │  status check        │  │
│   │                  │   │  Reads: App Group,    │   │                      │  │
│   │  Small / Med /   │   │    SQLite, state.plist│   │  Reads: state.plist  │  │
│   │  Large sizes     │   │  Writes: SQLite →     │   │  Writes: override    │  │
│   │                  │   │    signal via socket   │   │    flag (sudo)       │  │
│   └──────────────────┘   └──────────────────────┘   └──────────────────────┘  │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ROOT / PRIVILEGED SPACE (runs as root via launchd)                         │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │                     PRIVILEGED HELPER                                │   │
│   │              (com.curfew.enforcer, LaunchDaemon)                     │   │
│   │                                                                      │   │
│   │  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────────┐  │   │
│   │  │ Screen Locker   │  │ Event Tap Mgr   │  │ Shutdown Controller  │  │   │
│   │  │                 │  │                  │  │                      │  │   │
│   │  │ NSWindow at     │  │ CGEvent tap at   │  │ Graceful app quit   │  │   │
│   │  │ .screenSaver    │  │ session level    │  │ → system shutdown   │  │   │
│   │  │ level, covers   │  │                  │  │                      │  │   │
│   │  │ all displays    │  │ Blocks: Cmd+Tab, │  │ Configurable delay  │  │   │
│   │  │ and Spaces      │  │ Cmd+Q, Cmd+Opt+  │  │ with countdown      │  │   │
│   │  │                 │  │ Esc, Cmd+Space   │  │                      │  │   │
│   │  └─────────────────┘  └──────────────────┘  └──────────────────────┘  │   │
│   │                                                                      │   │
│   │  ┌────────────────┐  ┌─────────────────┐                             │   │
│   │  │ Process Watch   │  │ Boot Check       │                            │   │
│   │  │                 │  │                  │                             │   │
│   │  │ Monitors lock   │  │ On login: read   │                            │   │
│   │  │ overlay proc,   │  │ state.plist →    │                            │   │
│   │  │ restarts if     │  │ activate lock    │                            │   │
│   │  │ killed          │  │ if in lockout    │                            │   │
│   │  │                 │  │ window           │                            │   │
│   │  └─────────────────┘  └──────────────────┘                            │   │
│   │                                                                      │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   DATA STORES                                                                │
│                                                                              │
│   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │
│   │ App Group         │  │ /Library/App     │  │ iCloud                   │  │
│   │ Container         │  │ Support/Curfew/  │  │ (CloudKit Private DB)    │  │
│   │                   │  │                  │  │                          │  │
│   │ • UserDefaults    │  │ • state.plist    │  │ • Schedule record        │  │
│   │   (schedule)      │  │   (root-owned)   │  │ • LockoutState record    │  │
│   │ • SQLite DB       │  │ • HMAC key       │  │ • Device records         │  │
│   │   (history,       │  │ • Override log   │  │ • DeviceActivity records │  │
│   │    budgets,       │  │                  │  │                          │  │
│   │    overrides)     │  │ Daemon reads     │  │ Synced via               │  │
│   │                   │  │ and writes;      │  │ CKSubscription +         │  │
│   │ Shared by: App,   │  │ app reads only   │  │ silent push              │  │
│   │ Widget, MCP       │  │                  │  │                          │  │
│   └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

### A2: Onboarding Flow

The first-run experience. Each screen is a single focus. The flow is linear with optional branches.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  SCREEN 1: WELCOME                                                      │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │              ┌─────────────────────────────┐                      │  │
│  │              │         🌙                   │                      │  │
│  │              │   Curfew logo / icon         │                      │  │
│  │              └─────────────────────────────┘                      │  │
│  │                                                                   │  │
│  │      "Curfew helps you stop working on time.                      │  │
│  │       Not tomorrow. Today."                                       │  │
│  │                                                                   │  │
│  │      Brief explanation of the commitment model:                   │  │
│  │      "Set your schedule when you're thinking clearly.             │  │
│  │       Curfew enforces it when you're not."                        │  │
│  │                                                                   │  │
│  │      Animation: sunset gradient transitioning                     │  │
│  │      from work → rest, previewing the lockout aesthetic           │  │
│  │                                                                   │  │
│  │                               [ Get Started → ]                   │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                        │                                │
│                                        ▼                                │
│  SCREEN 2: SCHEDULE SETUP                                               │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │      "When should your workday end?"                              │  │
│  │                                                                   │  │
│  │      ┌─────────────────────────────────────────────────────────┐  │  │
│  │      │  PRESET CARDS (tap to select)                           │  │  │
│  │      │                                                         │  │  │
│  │      │  ┌───────────┐  ┌───────────┐  ┌───────────┐           │  │  │
│  │      │  │  9 to 5   │  │  Startup  │  │  Custom   │           │  │  │
│  │      │  │           │  │  Hours    │  │           │           │  │  │
│  │      │  │ End: 5 PM │  │ End: 8 PM │  │ You pick  │           │  │  │
│  │      │  │ Wake: 9AM │  │ Wake: 9AM │  │           │           │  │  │
│  │      │  └───────────┘  └───────────┘  └───────────┘           │  │  │
│  │      └─────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │      IF "Custom" selected:                                        │  │
│  │      ┌─────────────────────────────────────────────────────────┐  │  │
│  │      │  Weekly calendar grid                                   │  │  │
│  │      │                                                         │  │  │
│  │      │  Mon  ████████████████░░░░░░░░  9AM ──────── 6PM       │  │  │
│  │      │  Tue  ████████████████░░░░░░░░  9AM ──────── 6PM       │  │  │
│  │      │  Wed  ████████████████░░░░░░░░  9AM ──────── 6PM       │  │  │
│  │      │  Thu  ████████████████░░░░░░░░  9AM ──────── 6PM       │  │  │
│  │      │  Fri  ████████████████░░░░░░░░  9AM ──────── 6PM       │  │  │
│  │      │  Sat  ░░░░░░░░░░░░░░░░░░░░░░░░  Day Off               │  │  │
│  │      │  Sun  ░░░░░░░░░░░░░░░░░░░░░░░░  Day Off               │  │  │
│  │      │                                                         │  │  │
│  │      │  (drag handles to adjust per-day times)                 │  │  │
│  │      └─────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │      Curfew mode:                                                 │  │
│  │      ( ) Fixed time — "Lock at 6:00 PM"                           │  │
│  │      ( ) Hours worked — "Lock after 8 hours"                      │  │
│  │      ( ) Combined — "6:00 PM or 8 hours, whichever first"         │  │
│  │                                                                   │  │
│  │                      [ ← Back ]    [ Continue → ]                 │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                        │                                │
│                                        ▼                                │
│  SCREEN 3: FLEXIBILITY                                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │      "Life happens. Here's your safety valve."                    │  │
│  │                                                                   │  │
│  │      Extensions per week:                                         │  │
│  │      ┌─────┐                                                      │  │
│  │      │  3  │  ◄──── stepper (1–5)                                 │  │
│  │      └─────┘                                                      │  │
│  │                                                                   │  │
│  │      Extension duration:                                          │  │
│  │      [ 10 min ]  [ ● 15 min ]  [ 30 min ]                        │  │
│  │                                                                   │  │
│  │      Emergency overrides per week:                                │  │
│  │      ┌─────┐                                                      │  │
│  │      │  2  │  ◄──── stepper (1–3)                                 │  │
│  │      └─────┘                                                      │  │
│  │                                                                   │  │
│  │      ┌──────────────────────────────────────────────────────┐     │  │
│  │      │  ℹ️  Extensions let you push curfew by 15 minutes.   │     │  │
│  │      │  Overrides unlock your Mac for 30 minutes but        │     │  │
│  │      │  require a 5-minute cooldown + written reason.       │     │  │
│  │      │  Both are logged in your weekly review.              │     │  │
│  │      └──────────────────────────────────────────────────────┘     │  │
│  │                                                                   │  │
│  │                      [ ← Back ]    [ Continue → ]                 │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                        │                                │
│                                        ▼                                │
│  SCREEN 4: PERMISSIONS                                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │      "Curfew needs a few permissions to work."                    │  │
│  │                                                                   │  │
│  │      ┌──────────────────────────────────────────────────────┐     │  │
│  │      │  🔔  Notifications                    [ Grant ✓ ]    │     │  │
│  │      │      "To warn you before curfew"                     │     │  │
│  │      ├──────────────────────────────────────────────────────┤     │  │
│  │      │  🛡️  Accessibility                    [ Grant   ]    │     │  │
│  │      │      "To block keyboard shortcuts                    │     │  │
│  │      │       during lockout (required)"                     │     │  │
│  │      ├──────────────────────────────────────────────────────┤     │  │
│  │      │  🔑  Admin Password                   [ Grant   ]    │     │  │
│  │      │      "To install the privileged helper                │     │  │
│  │      │       that survives restarts (one-time)"             │     │  │
│  │      ├──────────────────────────────────────────────────────┤     │  │
│  │      │  📅  Calendar Access (optional)        [ Skip  ]     │     │  │
│  │      │      "To detect meetings that run late"              │     │  │
│  │      └──────────────────────────────────────────────────────┘     │  │
│  │                                                                   │  │
│  │      Each permission shows WHY it's needed.                       │  │
│  │      Required items block progress; optional can be skipped.      │  │
│  │                                                                   │  │
│  │                      [ ← Back ]    [ Continue → ]                 │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                        │                                │
│                                        ▼                                │
│  SCREEN 4.5: MULTI-DEVICE (conditional — only if iCloud detected)       │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │      "Curfew found 1 other Mac on your iCloud account."           │  │
│  │                                                                   │  │
│  │      ┌──────────────────────────────────────────────────────┐     │  │
│  │      │  💻  Mac Studio                                      │     │  │
│  │      │      "Sync schedule and lockout across both Macs?"   │     │  │
│  │      └──────────────────────────────────────────────────────┘     │  │
│  │                                                                   │  │
│  │      [ Sync both Macs ]          [ Keep independent ]             │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                        │                                │
│                                        ▼                                │
│  SCREEN 4.75: MCP (conditional — only if Claude Desktop detected)       │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │      "Claude Desktop detected! 🎉"                                │  │
│  │                                                                   │  │
│  │      "Add Curfew as an MCP server so Claude can help              │  │
│  │       manage your time, prioritize tasks, and remind              │  │
│  │       you when curfew is approaching."                            │  │
│  │                                                                   │  │
│  │      [ Add to Claude Desktop ]       [ Skip for now ]             │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                        │                                │
│                                        ▼                                │
│  SCREEN 5: CONFIRMATION                                                 │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │      "Here's your plan."                                          │  │
│  │                                                                   │  │
│  │      ┌──────────────────────────────────────────────────────┐     │  │
│  │      │                                                      │     │  │
│  │      │  Schedule:    Mon–Fri, curfew at 6:00 PM             │     │  │
│  │      │  Unlock:      8:00 AM each morning                   │     │  │
│  │      │  Mode:        Fixed time                             │     │  │
│  │      │  Extensions:  3 per week (15 min each)               │     │  │
│  │      │  Overrides:   2 per week (30 min, with cooldown)     │     │  │
│  │      │  Shutdown:    10 min after lockout                   │     │  │
│  │      │  Sync:        Mac Studio + MacBook Pro               │     │  │
│  │      │  MCP:         Connected to Claude Desktop            │     │  │
│  │      │                                                      │     │  │
│  │      └──────────────────────────────────────────────────────┘     │  │
│  │                                                                   │  │
│  │      "Starting tomorrow, Curfew will enforce this schedule.       │  │
│  │       You can always adjust it — changes take effect               │  │
│  │       the next day."                                              │  │
│  │                                                                   │  │
│  │      "We're not your boss. We're the friend who                   │  │
│  │       tells you to go home."                                      │  │
│  │                                                                   │  │
│  │                    [ ← Back ]   [ 🟢 Activate Curfew ]            │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### A3: Warning Escalation State Machine

The lifecycle of a single workday from the enforcement system's perspective.

```
                    ┌──────────────────┐
                    │                  │
                    │    INACTIVE      │
                    │  (outside work   │
      Day off or ──►│   hours, or     │◄── Unlock time
      disabled      │   day off)       │    reached
                    │                  │
                    └────────┬─────────┘
                             │
                             │ Unlock time reached
                             │ (e.g., 8:00 AM)
                             ▼
                    ┌──────────────────┐
                    │                  │
                    │    WORKING       │
                    │                  │
                    │  Menu bar: 🟢    │
                    │  Timer counting  │
                    │  down            │
                    │                  │
                    └────────┬─────────┘
                             │
                             │ T-30 min (or hours limit
                             │ approaching)
                             ▼
                    ┌──────────────────┐
                    │                  │        ┌──────────────────┐
                    │  WARNING PHASE   │        │                  │
                    │                  │        │   EXTENDED       │
                    │  T-30: Notif     │        │                  │
                    │  T-15: Notif +   │◄───────│ Extension used,  │
                    │        amber bar │        │ timer reset to   │
                    │  T-5:  10% dim   │        │ new end time,    │
                    │  T-2:  25% dim   │  Ext   │ re-enter warning │
                    │  T-1:  40% dim   │──────►│ at appropriate   │
                    │        + chime   │ budget │ phase            │
                    │                  │ > 0    │                  │
                    └────────┬─────────┘        └──────────────────┘
                             │
                             │ T-0 (no extensions used
                             │ or budget exhausted)
                             ▼
                    ┌──────────────────┐
                    │                  │
                    │    LOCKOUT       │
                    │                  │
                    │  Full-screen     │
                    │  overlay active  │
                    │  Event tap on    │
                    │  Keyboard blocked│
                    │                  │
                    │  Menu bar: 🔒    │
                    │  Widget: locked  │
                    │                  │
                    │  State synced    │
                    │  to CloudKit →   │
                    │  other devices   │
                    │  lock too        │
                    │                  │
                    ├──────────────────┤
                    │ "Convince Me"    │
                    │  flow available  │
                    │  if overrides    │
                    │  remain          │
                    │                  │
                    └───┬──────────┬───┘
                        │          │
           Shutdown     │          │  Override granted
           delay        │          │  (30 min)
           elapsed      │          │
                        ▼          ▼
          ┌──────────────┐  ┌──────────────────┐
          │              │  │                  │
          │  SHUTDOWN    │  │  OVERRIDE        │
          │              │  │  (temporary)     │
          │  Graceful    │  │                  │
          │  app quit →  │  │  30 min timer    │
          │  system      │  │  then → LOCKOUT  │
          │  shutdown    │  │                  │
          │              │  │  Logged with     │
          └──────────────┘  │  device + reason │
                            │                  │
                            └──────────────────┘
```

---

### A4: Bypass Protection Layers

How the system prevents circumvention, from easiest to hardest to defeat.

```
CIRCUMVENTION ATTEMPT              DEFENSE LAYER                    FRICTION LEVEL
═══════════════════════════════════════════════════════════════════════════════════

"Click away the overlay"    ──►    Window at .screenSaver level,    ████░░░░░░
                                   captures all input               Trivial block

"Cmd+Tab to another app"   ──►    CGEvent tap swallows Cmd+Tab,    ████░░░░░░
                                   Cmd+Q, Cmd+Space, Cmd+Opt+Esc   Trivial block

"Force Quit from Dock"     ──►    Event tap blocks Cmd+Opt+Esc;    █████░░░░░
                                   Dock right-click quit caught     Low friction

"Kill app from Activity    ──►    Process watchdog in daemon        ██████░░░░
 Monitor"                          restarts overlay within seconds  Medium friction

"Kill the daemon process"  ──►    launchd KeepAlive: true           ██████░░░░
                                   auto-restarts immediately        Medium friction

"Restart the Mac"          ──►    LaunchDaemon starts at boot,      ███████░░░
                                   checks state.plist before        High friction
                                   user session loads

"Delete the LaunchDaemon   ──►    Requires: sudo + knowledge of     ████████░░
 plist and restart"                plist location + terminal         Very high
                                   access during lockout (blocked)

"Boot into Recovery Mode   ──►    No defense — this is the          ██████████
 and remove files"                 documented escape hatch.          Maximum friction
                                   Requires: full reboot into        (deliberate effort)
                                   Recovery, file navigation,
                                   then another reboot

"Use the Convince Me flow" ──►    5-min cooldown + 50-char          ████████░░
                                   justification + press-and-hold   Very high
                                   + limited weekly budget           (but sanctioned)

"Use curfew-ctl override"  ──►    Requires: open terminal (blocked  ████████░░
                                   during lockout) + sudo +         Very high
                                   limited to 2/week                (but sanctioned)

═══════════════════════════════════════════════════════════════════════════════════

DESIGN PRINCIPLE: We're not building a prison. We're making "just 5 more
minutes" harder than going to bed. Every sanctioned escape path is logged
and budget-limited. Unsanctioned paths require enough friction that the
impulse dies before the user completes them.
```

---

### A5: CloudKit Sync Flow

How state propagates between devices when lockout triggers.

```
       MAC STUDIO                       iCLOUD                        MACBOOK PRO
       (active device)                  (CloudKit)                    (idle device)
       ═══════════════                  ══════════                    ═══════════════

T-0 reached
       │
       ├─► WarningCoordinator
       │   triggers lockout
       │
       ├─► Screen Locker activates
       │   (local, immediate)
       │
       ├─► Writes state.plist           
       │   isLocked: true               
       │   lockoutStarted: now          
       │   unlockTime: 8:00 AM          
       │                                
       ├─► CloudKitSync pushes ──────►  LockoutState record
       │   updated record               updated in private DB
       │                                       │
       │                                       │ CKSubscription
       │                                       │ triggers silent
       │                                       │ push notification
       │                                       │
       │                                       └──────────────────► Notification
       │                                                            received
       │                                                                │
       │                                                                ├─► CloudKitSync
       │                                                                │   pulls updated
       │                                                                │   LockoutState
       │                                                                │
       │                                                                ├─► Writes local
       │                                                                │   state.plist
       │                                                                │
       │                                                                ├─► Daemon reads
       │                                                                │   state.plist
       │                                                                │
       │                                                                └─► Screen Locker
       │                                                                    activates
       │                                                                    (< 5 sec total)
       │
       │   EXTENSION USED ON MAC STUDIO
       │
       ├─► ExtensionManager grants
       │   15 min extension
       │
       ├─► Screen Locker deactivates
       │   (local)
       │
       ├─► CloudKitSync pushes ──────►  LockoutState record
       │   isLocked: false               extensionsUsedThisWeek: 2
       │   newEndTime: 6:15 PM                 │
       │   extensionsUsed: 2                   └──────────────────► MacBook receives
       │                                                            update, deactivates
       │                                                            its own lockout
       │


       OFFLINE SCENARIO (MacBook was asleep)
       ═══════════════════════════════════════

Mac Studio locks at 6 PM,           LockoutState updated
MacBook was asleep                   in CloudKit
                                            │
                                            │  (MacBook wakes
                                            │   at 9 PM)
                                            │
                                            └──────────────────► MacBook wakes,
                                                                 app launches,
                                                                 CloudKitSync pulls
                                                                 state
                                                                     │
                                                                     ├─► Is 9 PM within
                                                                     │   lockout window?
                                                                     │   (6 PM – 8 AM)
                                                                     │   YES
                                                                     │
                                                                     └─► Lockout activates
                                                                         retroactively
```

---

### A6: "Convince Me" Override Flow (User-Facing Unlock)

Detailed state machine for the lockout-screen override request.

```
┌─────────────────────────────────┐
│                                 │
│        LOCKOUT SCREEN           │
│                                 │
│   Beautiful animated background │
│   "Great work today."           │
│   "Unlocks at 8:00 AM"         │
│                                 │
│              ...                │
│                                 │
│     ┌─ "Need to get back in?"  │ ◄── small, low-contrast link
│     │   (only visible if       │     at bottom of screen
│     │    overrides remain)     │
│     │                          │
│     │  If budget = 0:          │
│     │  "No overrides remaining │
│     │   this week."            │
│     │  (link disabled)         │
│     │                          │
└─────┼──────────────────────────┘
      │
      │ tap
      ▼
┌──────────────────────────────────┐
│                                  │
│  STAGE 1: COOLDOWN               │
│                                  │
│  "Still sure? 🤔"                │
│                                  │
│  ┌────────────────────────────┐  │
│  │                            │  │
│  │        4:32                │  │ ◄── 5-minute countdown
│  │                            │  │     (cannot be skipped)
│  │    "Most impulses fade     │  │
│  │     in 5 minutes."         │  │
│  │                            │  │
│  └────────────────────────────┘  │
│                                  │
│          [ Cancel ]              │ ──► back to LOCKOUT
│                                  │
└─────────────┬────────────────────┘
              │
              │ countdown reaches 0:00
              ▼
┌──────────────────────────────────┐
│                                  │
│  STAGE 2: JUSTIFICATION          │
│                                  │
│  "Why do you need to get back    │
│   on right now?"                 │
│                                  │
│  ┌────────────────────────────┐  │
│  │                            │  │
│  │  (large, comfortable       │  │ ◄── text field, min 50 chars
│  │   text field)              │  │     no visible counter until
│  │                            │  │     user is under 50 chars
│  │                            │  │
│  │                            │  │
│  │                     38/50  │  │ ◄── counter appears when close
│  └────────────────────────────┘  │
│                                  │
│  [ Cancel ]       [ Submit ]     │ ──► Submit disabled until ≥ 50
│                                  │
└─────────────┬────────────────────┘
              │
              │ submit tapped (≥ 50 chars)
              ▼
┌──────────────────────────────────┐
│                                  │
│  STAGE 3: CONSEQUENCES           │
│                                  │
│  "This will:"                    │
│                                  │
│  • Count as 1 of your 2 weekly   │
│    overrides                     │
│  • Be logged at 11:47 PM        │
│    on MacBook Pro                │
│  • Unlock your Mac for           │
│    30 minutes only               │
│                                  │
│  ┌────────────────────────────┐  │
│  │                            │  │
│  │   ████████████████████     │  │ ◄── press-and-hold button
│  │   Hold to confirm (3s)    │  │     (3 seconds, shows
│  │                            │  │      fill progress)
│  └────────────────────────────┘  │
│                                  │
│  [ Cancel — go back to sleep ]   │ ──► back to LOCKOUT
│                                  │
└─────────────┬────────────────────┘
              │
              │ held for 3 seconds
              ▼
┌──────────────────────────────────┐
│                                  │
│  OVERRIDE ACTIVE                 │
│                                  │
│  Lock screen fades out           │
│  Desktop restored                │
│                                  │
│  Menu bar shows: 🔴 29:43        │ ◄── countdown to re-lock
│  Floating mini-timer in corner   │
│                                  │
│  At T-5 min: warning overlay     │
│  At T-0: lockout resumes         │
│                                  │
│  Lockout screen returns:         │
│  "Welcome back. Hope you got     │
│   what you needed."              │
│                                  │
└──────────────────────────────────┘
```

---

### A7: IPC & Data Flow Diagram

How all processes communicate and share data at runtime.

```
┌──────────────┐     XPC (Mach IPC)      ┌──────────────────┐
│  Main App    │◄────────────────────────►│  Privileged      │
│  Process     │  • lockout commands      │  Helper          │
│              │  • state queries         │  (root)          │
│              │  • shutdown trigger      │                  │
└──────┬───┬───┘                          └────────┬─────────┘
       │   │                                       │
       │   │ Unix Domain Socket                    │ reads
       │   │ (~/Library/.../mcp.sock)              │
       │   │                                       ▼
       │   │  ┌──────────────┐          ┌──────────────────┐
       │   └─►│  curfew-mcp  │          │  state.plist     │
       │      │  (MCP Server)│          │  /Library/App    │
       │      └──────┬───────┘          │  Support/Curfew/ │
       │             │                  │                  │
       │             │ reads            │  Owner: root     │
       │             ▼                  │  App: read only  │
       │      ┌──────────────┐          │  Daemon: r/w     │
       │      │              │          └──────────────────┘
       │      │  Shared Data │
       ├─────►│  Layer       │◄───── WidgetKit Extension (reads)
       │      │              │
       │      │ ┌──────────┐ │
       │      │ │UserDflts │ │◄──── App Group suite
       │      │ │(schedule)│ │      group.com.curfew.shared
       │      │ └──────────┘ │
       │      │ ┌──────────┐ │
       │      │ │ SQLite   │ │◄──── App Group container
       │      │ │(history, │ │      ~/Library/Group Containers/
       │      │ │ budgets, │ │      group.com.curfew.shared/
       │      │ │ overrides│ │      curfew.sqlite
       │      │ └──────────┘ │
       │      └──────────────┘
       │
       │  CloudKit API
       │  (CKContainer, CKPrivateDatabase)
       │
       ▼
┌──────────────────────────────────────────────┐
│                                              │
│              iCloud (CloudKit)               │
│                                              │
│  ┌────────────┐ ┌────────────┐ ┌──────────┐ │
│  │  Schedule   │ │ LockoutSt. │ │  Device  │ │
│  │  record     │ │ record     │ │  records │ │
│  └────────────┘ └────────────┘ └──────────┘ │
│  ┌────────────────────────────────────────┐  │
│  │         DeviceActivity records         │  │
│  │         (heartbeats, per-device)       │  │
│  └────────────────────────────────────────┘  │
│                                              │
│           CKSubscription → silent push       │
│           to all devices on state change     │
│                                              │
└──────────────────────────────────────────────┘
```

---

### A8: Extension & Override Budget State Machine

How the weekly budget is tracked and enforced across devices.

```
                          WEEKLY RESET
                     (Monday at unlock time)
                              │
                              ▼
                 ┌────────────────────────┐
                 │                        │
                 │  FULL BUDGET           │
                 │                        │
                 │  Extensions: 3/3       │
                 │  Overrides:  2/2       │
                 │                        │
                 └───────────┬────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
    Extension requested              Override requested
    (warning phase only,             ("Convince Me" flow
     any device)                      or CLI, any device)
              │                             │
              ▼                             ▼
    ┌────────────────────┐        ┌────────────────────┐
    │ Budget check       │        │ Budget check       │
    │                    │        │                    │
    │ extensions > 0?    │        │ overrides > 0?     │
    │                    │        │                    │
    └──┬──────────┬──────┘        └──┬──────────┬──────┘
       │          │                  │          │
      YES         NO                YES         NO
       │          │                  │          │
       ▼          ▼                  ▼          ▼
    Granted    Denied             Granted    Denied
       │       "No extensions"      │       "No overrides
       │        remain"             │        remaining this
       │                            │        week."
       ▼                            ▼
    ┌────────────────────┐  ┌────────────────────┐
    │ Update state       │  │ Update state       │
    │                    │  │                    │
    │ extensions -= 1    │  │ overrides -= 1     │
    │ Push to CloudKit   │  │ Push to CloudKit   │
    │ All devices see    │  │ All devices see    │
    │ updated budget     │  │ updated budget     │
    │                    │  │                    │
    │ Log: device,       │  │ Log: device,       │
    │  timestamp         │  │  timestamp, reason │
    └────────────────────┘  └────────────────────┘
              │                        │
              ▼                        ▼
    ┌────────────────────────────────────────┐
    │                                        │
    │  PARTIALLY USED                        │
    │                                        │
    │  Extensions: 2/3   Overrides: 1/2      │
    │                                        │
    │  Shown in:                             │
    │  • Menu bar popover                    │
    │  • Widget (medium/large)               │
    │  • MCP get_extension_budget            │
    │  • Warning overlay button text         │
    │  • Weekly retrospective                │
    │                                        │
    └────────────────────────────────────────┘
              │
              │ (continues until weekly reset
              │  or all budgets exhausted)
              ▼
    ┌────────────────────────────────────────┐
    │                                        │
    │  EXHAUSTED                             │
    │                                        │
    │  Extensions: 0/3   Overrides: 0/2      │
    │                                        │
    │  • Extension button disabled in        │
    │    warning overlay                     │
    │  • "Convince Me" link hidden on        │
    │    lockout screen                      │
    │  • CLI `curfew-ctl override` refuses   │
    │  • MCP request_extension returns       │
    │    granted: false                      │
    │                                        │
    │  "Hard lockout" — no escape until      │
    │  unlock time (except Recovery Mode)    │
    │                                        │
    └────────────────────────────────────────┘
```

---

### A9: CI/CD Pipeline

Build, sign, notarize, and release flow.

```
Developer pushes
git tag v1.2.0
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  GITHUB ACTIONS                                                  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  STAGE 1: BUILD                                            │  │
│  │                                                            │  │
│  │  xcodebuild archive                                        │  │
│  │    -scheme Curfew                                          │  │
│  │    -destination "generic/platform=macOS"                   │  │
│  │    -archivePath Curfew.xcarchive                           │  │
│  │                                                            │  │
│  │  Produces: Universal Binary (arm64 + x86_64)               │  │
│  │  Targets: Curfew.app, curfew-mcp, curfew-ctl,             │  │
│  │           CurfewHelper, CurfewWidget                       │  │
│  └──────────────────────────┬─────────────────────────────────┘  │
│                             ▼                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  STAGE 2: SIGN                                             │  │
│  │                                                            │  │
│  │  codesign --deep --force --options runtime                 │  │
│  │    --sign "Developer ID Application: ..."                  │  │
│  │    Curfew.app                                              │  │
│  │                                                            │  │
│  │  codesign (same) CurfewHelper                              │  │
│  │    + SMAuthorizedClients entry                             │  │
│  │                                                            │  │
│  │  Keychain: imported from GitHub Secrets                    │  │
│  │  (CERTIFICATE_P12 + CERTIFICATE_PASSWORD)                  │  │
│  └──────────────────────────┬─────────────────────────────────┘  │
│                             ▼                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  STAGE 3: PACKAGE                                          │  │
│  │                                                            │  │
│  │  create-dmg                                                │  │
│  │    --volname "Curfew"                                      │  │
│  │    --window-size 600 400                                   │  │
│  │    --icon-size 128                                         │  │
│  │    --icon "Curfew.app" 150 200                             │  │
│  │    --app-drop-link 450 200                                 │  │
│  │    --background dmg-background@2x.png                      │  │
│  │    Curfew-1.2.0.dmg                                        │  │
│  └──────────────────────────┬─────────────────────────────────┘  │
│                             ▼                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  STAGE 4: NOTARIZE                                         │  │
│  │                                                            │  │
│  │  xcrun notarytool submit Curfew-1.2.0.dmg                  │  │
│  │    --apple-id $APPLE_ID                                    │  │
│  │    --team-id $TEAM_ID                                      │  │
│  │    --password $APP_SPECIFIC_PASSWORD                        │  │
│  │    --wait                        (blocks until complete)   │  │
│  │                                                            │  │
│  │  xcrun stapler staple Curfew-1.2.0.dmg                     │  │
│  │                          (attach ticket for offline verify) │  │
│  └──────────────────────────┬─────────────────────────────────┘  │
│                             ▼                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  STAGE 5: RELEASE                                          │  │
│  │                                                            │  │
│  │  1. Upload Curfew-1.2.0.dmg to GitHub Release (tag v1.2.0)│  │
│  │                                                            │  │
│  │  2. Generate Sparkle appcast entry:                        │  │
│  │     generate_appcast ./release/                            │  │
│  │     → appcast.xml updated with new version, EdDSA sig      │  │
│  │     → Push to gh-pages branch (or release assets)          │  │
│  │                                                            │  │
│  │  3. Open PR to homebrew/homebrew-cask:                     │  │
│  │     Update curfew.rb with new version + SHA256             │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
  Users receive update via:
  • Sparkle "New version available" dialog (existing users)
  • `brew upgrade --cask curfew` (Homebrew users)
  • Direct download from curfew.app / GitHub Releases (new users)
```

---

### A10: Xcode Project Structure

Target dependency graph for developers building from source.

```
Curfew.xcodeproj (or Package.swift workspace)
│
├── CurfewShared (Swift Package / Framework)
│   │   Shared by all targets. No UI dependencies.
│   │
│   ├── Models/
│   │   ├── WorkSchedule.swift          // Schedule data model
│   │   ├── DayRecord.swift             // Daily usage record
│   │   ├── DeviceInfo.swift            // Device identity model
│   │   └── CurfewState.swift           // Lockout state enum + model
│   │
│   ├── Persistence/
│   │   ├── DatabaseManager.swift       // SQLite (via GRDB) read/write
│   │   ├── SharedDefaults.swift        // App Group UserDefaults wrapper
│   │   └── StatePlistManager.swift     // state.plist read (+ HMAC verify)
│   │
│   ├── Sync/
│   │   ├── CloudKitSyncManager.swift   // CKContainer, subscriptions, push
│   │   ├── ConflictResolver.swift      // Last-write-wins + merge logic
│   │   └── DeviceRegistry.swift        // Device heartbeat, active detection
│   │
│   └── IPC/
│       ├── XPCProtocol.swift           // XPC interface definition
│       └── SocketClient.swift          // Unix domain socket for MCP → App
│
├── Curfew (Main App Target — .app bundle)
│   │   Dependencies: CurfewShared, SwiftUI, AppKit, CloudKit,
│   │                 EventKit, UserNotifications, ServiceManagement
│   │
│   ├── App/
│   │   ├── CurfewApp.swift             // @main, MenuBarExtra setup
│   │   └── AppDelegate.swift           // NSApplicationDelegate for AppKit hooks
│   │
│   ├── Views/
│   │   ├── MenuBarPopover.swift        // Timer, schedule, extension button
│   │   ├── SettingsView.swift          // Tabbed settings (Schedule, Flex, Integrations, Devices, Advanced)
│   │   ├── OnboardingView.swift        // Multi-step onboarding flow
│   │   ├── RetrospectiveView.swift     // Weekly summary with charts
│   │   └── WarningOverlay.swift        // Translucent dimming overlay
│   │
│   ├── Services/
│   │   ├── ScheduleManager.swift       // Core scheduling logic
│   │   ├── WarningCoordinator.swift    // Escalation state machine
│   │   ├── ExtensionManager.swift      // Budget tracking, grant/deny
│   │   ├── CalendarBridge.swift        // EventKit meeting detection
│   │   ├── WorkTimer.swift             // Active time tracking, idle detection
│   │   └── NotificationManager.swift   // UNUserNotificationCenter scheduling
│   │
│   └── Resources/
│       ├── Assets.xcassets             // App icon, menu bar glyphs, colors
│       ├── Localizable.strings         // All user-facing strings
│       ├── LockoutMessages.json        // Curated lockout screen messages
│       └── Sounds/                     // Warning chimes, countdown tones
│
├── CurfewHelper (Privileged Helper Target — standalone executable)
│   │   Dependencies: CurfewShared, AppKit (for NSWindow), Foundation
│   │   Code-signed with SMAuthorizedClients
│   │   Installed as LaunchDaemon via SMAppService
│   │
│   ├── HelperMain.swift                // Entry point, launchd lifecycle
│   ├── ScreenLocker.swift              // NSWindow at .screenSaver level
│   ├── EventTapManager.swift           // CGEvent tap creation/management
│   ├── ShutdownController.swift        // Graceful quit + system shutdown
│   ├── ProcessWatchdog.swift           // Monitor + restart overlay process
│   ├── BootChecker.swift               // On-login state check
│   ├── ConvinceMeFlow.swift            // Cooldown, justification, confirm UI
│   └── Info.plist                      // SMAuthorizedClients, LaunchDaemon keys
│
├── CurfewWidget (WidgetKit Extension Target)
│   │   Dependencies: CurfewShared, WidgetKit, SwiftUI
│   │
│   ├── CurfewWidget.swift              // Widget definition, configuration
│   ├── TimeRemainingProvider.swift     // TimelineProvider
│   ├── SmallWidgetView.swift           // Circular countdown
│   ├── MediumWidgetView.swift          // Countdown + schedule + budget
│   └── LargeWidgetView.swift           // Countdown + schedule + weekly chart
│
├── CurfewMCP (MCP Server Target — standalone executable)
│   │   Dependencies: CurfewShared, MCP (swift-sdk), ServiceLifecycle, Logging
│   │
│   ├── MCPMain.swift                   // Server setup, transport init
│   ├── CurfewTools.swift               // Tool definitions (ListTools handler)
│   └── ToolHandlers.swift              // CallTool dispatch + implementation
│
├── CurfewCTL (CLI Target — standalone executable)
│   │   Dependencies: CurfewShared, ArgumentParser
│   │
│   ├── CTLMain.swift                   // @main, command routing
│   ├── OverrideCommand.swift           // `sudo curfew-ctl override`
│   ├── StatusCommand.swift             // `curfew-ctl status`
│   └── ScheduleCommand.swift           // `curfew-ctl schedule`
│
└── Tests/
    ├── CurfewSharedTests/              // Unit tests for models, persistence, sync
    ├── CurfewTests/                    // Integration tests for services
    └── CurfewMCPTests/                 // MCP tool handler tests
```

---

### A11: Menu Bar & Widget Visual States

Reference for all visual states a developer needs to implement.

```
MENU BAR ICON STATES
═══════════════════════════════════════════════════

  🟢 clock    Working, > 1 hour remaining
  🟠 clock    Warning phase, < 1 hour remaining
  🔴 clock    Critical, < 15 minutes remaining
  ⚪ clock    Day off or outside work hours
  🔒 lock     Lockout active


MENU BAR POPOVER STATES
═══════════════════════════════════════════════════

  WORKING (normal):
  ┌──────────────────────────────┐
  │  ⏱ 3h 42m remaining         │
  │                              │
  │  Today: 9 AM – 6 PM         │
  │  Worked: 4h 18m (2 devices)  │
  │  Extensions: 3 left          │
  │                              │
  │  ──────────────────────────  │
  │  ⚙ Settings    📊 This Week │
  └──────────────────────────────┘

  WARNING (< 30 min):
  ┌──────────────────────────────┐
  │  ⏱ 0h 14m remaining   🟠    │
  │                              │
  │  ┌────────────────────────┐  │
  │  │ Need 15 more minutes?  │  │
  │  │ (2 left this week)     │  │
  │  │     [ Hold to extend ] │  │
  │  └────────────────────────┘  │
  │                              │
  │  ──────────────────────────  │
  │  ⚙ Settings    📊 This Week │
  └──────────────────────────────┘

  LOCKOUT:
  ┌──────────────────────────────┐
  │  🔒 Locked                   │
  │                              │
  │  Unlocks at 8:00 AM          │
  │  Worked today: 8h 12m        │
  │                              │
  │  ──────────────────────────  │
  │  ⚙ Settings    📊 This Week │
  └──────────────────────────────┘

  DAY OFF:
  ┌──────────────────────────────┐
  │  ☀️ Day off                   │
  │                              │
  │  Next curfew: Monday 6 PM   │
  │                              │
  │  ──────────────────────────  │
  │  ⚙ Settings    📊 This Week │
  └──────────────────────────────┘


WIDGET STATES (Small / Medium / Large)
═══════════════════════════════════════════════════

  SMALL — Circular countdown ring:

  ┌────────────────┐     ┌────────────────┐     ┌────────────────┐
  │   ╭───────╮    │     │   ╭───────╮    │     │                │
  │   │ 3:42  │ 🟢 │     │   │ 0:14  │ 🟠 │     │   🔒  Locked   │
  │   │  left │    │     │   │  left │    │     │   until        │
  │   ╰───────╯    │     │   ╰───────╯    │     │   8:00 AM 🌅   │
  │                │     │                │     │                │
  └────────────────┘     └────────────────┘     └────────────────┘
   Working (green)        Warning (amber)        Lockout

  MEDIUM — Countdown + context:

  ┌────────────────────────────────────┐
  │  ╭───────╮                         │
  │  │ 3:42  │  Today: 9 AM – 6 PM    │
  │  │  left │  Extensions: 2 left     │
  │  ╰───────╯  Worked: 4h 18m        │
  │              (Mac Studio: 3h,      │
  │               MacBook: 1h 18m)     │
  └────────────────────────────────────┘

  LARGE — Countdown + schedule + weekly chart:

  ┌────────────────────────────────────┐
  │  ╭───────╮  Today: 9 AM – 6 PM    │
  │  │ 3:42  │  Extensions: 2 left    │
  │  │  left │  Streak: 12 days 🔥     │
  │  ╰───────╯                         │
  │                                    │
  │  This week:                        │
  │  Mon ████████░░  8.2h              │
  │  Tue ███████░░░  7.1h              │
  │  Wed ██████████  9.8h  (override)  │
  │  Thu ████████░░  8.0h              │
  │  Fri ████░░░░░░  4.3h  ◄ today    │
  │  Sat ░░░░░░░░░░  day off          │
  └────────────────────────────────────┘
```

---

### A12: Lockout Screen Layout

Visual reference for the full-screen lockout experience.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│                                                                         │
│    Background: Slow-moving aurora / particle field animation             │
│    (respects reduceMotion — falls back to static gradient)              │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                          11:47 PM                                       │
│                                                                         │
│                    SF Pro Display, 72pt                                  │
│                    Light weight, generous tracking                       │
│                                                                         │
│                                                                         │
│                                                                         │
│              "The best code is written                                   │
│                   by a rested mind."                                     │
│                                                                         │
│                    SF Pro, 24pt, 50% opacity                             │
│                    (rotates every 30 seconds                             │
│                     with crossfade)                                      │
│                                                                         │
│                                                                         │
│                                                                         │
│           ┌───────────────────────────────────────┐                     │
│           │  Unlocks at 8:00 AM  ☀️                │                     │
│           │                                       │                     │
│           │  Today: 8h 12m worked across 2 Macs   │                     │
│           │  Streak: 12 days                       │                     │
│           └───────────────────────────────────────┘                     │
│                                                                         │
│              Card: rounded rect, frosted glass blur                      │
│              SF Pro, 16pt                                                │
│                                                                         │
│                                                                         │
│    IF shutdown enabled:                                                  │
│                                                                         │
│           "Your Mac is going to sleep in 8:42"                          │
│            SF Pro, 14pt, 40% opacity                                    │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                      "Need to get back in?"             │
│                                       SF Pro, 12pt, 30% opacity         │
│                                       (deliberatley subtle)             │
│                                       Bottom-right corner               │
│                                       Only if overrides > 0             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

ACCESSIBILITY NOTES:
• VoiceOver reads: "Curfew active. Current time 11:47 PM.
  Your computer unlocks at 8:00 AM. You worked 8 hours
  and 12 minutes today. [Message]. Need to get back in? Button."
• reduceMotion: static gradient, no particle animation
• reduceTransparency: solid dark background, no blur on card
• High contrast: all text at 100% opacity, card has solid border
```

---

*Curfew: Because the best productivity hack is knowing when to stop.*
