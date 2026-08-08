# Curfew audit log format

This is the complete on-disk specification for Curfew's audit log. It is
written for someone building a parser, a compliance report, or a log shipper
against files Curfew has already produced, with no access to Curfew's source.
Everything a parser needs — file locations, the record envelope, every event
type, every field, rotation behaviour, and the tamper-evidence scheme — is in
this document.

The audit log is **not** the activity store. `activity.sqlite3` is a queryable
rollup that powers the This Week retrospective and the CSV export; it holds a
dozen event kinds and is designed to be aggregated. The audit log is a
plain-text, append-only record of *what Curfew did, when, and why*, including
the events that never reach the UI: daemon shutdown decisions, deferred
schedule changes, consent verdicts, and permission loss during a live lockout.
The two files overlap in a few places and disagree in none.

## File locations

| Stream   | Path                                            | Owner       | Mode                |
|----------|-------------------------------------------------|-------------|---------------------|
| `app`    | `~/Library/Logs/Curfew/curfew-app.jsonl`        | the user    | `0600`, dir `0700`  |
| `daemon` | `/Library/Logs/Curfew/curfew-daemon.jsonl`      | `root`      | `0644`, dir `0755`  |

A development build writes the app stream to `~/Library/Logs/Curfew (Dev)/`
instead, mirroring the flavor split Curfew already applies to Application
Support, so a dev run never interleaves with the production install's history.
The daemon stream is not flavor-suffixed: there is one privileged daemon per
machine, and a dev build does not install one.

Rotated segments sit beside the active file as `curfew-app.1.jsonl` through
`curfew-app.4.jsonl` (`.1` is the most recently rotated).

### Why two files instead of one

The Curfew app runs as the user; `curfew-daemon` runs as root. Both need to
record during the same lockout, and that is precisely when the two most need to
be believable. One file per writer removes interleaving without inventing a
lock protocol across a privilege boundary that could not be tested on a
developer machine, and it is the only arrangement in which a per-file hash
chain means anything, since a chain assumes a single writer.

To read the whole picture, concatenate both files and sort by `ts`. Every
record carries a `stream` field, so a merged view still says who wrote each
line.

