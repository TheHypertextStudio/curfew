# Protected work and the break-glass release

Read this if you are about to install the privileged daemon, or if the daemon
has just shut your Mac down and you want it to stop. The break-glass runbook is
at the bottom; if that is why you are here, jump to it.

## The problem

Curfew's lockout combines a full-screen overlay with keyboard shortcut blocking. `OverlayCoordinator` puts a
borderless window on every `NSScreen` at `.screenSaver` level and
`LockoutKeyInterceptor` uses a `CGEvent` tap to block ⌘⇥ / ⌘Q / ⌘⌥Esc when Accessibility access is granted. Neither
touches a process, so a `claude` or `codex` run started before curfew keeps
running during lockout unless another action stops it.

Two paths do end processes.

1. `ShutdownWorkflow` → `SystemShutdownController.requestGracefulTermination()`
   sends `terminate()` to running applications except Curfew and configured
   protected applications, then requests shutdown through AppleScript. Closing
   Terminal, iTerm, or VS Code can stop processes launched inside them.
   Protected apps skip Curfew's termination step, but they still stop at shutdown.
2. `Sources/curfew-daemon/main.swift` polls every 15 s and, when the app
   heartbeat is more than 90 s stale during an active lockout, runs
   `/sbin/shutdown -h +1` as root.

Auto-shutdown is off by default. Enabling it or installing the daemon can
interrupt background work unless a claim or detected work delays shutdown.

## The model

The app, `curfew-ctl`, `curfew-mcp`, and the root daemon share three types in
`CurfewKit`.

**`ProtectedWorkPolicy`** (`Sources/CurfewKit/Settings/ProtectedWorkPolicy.swift`)
carries the allowlist and the deferral bound. It lives on `CurfewSettings`, so
it syncs and persists with everything else, and it is editable in Settings →
Protected Work. Defaults name common terminal emulators
(Terminal, iTerm2, Ghostty, kitty, Alacritty, WezTerm, Warp, Hyper) and common
agent CLIs (`claude`, `codex`, `aider`, `goose`, `gemini`, plus `ssh`, `mosh`,
`tmux`, `screen`). Those are defaults, not architecture: no enforcement code
knows any specific identifier.

**`ProtectedWorkClaim`** (`Sources/CurfewKit/Storage/ProtectedWorkStore.swift`)
has a label, a source, and an expiry. A caller renews the claim to keep it
active. If a caller stops renewing, the claim expires without a separate cleanup
operation. Claims live at
`~/Library/Application Support/Curfew/protected-work.json`, mode 0600, beside
`mcp-requests.json`. That location — rather than the App Group container where
`app-heartbeat` and `lockout-deadline.json` sit — avoids the macOS "access data
from other apps" prompt that a non-sandboxed app triggers when it touches its
own group container.

**`ProtectedWorkDeferral`** (`Sources/CurfewKit/Domain/ProtectedWorkGate.swift`)
calculates the deferral bound. The app and daemon use the same decision logic.

Three surfaces file claims. `curfew-ctl work claim --label … --minutes N`
prints a claim id for a shell wrapper to renew and release. The MCP tool
`curfew_declare_work` does the same for an agent, and `curfew_release_work`
releases it early. The app reads claims every tick.

## Work without a claim

Claims require a caller to file and renew them. These two cases may have no claim:

- A `claude` or `codex` run started from a shell before curfew. It files
  nothing because nobody wrapped it in `curfew-ctl work claim`.
- An engineer working on the Mac over SSH. There is no claim and no agent —
  a remote session that shutdown would interrupt.

The application allowlist does not detect these cases.
`protectedProcessNames` is read in exactly one place:
`SystemShutdownController.requestGracefulTermination`, which filters
`NSWorkspace.runningApplications`. That list holds LaunchServices
applications; a bare CLI process is never in it. So `claude`, `ssh`, `tmux`,
and `screen` do not match LaunchServices applications in that policy.
The daemon's `/sbin/shutdown` stops the Mac regardless of the application
allowlist.

**`LiveProtectedWorkMonitor`** (`Sources/CurfewKit/Domain/LiveProtectedWork.swift`)
detects processes and remote sessions. It supplies the same
`hasActiveProtectedWork` input that the app and daemon use for claims:

- `SysctlProcessEnumerator` walks `sysctl(KERN_PROC_ALL)` and matches `p_comm`
  against `ProtectedWorkPolicy.deferringProcessNames`. `p_comm` rather than
  `KERN_PROCARGS2` because the latter will not hand a non-root caller another
  user's argv, and the app (user) and the daemon (root) must see one machine.
  The kernel truncates `p_comm` at 16 characters.
- `UtmpxLoginSessionEnumerator` reads `utmpx` — what `who` reads — and counts
  a session as remote when `ut_host` is non-empty. An `sshd` process alone does not establish a remote session. The listener
  runs whenever Remote Login is enabled, so matching on it would delay shutdown
  during each lockout on any Mac that accepts SSH.

`ProtectedWorkStores.hasProtectedWork(now:policy:)` is the single place claims
and observations are OR-ed together, so root's answer and the user's answer
use the same combination rule.

### Why `deferringProcessNames` is a second, narrower list

`protectedProcessNames` skips application termination. `deferringProcessNames`
delays shutdown. Reusing the application list would delay shutdown even when a
terminal is open without a running job.

A terminal can remain open after its job finishes. `tmux`, `screen`, and `ssh`
can also remain running without active work. Including them in the shutdown
delay list would consume the full deferral window even when no job needs it.

`deferringProcessNames` defaults to agent command names: `claude`, `codex`,
`aider`, `goose`,
`gemini`. Emptying the list turns liveness-based deferral off entirely, and
`defersForRemoteSessions` does the same for SSH. Both are in Settings →
Protected Work.

Everything downstream is unchanged: the observation only sets the same boolean
a claim sets, so the 30-minute bound, the break-glass precedence, and the
marker invariants below all apply to it exactly as written.

## Why `curfew_declare_work` is not on the consent queue

`curfew_request_extension` and `curfew_set_schedule` can move the lock time.
They pass through `MCPRequestMonitor` and follow the user's consent policy.
`curfew_declare_work` does not use that queue. It
cannot unlock the display, cannot move the lock time, and cannot extend the
window. It delays application termination and shutdown within the configured
limit. Work can still be interrupted when that limit expires.

Queueing a claim would prevent approval while the app is unresponsive. The
daemon schedules shutdown when the app heartbeat becomes stale. During that
failure, the user may be unable to approve a consent sheet.

Three limits apply to claims:

- `ProtectedWorkPolicy.acceptsAgentClaims` lets the user refuse agent claims
  outright, and the tool returns a policy error rather than filing one.
- Every claim expires on its own within one lease (ceiling 30 minutes).
- The total postponement is bounded regardless of how many claims arrive or how
  often they renew.

## The bound: 30 minutes

`maximumDeferralMinutes` defaults to 30, is user-editable, and is clamped to
`1 ... 120` on construction *and* on decode, so neither the Settings UI nor a
hand-edited JSON file can widen it further.

The default permits at most 30 minutes of delay. It does not guarantee that a
job finishes before shutdown.

The bound is measured **from the moment the destructive action first came due**,
not from the most recent claim. Measuring from the latest claim would let an
agent that keeps renewing delay shutdown indefinitely, which is the failure the
type exists to prevent. Once the window is spent, the gate returns `proceed` no
matter how fresh the claim is, and a claim filed one second later cannot reopen
it.

The daemon persists the window's start to
`/Library/Application Support/Curfew/deferral-started`, root-owned. `launchd`
can restart the daemon, so an in-memory clock would make the bound
meaningless — restart the process, get a fresh 30 minutes.

### The marker invariant

A stale persisted window can cause shutdown before the current deferral limit.
Two rules govern the marker, both enforced in
`DaemonEnforcementDecision`:

1. **The marker mirrors the in-memory window after every tick, `nil`
   included.** A window is open only while a shutdown is *actually due* — that
   is, while the heartbeat is stale *and* protected work is live. The gate is
   fed `isShutdownDue && hasActiveProtectedWork`, so a recovered heartbeat
   closes the window as a consequence of the invariant rather than as a special
   case, and the caller writes that `nil` straight through.

   Without it: the app stops responding (crash and relaunch, or sleep/wake) while an
   agent is working, a window opens, the app recovers, and the marker is left
   behind. Later in the *same* lockout the app goes stale again for real. The
   daemon reads the old start, sees a deferral limit reached an hour ago, and fires
   `/sbin/shutdown -h +1` on the first tick with no grace at all — killing the
   live agent work this whole branch exists to protect.

