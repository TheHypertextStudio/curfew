# Protected work and the break-glass release

Read this if you are about to install the privileged daemon, or if the daemon
has just shut your Mac down and you want it to stop. The break-glass runbook is
at the bottom; if that is why you are here, jump to it.

## The problem

Curfew's lockout is a display and keyboard shield. `OverlayCoordinator` puts a
borderless window on every `NSScreen` at `.screenSaver` level and
`LockoutKeyInterceptor` taps `CGEvent` to swallow ⌘⇥ / ⌘Q / ⌘⌥Esc. Neither
touches a process, so a `claude` or `codex` run started before curfew keeps
running through the night.

Two paths do end processes.

1. `ShutdownWorkflow` → `SystemShutdownController.requestGracefulTermination()`
   sends `terminate()` to every running application except Curfew, then
   AppleScripts a shut down. Terminating Terminal, iTerm, or VS Code takes every
   child process in it, so the agent dies with its window.
2. `Sources/curfew-daemon/main.swift` polls every 15 s and, when the app
   heartbeat is more than 90 s stale during an active lockout, runs
   `/sbin/shutdown -h +1` as root.

Before this change, agents survived only because auto-shutdown defaults off and
the daemon is not installed. That is an accident, not a feature. Turn either
one on and the night's work is gone.

## The model

Three pieces, all in `CurfewKit` so the app, `curfew-ctl`, `curfew-mcp`, and the
root daemon share one definition.

**`ProtectedWorkPolicy`** (`Sources/CurfewKit/Settings/ProtectedWorkPolicy.swift`)
carries the allowlist and the deferral bound. It lives on `CurfewSettings`, so
it syncs and persists with everything else, and it is editable in Settings →
Enforcement → Protected Work. Defaults name common terminal emulators
(Terminal, iTerm2, Ghostty, kitty, Alacritty, WezTerm, Warp, Hyper) and common
agent CLIs (`claude`, `codex`, `aider`, `goose`, `gemini`, plus `ssh`, `mosh`,
`tmux`, `screen`). Those are defaults, not architecture: no enforcement code
knows any specific identifier.

**`ProtectedWorkClaim`** (`Sources/CurfewKit/Storage/ProtectedWorkStore.swift`)
is a lease, not a reservation. A claim carries a label, a source, and an expiry;
the holder renews to keep it alive. An agent that crashes stops renewing and its
protection lapses within one lease, so nothing has to notice the death and clean
up. Claims live at
`~/Library/Application Support/Curfew/protected-work.json`, mode 0600, beside
`mcp-requests.json`. That location — rather than the App Group container where
`app-heartbeat` and `lockout-deadline.json` sit — avoids the macOS "access data
from other apps" prompt that a non-sandboxed app triggers when it touches its
own group container.

**`ProtectedWorkDeferral`** (`Sources/CurfewKit/Domain/ProtectedWorkGate.swift`)
is the bound. Both kill paths run their decision through it, which is what keeps
the app's answer and the daemon's answer the same.

Three surfaces file claims. `curfew-ctl work claim --label … --minutes N`
prints a claim id for a shell wrapper to renew and release. The MCP tool
`curfew_declare_work` does the same for an agent, and `curfew_release_work`
drops it early. The app reads claims every tick.

## Why `curfew_declare_work` is not on the consent queue

`curfew_request_extension` and `curfew_set_schedule` weaken the curfew: they
move when the user gets locked out, so a human approves each one through
`MCPRequestMonitor` and the consent sheet. `curfew_declare_work` does not. It
cannot unlock the display, cannot move the lock time, and cannot extend the
window. It postpones the destructive half of enforcement so unfinished work is
not thrown away, and nothing else.

Queueing it would also be useless exactly when it matters. The daemon's shutdown
fires because the Curfew app has stopped responding — which is precisely when
nobody can approve a consent sheet.

Three things keep it honest instead:

- `ProtectedWorkPolicy.acceptsAgentClaims` lets the user refuse agent claims
  outright, and the tool returns a policy error rather than filing one.
- Every claim expires on its own within one lease (ceiling 30 minutes).
- The total postponement is bounded regardless of how many claims arrive or how
  often they renew.

## The bound: 30 minutes

`maximumDeferralMinutes` defaults to 30, is user-editable, and is clamped to
`1 ... 120` on construction *and* on decode, so neither the Settings UI nor a
hand-edited JSON file can widen it further.

Thirty minutes comfortably outlasts a single agent turn and is a rounding error
against a lockout window measured in hours. A claim that never gets released
therefore costs half an hour of curfew, not the whole night.