`curfew-ctl` and `curfew-mcp` do **not** write. Both submit requests to the
queue at `~/Library/Application Support/Curfew/mcp-requests.json`, and the app
is the process that decides what to do about them — so the app writes the
record, and the `actor` field names the origin. See [Actors](#actors).

## Format: JSON Lines

One JSON object per line, UTF-8, `\n`-terminated, no trailing comma, no
enclosing array.

JSON Lines was chosen over the alternatives for four reasons. Appending a
record is one `write(2)` at the end of the file, so no earlier byte is ever
rewritten and the append-only claim holds at the filesystem level. A truncated
final line from a crash costs exactly one record instead of corrupting the
file. `tail -f`, `grep '"event":"daemon\.'`, and `jq` all work with no tooling.
And each line is independently self-describing, carrying its own schema
version, which a CSV header or a binary framing could not do per record.

SQLite was rejected because the daemon writes as root and the app as the user:
two processes with different privileges sharing one database file is the exact
situation that produces a permissions knot and a locking bug. Plain syslog was
rejected because the records are structured and the retention would be out of
Curfew's hands.

### The envelope

Keys appear in a **fixed order**, which matters because the hash is computed
over the emitted bytes:

```
v, ts, seq, stream, actor, event, from, to, detail, prev, hash
```

| Field    | Type              | Always present | Meaning |
|----------|-------------------|----------------|---------|
| `v`      | integer           | yes | Schema version. Currently `1`. |
| `ts`     | string            | yes | ISO-8601 with milliseconds and an explicit numeric offset: `YYYY-MM-DDTHH:MM:SS.sss±HH:MM`. Never `Z` — UTC is written as `+00:00` so the shape is fixed. |
| `seq`    | integer           | yes | Per-stream counter starting at 1, never reset, continuing across restarts and rotations. A gap means records were lost. |
| `stream` | string            | yes | `app` or `daemon`. Identifies the writing process. |
| `actor`  | string            | yes | Origin of the action. See [Actors](#actors). |
| `event`  | string            | yes | Dotted event type. See [Event types](#event-types). |
| `from`   | string            | no  | Prior state. Present only on transitions. |
| `to`     | string            | no  | New state. Present only on transitions. |
| `detail` | object            | no  | Event-specific payload. Omitted when empty. Values are JSON scalars only — never nested objects or arrays. Keys are sorted ascending by Unicode scalar. |
| `prev`   | string            | yes | Lowercase hex SHA-256 of the previous record in this stream, or 64 zeros for the first record ever written. |
| `hash`   | string            | yes | Lowercase hex SHA-256 of this record. Always the last key. See [Tamper evidence](#tamper-evidence). |

A parser **must** ignore unknown `event` values and unknown `detail` keys.
Adding either is a non-breaking change and will not bump `v`. `v` increases
only when a top-level field is renamed or removed, or when the hash
construction changes.

Timestamps keep their local offset rather than normalising to UTC because a
curfew is a wall-clock promise. An auditor reading "lockout started at 22:00"
needs the hour the user actually experienced, and the offset is the only
on-disk evidence of a timezone change mid-window.

### Actors

`actor` says who caused the event; `stream` says who attested to it. They
differ whenever the app records something an external client asked for.

| Token          | Meaning |
|----------------|---------|
| `app`          | The Curfew app acted on its own: a tick-loop transition, a policy decision, an automatic grant. |
| `daemon`       | The privileged daemon acted. |
| `user`         | A person acting directly in Curfew's UI. |
| `cli`          | `curfew-ctl` originated the request. |
| `mcp`          | An MCP client originated the request, identity unknown. |
| `mcp:<client>` | An MCP client with a known identifier, e.g. `mcp:claude-desktop`. |
| `system`       | macOS originated the event: TCC permission change, idle detection, wake. |

Split on the first `:`; the head is always one of the seven classes above.
Client identifiers are sanitised to `[A-Za-z0-9._-]`, truncated to 64
characters, with anything else replaced by `_` — an MCP client cannot forge a
different actor class or inject a second line by naming itself.

`cli` does not appear today. `curfew-ctl`'s mutating subcommands enqueue onto
the same queue file `curfew-mcp` uses, and the envelope carries no client
field, so every queued request is currently attributed to `mcp`. When
`curfew-protocols` adds a client identifier to the envelope, these records will
start carrying `mcp:<client>` and `cli`.

## Example records

Real output, chain intact, from a machine in `America/Denver`:

```jsonl
{"v":1,"ts":"2025-11-24T09:00:00.000-07:00","seq":1,"stream":"app","actor":"app","event":"app.launched","detail":{"accessibility":"granted","autoShutdownEnabled":true,"build":"412","enforcementArmed":true,"flavor":"production","phase":"working","pid":4711,"scheduleDigest":"3f1c9a2d8e4b7c05","setupComplete":true,"version":"0.4.1"},"prev":"0000000000000000000000000000000000000000000000000000000000000000","hash":"ccee952319d41ce161315d134861d867a2bc9886fc8d05e48ad3dd31ecc0b0da"}
{"v":1,"ts":"2025-11-24T09:59:00.000-07:00","seq":2,"stream":"app","actor":"app","event":"enforcement.warning_stage_changed","from":"none","to":"T-30","detail":{"minutesRemaining":30,"phase":"warning"},"prev":"ccee952319d41ce161315d134861d867a2bc9886fc8d05e48ad3dd31ecc0b0da","hash":"180b7cd6dcb2ac1bc5fc4dc8229fae5916eb51de8f933c0caf8c48f54a6abf51"}
{"v":1,"ts":"2025-11-24T10:01:00.000-07:00","seq":3,"stream":"app","actor":"user","event":"extension.granted","detail":{"budgetLimit":3,"budgetRemaining":2,"minutes":15,"minutesGrantedToday":15,"warningStage":"T-30"},"prev":"180b7cd6dcb2ac1bc5fc4dc8229fae5916eb51de8f933c0caf8c48f54a6abf51","hash":"c059d10a34b352d095829e6e233d27769b348529878a3220a22e4ea92d47a490"}
```

An MCP request that the user refused, and an override the user talked their
way into:

```jsonl
{"v":1,"ts":"2025-11-24T10:31:45.000-07:00","seq":6,"stream":"app","actor":"mcp","event":"mcp.request_received","detail":{"argumentsDigest":"b41f7d09c2a6e358","argumentsLength":58,"policy":"queue","requestId":"6C7B0A2E-6C0E-4E31-9D1F-0B2A4E9C8F13","signatureValid":true,"signed":true,"tool":"curfew.set_schedule"},"prev":"...","hash":"..."}
{"v":1,"ts":"2025-11-24T10:31:57.000-07:00","seq":7,"stream":"app","actor":"user","event":"mcp.request_denied","detail":{"denialReason":"Not during lockout.","policy":"queue","requestId":"6C7B0A2E-6C0E-4E31-9D1F-0B2A4E9C8F13","tool":"curfew.set_schedule"},"prev":"...","hash":"..."}
{"v":1,"ts":"2025-11-24T10:35:17.000-07:00","seq":8,"stream":"app","actor":"user","event":"override.granted","detail":{"activeUntil":"2025-11-24T17:41:17.000-07:00","budgetLimit":2,"budgetRemaining":1,"minutes":20,"reasonDigest":"2ad0c6f4be195773","reasonLength":96},"prev":"...","hash":"..."}
```

## Event types

Fields listed under each event are what Curfew writes today. Treat them as a
floor, not a ceiling: a future release may add keys, and a parser must tolerate
that.

Every `detail` field named `*At` is an ISO-8601 timestamp in the same format as
`ts`. Every field named `*Digest` is 16 lowercase hex characters. Every field
named `*Length` is a character count.

### Audit stream meta

| Event | `from`/`to` | `detail` |
|-------|-------------|----------|
| `audit.stream_opened` | — | `path`, `schemaVersion`, `pid`, `uid`, `maxSegmentBytes`, `maxRotatedSegments`, `retentionDays`, `chainRecovered` (bool: whether the writer found and continued an existing chain) |
| `audit.rotated` | — | `rotatedTo` (file name the previous segment became), `maxSegmentBytes` |

`chainRecovered: false` on anything other than the very first record of a
stream's life means the previous segments were deleted or unreadable.

### App lifecycle — `stream: app`

| Event | `from`/`to` | `detail` |
|-------|-------------|----------|
| `app.launched` | — | `version`, `build`, `flavor`, `pid`, `enforcementArmed`, `setupComplete`, `accessibility` (`granted`/`denied`), `autoShutdownEnabled`, `scheduleDigest`, `phase` |
| `app.terminating` | — | `phase`, `enforcementRunning` |
| `app.accessibility_changed` | `granted` ⇄ `denied` | — |
| `app.enforcement_health_changed` | `active` / `degraded_no_accessibility` / `degraded_tap_down` | `phase` |
| `app.respawn_guard_changed` | `armed` / `disarmed` / `arm_failed` / `disarm_failed` | `phase`, `error` (present only on a failure) |

An `app.launched` with no preceding `app.terminating` is the signal that the
previous run was killed, crashed, or force-quit. That is the same condition the
privileged daemon acts on, so the two streams corroborate each other.

`app.enforcement_health_changed` moving to `degraded_no_accessibility` or
`degraded_tap_down` while `phase` is `locked` is the highest-value line in the
file: it says the keyboard shield was down during an enforced lockout.

### Enforcement — `stream: app`

| Event | `from`/`to` | `detail` |
|-------|-------------|----------|
| `enforcement.phase_changed` | `working` / `warning` / `locked` / `day_off` | `warningStage`, `minutesRemaining`, `trigger` (`time`/`hours`), `scheduleDigest`, `extensionMinutesToday`, `snoozeMinutesToday`, `todayDayOff`, `todayLock`, `todayUnlock`, `todayMode`, `todayHoursLimitMinutes` (when set), `lockAt`, `unlockAt` |
| `enforcement.warning_stage_changed` | `none` / `T-30` / `T-15` / `T-5` / `T-2` / `T-1` / `lockout` | `minutesRemaining`, `phase` |
| `lockout.started` | — | everything from `enforcement.phase_changed`, plus `durableDeadlineActive` |
| `lockout.ended` | — | everything from `enforcement.phase_changed`, plus `reason`: `schedule`, `override`, or `day_off` |

`lockout.started` and `lockout.ended` are redundant with the phase transition
on purpose. They are the two lines an auditor greps for first, and forcing that
reader to know that `locked` is a phase value would be a bad trade for two
saved lines a day.

`durableDeadlineActive: true` on `lockout.started` means the on-disk deadline
record (not the schedule) is holding the lockout — the anti-bypass path that
re-locks a Mac whose clock, schedule, or app process changed mid-window. Its
presence explains a `working → locked` step that no schedule boundary accounts
for.

### Schedule — `stream: app`

| Event | `from`/`to` | `detail` |
|-------|-------------|----------|
| `schedule.change_requested` | schedule digest before → after | `classification` (`weaker`/`stricter`/`no_change`), `changedDays` (comma-separated `mon`…`sun`), `effectiveAt` |
| `schedule.change_deferred` | — | `reason`, `fromDigest`, `toDigest`, `classification`, `requestedAt`, `effectiveAt` |
| `schedule.change_applied` | digest before → after | `classification`, `requestedAt`, `effectiveAt`, `delaySeconds` |
| `schedule.change_cancelled` | withdrawn digest → live digest | `classification`, `requestedAt`, `effectiveAt` |

Curfew's anti-bypass policy delays a weaker schedule by 24 hours and a stricter
one until the next midnight, and refuses to install a weaker one at all while
the user is locked out. These four events are that policy's paper trail: what
was asked for, how it was graded, when it was allowed to land, and whether it
was held back. `schedule.change_deferred` is written once per distinct
deferral, not once per tick.

A schedule is identified by `scheduleDigest`: 16 hex characters of SHA-256 over
a canonical rendering, Monday first,

```
mon=09:00-17:00/time;tue=off;wed=09:00-17:00/hours:480;…
```

where a day is `off`, or `HH:MM-HH:MM/<mode>` with `<mode>` one of `time`,
`hours`, `combined`, followed by `:<minutes>` when an hours budget is set and
`+exc` when the day carries an exception. Two records with the same digest
describe the same schedule; a digest is enough to prove a proposed change was
or was not the one that landed.

`no_change` submissions are not recorded — the schedule editor fires one on
every stepper nudge, and the log must not fill with lines describing nothing
happening. A `no_change` that withdraws a queued change is recorded, as
`schedule.change_cancelled`.

### Grants — `stream: app`

| Event | `detail` |
|-------|----------|
| `extension.requested` | reserved; not currently emitted |
| `extension.granted` | `minutes`, `budgetRemaining`, `budgetLimit`, `minutesGrantedToday`, `warningStage` |
| `extension.denied` | `reason` (`not_offered`, `budget_exhausted`), `budgetRemaining`, `phase` |
| `override.requested` | `reasonLength`, `reasonDigest`, `budgetRemaining` |
| `override.granted` | `minutes`, `budgetRemaining`, `budgetLimit`, `reasonLength`, `reasonDigest`, `activeUntil` |
| `override.denied` | `reason` (`not_locked`, `budget_exhausted`, `gate_failed`), `budgetRemaining`, `phase` |

`actor` is `user` for in-app grants and `mcp` / `mcp:<client>` for ones an
assistant asked for. The override justification itself is never written — see
[Privacy](#privacy).

### Presence — `stream: app`

| Event | `from`/`to` | `detail` |
|-------|-------------|----------|
| `presence.changed` | `active` ⇄ `idle` | `thresholdSeconds` |

`actor` is `system`. Presence decides whether auto-shutdown uses the
configured delay or the short two-minute idle grace, so it is load-bearing for
reading a `shutdown.scheduled` line.

### Auto-shutdown, app side — `stream: app`

| Event | `detail` |
|-------|----------|
| `shutdown.scheduled` | `fireAt`, `delayMinutes`, `activeDevice` |
| `shutdown.retry_scheduled` | `fireAt`, `delayMinutes`, `activeDevice` |
| `shutdown.executed` | `delayMinutes`, `activeDevice` |
| `shutdown.permission_denied` | `delayMinutes`, `activeDevice` |
| `shutdown.failed` | `delayMinutes`, `activeDevice` |
| `shutdown.deferred` | `fireAt` (the deferral bound), `delayMinutes`, `activeDevice` |
| `shutdown.released_by_break_glass` | `delayMinutes`, `activeDevice` |
| `shutdown.cancelled` | reserved; the workflow returning to idle is currently recorded only by the absence of a further transition |

This is the app's Apple Events path, which the user can decline. The daemon's
`/sbin/shutdown` path is separate and lives in the daemon stream.

`shutdown.deferred` and `shutdown.released_by_break_glass` are the app-side
mirror of the protected-work carve-out below. `fireAt` on a deferred record is
the bound the deferral runs to, not a promise the shutdown fires then — the
work finishing first closes the window earlier.

### MCP and CLI — `stream: app`

| Event | `actor` | `detail` |
|-------|---------|----------|
| `mcp.request_received` | the origin: `mcp`, `mcp:<client>`, or `cli` | `requestId`, `tool`, `signed`, `signatureValid`, `policy`, `argumentsLength`, `argumentsDigest` |
| `mcp.request_auto_approved` | always `app` | `requestId`, `tool`, `policy` |
| `mcp.request_queued` | always `app` | `requestId`, `tool`, `policy` |
| `mcp.request_approved` | always `user` | `requestId`, `tool`, `policy` |
| `mcp.request_denied` | `user` or `app` — see below | `requestId`, `tool`, `policy`, `denialReason` |

`tool` is the wire name: `curfew.request_extension`, `curfew.request_override`,
or `curfew.set_schedule`. `policy` is the consent setting in force:  `queue`,
`autoApprove`, or `deny`. `signatureValid: false` on an
`mcp.request_auto_approved` would be a bug — Curfew downgrades an unsigned or
forged request to the consent sheet even under auto-approve, and this pair of
fields is how you check that it did.

**The actor on a verdict is load-bearing, so read it precisely.** A person can
only ever produce two of these: `mcp.request_approved` and a
`mcp.request_denied` with `actor: "user"`. Both mean somebody saw the consent
sheet and clicked. Everything else was decided with no human in the loop:
`mcp.request_auto_approved` is the auto-approve policy, `mcp.request_queued` is
the app parking a request for a sheet nobody has answered yet, and a
`mcp.request_denied` with `actor: "app"` is either the deny-all policy or the
guard that refuses `curfew.request_override` outright. If you are auditing
whether a person consented to something, `actor` is the field that answers it —
not the event name.

Join a request to its verdict on `requestId`. Every request produces exactly
one `mcp.request_received` and exactly one of the four verdicts. An approval is
never written twice: a policy auto-approval emits `mcp.request_auto_approved`
alone, never that plus a `mcp.request_approved`.

### Protected-work carve-out

| Event | Stream | `detail` |
|-------|--------|----------|
| `protected_work.active` | `daemon` | — |
| `protected_work.cleared` | `daemon` | — |
| `break_glass.observed` | `daemon` | `releaseId`, `issuedAt` |

A protected-work claim is an agent telling Curfew that killing this machine
right now would destroy work in flight; a break-glass release is the privileged
way out of an enforced lockout. Both change what the daemon is willing to do,
so both are recorded before anything acts on them. `protected_work.active` is
the antecedent for any `daemon.shutdown_held` or `daemon.shutdown_cancelled`
with `reason: protected_work` that follows, and `break_glass.observed` carries
the release identifier that traces back to the `curfew-ctl` invocation that
issued it.

Only the daemon writes these today. The app reads the same two facts through
`protectedWorkContext()`, and its view of them surfaces as `shutdown.deferred`
and `shutdown.released_by_break_glass` instead.

### Daemon — `stream: daemon`

| Event | `detail` |
|-------|----------|
| `daemon.started` | `pid`, `uid`, `loopIntervalSeconds`, `heartbeatTimeoutSeconds` |
| `daemon.stopped` | `shutdownIssued` |
| `daemon.deadline_observed` | `lockoutStartedAt`, `scheduledUnlockAt`, `kind` (`scheduled_time` or `scheduled_hours`), `source` (`user` or `shadow`) |
| `daemon.deadline_elapsed` | `scheduledUnlockAt` |
| `daemon.heartbeat_stale` | `ageSeconds` (`-1` when the heartbeat file is absent entirely), `thresholdSeconds`, `heartbeatPresent` |
| `daemon.heartbeat_recovered` | same fields as above |
| `daemon.shutdown_issued` | — |
| `daemon.shutdown_failed` | `error` |
| `daemon.shutdown_cancelled` | `reason`: `protected_work`, `break_glass`, or `lockout_ended` |
| `daemon.shutdown_held` | `until` (the deferral bound), `shutdownWasInFlight` |
| `daemon.stand_down` | — |
| `daemon.deferral_opened` | `startedAt`, `openForSeconds` |
| `daemon.deferral_closed` | — |

These are the highest-stakes records Curfew writes: the daemon runs as root and
can power the machine off. The sequence that matters reads
`daemon.deadline_observed` → `daemon.heartbeat_stale` →
`daemon.shutdown_issued`, and it means the app process disappeared during an
enforced lockout and root shut the Mac down ninety seconds later.

**`daemon.shutdown_cancelled` is the counterpart, and it changes what that
sequence means.** `/sbin/shutdown -h +1` runs about a minute after it is
issued, so a `daemon.shutdown_issued` followed by a `daemon.shutdown_cancelled`
inside the next minute means the machine did *not* power off. Read the two
together or you will conclude the opposite of what happened. The `reason`
distinguishes the three ways it can occur: an agent claimed protected work, a
break-glass release was honored, or the lockout window simply ended.

`daemon.shutdown_failed` means `/sbin/shutdown` could not be launched at all.
It follows the `daemon.shutdown_issued` for the same tick, because the record
that the command was dispatched is written before the process starts. An
`issued` line with no `failed` after it means the process really started.

`source: shadow` on `daemon.deadline_observed` means the user-writable deadline
file was gone and the daemon fell back to its root-owned copy — someone deleted
the record mid-lockout.

Deduplication matters here more than anywhere else, because the loop runs every
fifteen seconds. `daemon.heartbeat_stale` / `daemon.heartbeat_recovered` are
written on a change only; `daemon.stand_down` on the transition only;
`daemon.shutdown_held` once per deferral window, keyed on its bound; and the
deferral pair once each per window. A quiet night produces a handful of lines,
not five thousand.

## Rotation and retention

Defaults, per stream:

| Setting | Default | Effect |
|---------|---------|--------|
| `maxSegmentBytes` | 5 MiB (5,242,880) | Rotate before an append would exceed this. |
| `maxRotatedSegments` | 4 | Keep four rotated files behind the active one. |
| `retentionDays` | 90 | Delete a rotated segment last modified longer ago than this. |

The ceiling is therefore **25 MiB per stream, 50 MiB total**. At the volume
Curfew writes — a few hundred records on a heavy day, roughly 300 bytes each —
a single 5 MiB segment holds well over a year, so the size cap is a
disk-safety backstop and `retentionDays` is what normally bounds history.

Rotation shifts `.3` → `.4`, `.2` → `.3`, `.1` → `.2`, moves the active file to
`.1`, deletes whatever was in `.4`, and reopens a fresh active file. It writes
an `audit.rotated` record as the first line of the new segment. Retention
pruning runs **at rotation time only** — Curfew never spins a background
sweeper for the audit log, so an installation that stops writing keeps its last
segments indefinitely.

The chain does **not** reset at a rotation: the first record of the new segment
carries the last record of the old one as its `prev`. A rotated segment that
was deleted therefore shows up as a chain break rather than a clean restart.

## Tamper evidence

Each record carries `hash`, and each record's `prev` is the previous record's
`hash`. The construction is defined over emitted bytes so a non-Swift verifier
can reproduce it exactly:

1. Serialize the record with the fixed key order above, ending at `prev`,
   omitting `from`/`to` when absent and `detail` when empty. Call these UTF-8
   bytes the **body**. It starts with `{` and ends with `}`.
2. `hash` is the lowercase hex SHA-256 of the body, **including** its final
   `}`.
3. The written line is the body with `,"hash":"<hash>"` spliced in before that
   final `}`, then `\n`.

To verify a line, delete the trailing `,"hash":"<64 hex>"` from before the
closing brace, SHA-256 what remains, and compare. `hash` is always the last key
on the line, so the deletion is unambiguous.

A complete verifier, which is what produced the example records above:

```python
import hashlib, json, re, sys

prev = "0" * 64
for number, line in enumerate(open(sys.argv[1]), 1):
    line = line.rstrip("\n")
    match = re.search(r',"hash":"([0-9a-f]{64})"\}$', line)
    if not match:
        print(f"line {number}: malformed or truncated")
        break
    body = line[: match.start()] + "}"
    if hashlib.sha256(body.encode()).hexdigest() != match.group(1):
        print(f"line {number}: hash mismatch — this record was edited")
    if json.loads(line)["prev"] != prev:
        print(f"line {number}: chain break — a record before this was removed")
    prev = match.group(1)
```

The first record of a stream carries 64 zeros as `prev`.

### What the chain does and does not prove

It detects **editing and deletion after the fact by something that does not
recompute the chain**: a hand edit, a `sed`, a truncation, a log shipper that
drops lines. Combined with the monotonic `seq`, it also detects reordering.

It does **not** make the app stream tamper-proof. That file is owned by the
user, the chain head lives inside it, and SHA-256 is unkeyed — anyone willing
to write thirty lines of Python can rewrite the file and recompute every hash.
Closing that would take a key the user cannot reach, which on macOS means the
Secure Enclave or a remote notary, and Curfew's whole promise is that nothing
leaves the machine. The honest scope is: the app stream is tamper-*evident*
against casual editing, and that is what it claims.

The **daemon stream is meaningfully stronger**. It is `root:wheel`, mode
`0644`, in `/Library/Logs/Curfew/`. Rewriting it requires escalating first, and
it is precisely the stream that records what root did — shutdown decisions,
stale-heartbeat detections, deadline observations. If you only trust one file
here, trust that one.

## Privacy

Curfew stores everything locally and the audit log does not change that. It is
also the file most likely to be copied into a support thread, so the bar for
what may appear in it is higher than for the SQLite stores.

**Never written:**

- Reflection content. Morning intents and evening retrospectives are the user's
  private prose; `ReflectionStore` is the only place they exist, and the audit
  log does not even record that a reflection happened.
- Override justifications. The composer requires 50+ characters of explanation
  before granting an override, and that text is frequently the most personal
  thing in the app.
- MCP tool arguments. The payload arrives from an external process and can
  contain arbitrary text.
- Calendar event titles.

**Written instead, for the two redacted cases:** a `*Length` character count
and a `*Digest`, 16 hex characters of unsalted SHA-256 over the text.

The override-reason decision was the close one, and the answer is *redact*. The
verbatim text is already persisted in `activity.sqlite3` for the user's own
retrospective, which the privacy policy already accounts for; copying it into a
second, plain-text, shareable file widens exposure without making the decision
any more auditable. Everything an auditor needs is still there — that a
justification was given, how long it was, when, which grant followed, and what
budget it consumed. The digest lets a reader correlate the audit line with the
row in `activity.sqlite3` when they have access to both.

No salt is used. Salting would require storing the salt somewhere, and the only
threat it closes is brute-forcing short strings — which these fields never
hold, since the composer enforces a 50-character minimum.

## Reading the log

```bash
# What happened this evening, both streams, in order.
cat ~/Library/Logs/Curfew/curfew-app.jsonl /Library/Logs/Curfew/curfew-daemon.jsonl \
  | jq -s 'sort_by(.ts) | .[] | select(.ts > "2025-11-24T17:00")'

# Every time the schedule was touched, and how the policy graded it.
jq -r 'select(.event | startswith("schedule."))
       | "\(.ts)  \(.event)  \(.detail.classification // "-")  \(.actor)"' \
  ~/Library/Logs/Curfew/curfew-app.jsonl

# Did enforcement ever silently degrade during a lockout?
jq 'select(.event == "app.enforcement_health_changed" and .detail.phase == "locked")' \
  ~/Library/Logs/Curfew/curfew-app.jsonl

# Everything root did.
jq -r '"\(.ts)  \(.event)  \(.detail | tostring)"' /Library/Logs/Curfew/curfew-daemon.jsonl
```

## Implementation

| Concern | File |
|---------|------|
| Record, event, and actor types | `Sources/CurfewKit/Storage/AuditEvent.swift` |
| Serialization, hash chain, redaction | `Sources/CurfewKit/Storage/AuditLineEncoder.swift` |
| Paths and rotation policy | `Sources/CurfewKit/Storage/AuditLogPaths.swift` |
| Append, rotation, chain recovery | `Sources/CurfewKit/Storage/AuditLogWriter.swift` |
| Process-wide facade, transition dedup | `Sources/CurfewKit/Storage/AuditLog.swift` |
| Domain-to-token mapping, schedule digest | `Sources/CurfewKit/Storage/AuditTokens.swift` |
| App-side emitters | `Curfew/App/Model/CurfewAppModel+Audit.swift`, `+AuditGrants.swift`, `+AuditLifecycle.swift` |
| MCP consent resolution and its attribution | `Curfew/App/Model/CurfewAppModel+MCPConsent.swift` |
| Daemon actions (what was done) | `Sources/CurfewKit/Domain/DaemonEnforcementRuntime.swift` |
| Daemon observations (what was read) | `Sources/curfew-daemon/main.swift` |

## Known gaps

- **The CLI is not distinguished from MCP clients.** Both use the same queue
  file and the envelope has no client field, so every queued request records
  `actor: "mcp"`. Fixing this needs a `client` field in `MCPPendingRequest`,
  which is a `curfew-protocols` change and therefore a three-repo ceremony.
- **`shutdown.cancelled` and `extension.requested` are defined but not
  emitted.** They are in the enum so adding them later does not look like a
  schema change.
- **The app does not record protected-work claims or break-glass releases.**
  Only the daemon does, so a claim filed while the app is alive and the daemon
  is not leaves no line. The app's view surfaces indirectly, as
  `shutdown.deferred`.
- **Nothing verifies the chain at runtime.** Verification is an offline
  activity using the script above. Curfew does not warn the user when its own
  log has been edited, because a warning it cannot act on is noise.
- **A record dropped by a failed `write(2)` leaves a `seq` gap with no
  explanation.** The failure is recorded to `os.Logger` under subsystem
  `studio.hypertext.curfew`, category `audit-log`, and is visible in
  Console.app — but not in the audit file itself, which by then is the thing
  that is not working.
