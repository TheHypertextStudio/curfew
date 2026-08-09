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

## The half claims do not cover

Every one of those surfaces requires the work to *announce itself*. That
covers cooperating callers and nothing else, and the two cases this whole
carve-out exists for are usually not cooperating:

- A `claude` or `codex` run started from a shell before curfew. It files
  nothing, because nobody wrapped it in `curfew-ctl work claim`.
- An engineer working on the Mac over SSH. There is no claim and no agent —
  just a person whose machine is about to power off underneath them.

The allowlist did not help either, and it is worth being precise about why.
`protectedProcessNames` is read in exactly one place:
`SystemShutdownController.requestGracefulTermination`, which filters
`NSWorkspace.runningApplications`. That list holds LaunchServices
applications; a bare CLI process is never in it. So `claude`, `ssh`, `tmux`,
and `screen` sat in the default policy matching nothing, and sparing an
application Curfew was never going to `terminate()` anyway is not a carve-out.
Meanwhile the daemon's `/sbin/shutdown` does not care what is on any
allowlist — it powers the machine off and takes everything with it.

**`LiveProtectedWorkMonitor`** (`Sources/CurfewKit/Domain/LiveProtectedWork.swift`)
closes that half. It reads the machine directly and feeds the answer into the
same `hasActiveProtectedWork` input both paths already share, so nothing new
decides anything:

- `SysctlProcessEnumerator` walks `sysctl(KERN_PROC_ALL)` and matches `p_comm`
  against `ProtectedWorkPolicy.deferringProcessNames`. `p_comm` rather than
  `KERN_PROCARGS2` because the latter will not hand a non-root caller another
  user's argv, and the app (user) and the daemon (root) must see one machine.
  The kernel truncates `p_comm` at 16 characters.
- `UtmpxLoginSessionEnumerator` reads `utmpx` — what `who` reads — and counts
  a session as remote when `ut_host` is non-empty. That, and not the presence
  of an `sshd` process, is the honest test: the `sshd` listener runs whenever
  Remote Login is enabled, so matching on it would hold enforcement off every
  night on any Mac that merely *accepts* SSH.

`ProtectedWorkStores.hasProtectedWork(now:policy:)` is the single place claims
and observations are OR-ed together, so root's answer and the user's answer
cannot drift.

### Why `deferringProcessNames` is a second, narrower list

The obvious move is to reuse `protectedProcessNames` and it is wrong. The two
lists answer different questions and one of them is much more expensive to be
generous with.

"Do not send this `terminate()`" costs nothing when over-applied: if the Mac
powers off anyway, sparing a terminal changed nothing. "Hold the shutdown
while this is alive" costs the full deferral window. `tmux`, `screen`, a
parked `ssh`, and every terminal emulator are alive on a working machine
essentially always — so reusing that list would spend thirty minutes of
enforcement every single night for most users, whether or not any work was
actually in flight. That is not a carve-out for delegated work; that is
enforcement quietly becoming thirty minutes weaker.

So `deferringProcessNames` names only commands that exist *because a job is
running* and exit when it finishes: `claude`, `codex`, `aider`, `goose`,
`gemini`. Emptying the list turns liveness-based deferral off entirely, and
`defersForRemoteSessions` does the same for SSH. Both are in Settings →
Enforcement → Protected Work.

Everything downstream is unchanged: the observation only sets the same boolean
a claim sets, so the 30-minute bound, the break-glass precedence, and the
marker invariants below all apply to it exactly as written.

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

### The marker invariant

A persisted window is dangerous in the other direction too, and the first cut
of this branch got it wrong. Two rules now govern the marker, both enforced in
`DaemonEnforcementDecision`:

1. **The marker mirrors the in-memory window after every tick, `nil`
   included.** A window is open only while a shutdown is *actually due* — that
   is, while the heartbeat is stale *and* protected work is live. The gate is
   fed `isShutdownDue && hasActiveProtectedWork`, so a recovered heartbeat
   closes the window as a consequence of the invariant rather than as a special
   case, and the caller writes that `nil` straight through.

   Without it: the app blips out (crash and relaunch, or sleep/wake) while an
   agent is working, a window opens, the app recovers, and the marker is left
   behind. Later in the *same* lockout the app goes stale again for real. The
   daemon reads the old start, sees a budget spent an hour ago, and fires
   `/sbin/shutdown -h +1` on the first tick with no grace at all — killing the
   live agent work this whole branch exists to protect.