2. **A marker that predates the current `lockoutStartedAt` is ignored**, as is
   one dated in the future. The marker is root-owned and outlives the daemon:
   `launchctl bootout`, a panic, or a power cut all leave it on disk. A previous lockout's
   marker would otherwise make the current incident use an expired deferral
   window. This is the same scoping rule break-glass records already
   follow.

The daemon's whole decision now lives in
`Sources/CurfewKit/Domain/DaemonEnforcementDecision.swift` as a pure function
returning `(action, deferralStartedAt)`. `main.swift` reads files, calls it,
does what it says, and writes the marker unconditionally. It was a bare
`while true` loop with no test seam before, which is exactly how rule 1 came to
be missing.

## Break-glass

### Why it has to exist

`/sbin/shutdown -h +1` was chosen for the daemon *because* user space cannot
cancel it. That prevents a normal user process from cancelling the countdown:
every ordinary recovery move — killing a wedged app, rebooting a crash loop,
debugging enforcement — becomes a forced power-off a minute later, and the only
app control for recovery is behind a locked display. The CLI release provides
recovery when the app cannot accept input.

The daemon must not be installed until this exists. It now does.

### What it is

`curfew-ctl break-glass --reason "…"` writes a signed `BreakGlassRelease` to
`~/Library/Application Support/Curfew/break-glass.json`. The app and the daemon
both check for one every tick and suspend application termination and shutdown
when they find a valid one. Run under `sudo`, the command also kills a `/sbin/shutdown`
that is already counting down.

The display stays locked and the scheduled unlock time remains unchanged.

Four rules decide whether a record counts:

- Its HMAC-SHA256 signature must verify against the per-install key at
  `~/Library/Application Support/Curfew/.break-glass-secret` (mode 0600).
- It must not be dated in the future.
- It must have been issued after the current lockout window started — the
  daemon passes `lockoutStartedAt` from the deadline record, so a release from
  an earlier lockout cannot suspend shutdown in the current lockout.
- Failing that, it ages out after 12 hours.

The signature is not a security boundary. The key sits in the user's own
directory, and anyone who can read it can sign a release record.
The signature prevents a stray write, a stale file from a previous install, or a
buggy script from disabling root-level shutdown without a valid record.
The command requires a 20-character reason and records `user@host` so the audit
log identifies who issued the release and why.

### Runbook

Works over SSH, from a second Mac, or from a terminal the lockout overlay is
covering.

```bash
# The Mac is counting down to a forced shutdown. Stop it.
sudo curfew-ctl break-glass --reason "daemon fired during an agent run; investigating"

# Suspend application termination and shutdown for the current lockout.
curfew-ctl break-glass --reason "debugging enforcement on this machine"

# See what would happen first.
curfew-ctl break-glass --reason "…" --dry-run

# Re-arm before the window ends. Both the app and the daemon re-read the
# record every tick, so this restores enforcement on both within one tick.
curfew-ctl break-glass --revoke --reason "done"
```

Run it under `sudo` whenever a shutdown may already be in flight — only root can
signal the `shutdown` process. Without `sudo` the command says so plainly rather
than failing quietly, and the countdown keeps running.

The release is cleared automatically when the lockout window ends naturally, in
`clearDurableDeadlineIfNaturalUnlock()`.

A release suspends application termination and shutdown while it remains valid.
Both paths re-read it on every pass, so
revoking one re-arms both: the app's `ShutdownWorkflow` leaves
`.releasedByBreakGlass` and attempts the shutdown again, and the daemon resets
`shutdownIssued` and fires on its next stale-heartbeat tick. Revoking also hands
protected work a new grace window because the release clears the deferral
window when it takes effect.

## One gate, both paths

`DestructiveActionGate` in `Sources/CurfewKit/Domain/DestructiveActionGate.swift`
decides whether application termination or shutdown may proceed —
break-glass, protected work, and the bounded window together. The app's
`ShutdownWorkflow.attemptOrHold` and the daemon's
`DaemonEnforcementDecision.evaluate` both call it and neither decides anything
on its own.

Sharing a *helper* was not enough. An earlier cut had both paths consulting
`ProtectedWorkDeferral` and they still drifted, because the app treated a
break-glass release as terminal for the rest of the window while the daemon
re-read it every tick: revoking re-armed the daemon and left the app stood down
for the lockout window. The answers matched until the question changed, so the whole
question moved into one type.