The bound is measured **from the moment the destructive action first came due**,
not from the most recent claim. Measuring from the latest claim would let an
agent that keeps renewing hold enforcement off forever, which is the failure the
type exists to prevent. Once the window is spent, the gate returns `proceed` no
matter how fresh the claim is, and a claim filed one second later cannot reopen
it.

The daemon persists the window's start to
`/Library/Application Support/Curfew/deferral-started`, root-owned. `launchd`
will happily respawn the daemon, so an in-memory clock would make the bound
meaningless — restart the process, get a fresh 30 minutes.

## Break-glass

### Why it has to exist

`/sbin/shutdown -h +1` was chosen for the daemon *because* user space cannot
cancel it. That is a reasonable anti-bypass property and an unreasonable trap:
every ordinary recovery move — killing a wedged app, rebooting a crash loop,
debugging enforcement — becomes a forced power-off a minute later, and the only
surface offering to help is behind a locked display. An escape that depends on
the thing that is broken is not an escape.

The daemon must not be installed until this exists. It now does.

### What it is

`curfew-ctl break-glass --reason "…"` writes a signed `BreakGlassRelease` to
`~/Library/Application Support/Curfew/break-glass.json`. The app and the daemon
both check for one every tick and stand their destructive paths down when they
find a valid one. Run under `sudo`, the command also kills a `/sbin/shutdown`
that is already counting down.

It does not unlock the display and it does not shorten the curfew. Standing the
consequences down is not the same as ending enforcement.

Four rules decide whether a record counts:

- Its HMAC-SHA256 signature must verify against the per-install key at
  `~/Library/Application Support/Curfew/.break-glass-secret` (mode 0600).
- It must not be dated in the future.
- It must have been issued after the current lockout window started — the
  daemon passes `lockoutStartedAt` from the deadline record, so last night's
  release cannot disarm tonight.
- Failing that, it ages out after 12 hours.

The signature is not a security boundary and is not meant to be. The key sits in
the user's own directory, and anyone who can read it can already run `sudo`.
What it buys is that a stray write, a stale file from a previous install, or a
buggy script cannot disable root-level enforcement by accident. Releasing has to
be something a person meant to do. The 20-character minimum reason and the
recorded `user@host` are the same idea: a commitment device whose escape hatch
costs nothing is not a commitment device.

### Runbook

Works over SSH, from a second Mac, or from a terminal the lockout overlay is
covering.

```bash
# The Mac is counting down to a forced shutdown. Stop it.
sudo curfew-ctl break-glass --reason "daemon fired during an agent run; investigating"

# No countdown yet, just stand the daemon down for tonight.
curfew-ctl break-glass --reason "debugging enforcement on this machine"

# See what would happen first.
curfew-ctl break-glass --reason "…" --dry-run

# Re-arm before the window ends.
curfew-ctl break-glass --revoke --reason "done"
```

Run it under `sudo` whenever a shutdown may already be in flight — only root can
signal the `shutdown` process. Without `sudo` the command says so plainly rather
than failing quietly, and the countdown keeps running.

The release is cleared automatically when the lockout window ends naturally, in
`clearDurableDeadlineIfNaturalUnlock()`.

## A bug this uncovered

The daemon runs as root, where `NSHomeDirectory()` answers `/var/root`. Every
path `SharedPaths` derived from it therefore pointed at a directory the app
never writes: the daemon saw no lockout deadline, no app heartbeat, and would
have seen no protected work either — the worst possible reading to be wrong
about, because "no protected work" means "go ahead and shut down".

`SharedPaths.userHomeDirectory` now resolves the console user's home (via the
owner of `/dev/console`) when the effective uid is 0, and returns the process
home unchanged for everyone else. Non-root behaviour is byte-identical.

**This is a behaviour change with teeth.** It is the first time the daemon can
actually find the files it polls, which means the first time its shutdown path
can fire at all. Review it before installing the daemon.

## What is not done

- The daemon is not installed and this branch does not install it. Nothing here
  has been exercised against a live root daemon; the gating is covered by unit
  tests against the shared types plus CLI smoke tests.
- `LockoutStatePersistence.markLockoutActive()` writes to
  `/Library/Application Support/Curfew/`, which is `root:wheel` 0755. The app
  runs as the user and cannot create files there, and the write failure is
  logged and swallowed. Since the daemon's `KeepAlive.PathState` watches that
  sentinel, the daemon may never start. Pre-existing, untouched here, and worth
  fixing before install day.
- Claims are not surfaced on the lockout screen or in the activity log. The
  shutdown status line mentions a hold; there is no list of what is holding.
- `ProtectedWorkPolicy` matches an application exactly and case-insensitively.
  There is no pattern matching, deliberately — a prefix rule on reverse-DNS
  identifiers would let `com.apple.Terminal` shield everything Apple ships.