2. **A marker that predates the current `lockoutStartedAt` is ignored**, as is
   one dated in the future. The marker is root-owned and outlives the daemon:
   `launchctl bootout`, a panic, or a power cut all leave it on disk. Tuesday's
   marker would otherwise hand Wednesday's first genuine incident a budget that
   expired a day ago. This is the same scoping rule break-glass records already
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

# Re-arm before the window ends. Both the app and the daemon re-read the
# record every tick, so this restores enforcement on both within one tick.
curfew-ctl break-glass --revoke --reason "done"
```

Run it under `sudo` whenever a shutdown may already be in flight — only root can
signal the `shutdown` process. Without `sudo` the command says so plainly rather
than failing quietly, and the countdown keeps running.

The release is cleared automatically when the lockout window ends naturally, in
`clearDurableDeadlineIfNaturalUnlock()`.

A release is a *hold*, never an ending. Both paths re-read it on every pass, so
revoking one re-arms both: the app's `ShutdownWorkflow` leaves
`.releasedByBreakGlass` and attempts the shutdown again, and the daemon resets
`shutdownIssued` and fires on its next stale-heartbeat tick. Revoking also hands
protected work a full grace window rather than a spent one, because standing
down clears the deferral window on the way in.

## One gate, both paths

`DestructiveActionGate` in `Sources/CurfewKit/Domain/DestructiveActionGate.swift`
owns the entire "may I destroy the user's work right now?" question —
break-glass, protected work, and the bounded window together. The app's
`ShutdownWorkflow.attemptOrHold` and the daemon's
`DaemonEnforcementDecision.evaluate` both call it and neither decides anything
on its own.

Sharing a *helper* was not enough. An earlier cut had both paths consulting
`ProtectedWorkDeferral` and they still drifted, because the app treated a
break-glass release as terminal for the rest of the window while the daemon
re-read it every tick: revoking re-armed the daemon and left the app stood down
for the night. The answers matched until the question changed, so the whole
question moved into one type.

`CurfewTests/App/Infrastructure/EnforcementParityTests.swift` runs the same
scenario through both paths tick by tick and asserts the verdicts are equal, so
the next divergence fails there rather than at 22:00 on someone's Mac.

## Cancelling a shutdown already in flight

`/sbin/shutdown -h +1` executes about a minute after it is issued, so
"the daemon decided not to shut down" and "the machine will not shut down" are
different statements for sixty seconds. A protected-work claim arriving on a
tick inside that minute has to *call the countdown off*, not merely be noted.

Which actions cancel is carried on the decision's outcome
(`cancelsPendingShutdown`) rather than inferred by the code that acts on it,
because inferring it is exactly where this went wrong — `.hold` decided to wait
and then only logged, and the machine powered off with the work anyway.

- `.hold` and `.standDown` cancel. Something is telling the daemon not to
  destroy the user's work, and a countdown already running would destroy it.
- `.exit` cancels. The lockout window is over, so powering the Mac off after a
  legitimate unlock is pure harm, and the bypass it buys is the seconds the
  countdown had left.
- `.wait` does **not**. Its main cause is the app heartbeat recovering, and
  cancelling there would price the bypass at nothing: kill Curfew, enjoy an
  unlocked screen, relaunch inside the minute, walk away without consequence.
  The daemon's whole deterrent is that going missing during lockout costs you
  the machine.

Cancelling also resets `shutdownIssued`, so the reprieve is genuinely a
reprieve: if the work never finishes, the bound expires and the daemon fires
again.

## Where the bugs were, and what changed about that

All three findings across three review rounds were in imperative shell code
that no test could reach, while the pure decision beside it was well covered.
The daemon now has two testable halves and no third place to hide:

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