`CurfewTests/App/Infrastructure/EnforcementParityTests.swift` runs the same
scenario through both paths tick by tick and asserts the verdicts are equal, so
the next divergence fails there rather than at 22:00 on someone's Mac.

## Cancelling a shutdown already in flight

`/sbin/shutdown -h +1` executes about a minute after it is issued, so
"the daemon decided not to shut down" and "the machine will not shut down" are
different statements for sixty seconds. A protected-work claim arriving on a
tick inside that minute must cancel the countdown before it expires.

Which actions cancel is carried on the decision's outcome
(`cancelsPendingShutdown`) rather than inferred by the code that acts on it,
because inferring it is exactly where this went wrong — `.hold` decided to wait
and then only logged, and the machine powered off with the work anyway.

- `.hold` and `.standDown` cancel. A valid claim or release delays shutdown, so a pending countdown must stop.
- `.exit` cancels. The lockout window is over, so powering the Mac off after a
  scheduled unlock would contradict the resolved lockout state.
- `.wait` does **not**. Its main cause is the app heartbeat recovering, and
  cancelling there would allow this bypass: kill Curfew, enjoy an
  unlocked screen, relaunch inside the minute, walk away without consequence.
  The daemon retains a scheduled shutdown after a stale heartbeat even if the
  app starts responding again.

Cancelling also resets `shutdownIssued`. If the work never finishes, the bound
expires and the daemon schedules shutdown again.

## Where the bugs were, and what changed about that

All three findings across three review rounds were in imperative shell code
that no test could reach, while the pure decision beside it was well covered.
The daemon now separates the decision from the effects:

- `DaemonEnforcementDecision.evaluate` — what to do, as a pure function.
- `DaemonEnforcementRuntime.apply` — carrying it out, against a
  `DaemonEnforcementEffects` protocol that tests replace with a recorder.

`Sources/curfew-daemon/main.swift` reads files, calls those two, and logs. It
decides nothing and touches the machine only through `effects`.

The app half got the same treatment: `CurfewAppModel.protectedWorkContext()`
assembles the carve-out's three inputs in one named function, and
`ShutdownWorkflow.update` takes that context as a single value rather than
three loose booleans that could be transposed.
`CurfewTests/App/Model/ProtectedWorkWiringTests.swift` drives the model itself
rather than calling `update` with hand-supplied arguments.

## A bug this uncovered

The daemon runs as root, where `NSHomeDirectory()` answers `/var/root`. Every
path `SharedPaths` derived from it therefore pointed at a directory the app
never writes: the daemon saw no lockout deadline, no app heartbeat, and would
have seen no protected work either — the worst possible reading to be wrong
about, because "no protected work" means "go ahead and shut down".

`SharedPaths.userHomeDirectory` now resolves the console user's home (via the
owner of `/dev/console`) when the effective uid is 0, and returns the process
home unchanged for everyone else. Non-root behaviour is byte-identical.

**This enables the daemon's shutdown path.** The daemon can now find the files
it polls and schedule shutdown when their state requires it. Review this
behavior before installing the daemon.

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
  shutdown status line reports a delay; it does not list the work causing it.
- `ProtectedWorkPolicy` matches an application exactly and case-insensitively.
  There is no pattern matching, deliberately — a prefix rule on reverse-DNS
  identifiers would let `com.apple.Terminal` skip termination for every Apple
  application.
  `deferringProcessNames` follows the same rule for the same reason.
- No inbound SSH session has been exercised end to end. Creating one from a
  test needs Remote Login enabled on the host and credentials to log in with,
  and a test suite may not go and switch that on. What is covered:
  `UtmpxLoginSessionEnumerator` is run against the live `utmpx` database and
  asserted to return well-formed records, and the deferral both paths derive
  from a remote session is driven from a record of the shape macOS writes.
  The gap is the reader-to-record step on a machine someone is actually
  logged into. Worth ten minutes on install day.
- Liveness detection is on for the daemon unconditionally and opt-in for the
  app (`CurfewAppModel.enableLiveProtectedWorkDetection()`, skipped in the
  unit-test host). The default `ProtectedWorkStores.live` is
  `.disabled` so the suite's verdicts never depend on what happens to be
  running on the developer's machine — which, for this project, is reliably
  a `claude`.
