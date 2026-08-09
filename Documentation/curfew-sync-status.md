# Outbound device-status reporting

How Curfew tells a curfew-sync coordinator what this Mac is doing, what it
deliberately does not tell it, and which parts of the contract are still
unproven.

Companion to `curfew-sync.md` (the product-level view of the coordinator) and
`presence-detection.md` (what the camera does and does not produce).

## What it is

A best-effort, outbound-only status publisher. When the user has configured a
coordinator, Curfew POSTs a small JSON body describing this device's enforcement
phase — on every phase transition, on every presence transition, and on a
heartbeat in between.

It is telemetry. It is not a control channel: nothing a coordinator says can
change what this Mac does. Inbound remote commands are a separate, later piece
of work with its own schema (`curfew-protocols/schemas/remote-command.json`).

| Concern | Where |
|---|---|
| Payload shape and encoding | `Sources/CurfewKit/Sync/DeviceStatusReport.swift` |
| Monotonic `statusVersion` | `Sources/CurfewKit/Sync/DeviceStatusVersionCounter.swift` |
| Settings, defaults, endpoint resolution | `Sources/CurfewKit/Settings/DeviceStatusReportingPolicy.swift` |
| Transport and ordering guarantees | `Curfew/Core/Features/DeviceStatusReporter.swift` |
| Wiring into the tick loop | `Curfew/App/Model/CurfewAppModel+StatusReporting.swift` |
| The Settings surface | `Curfew/UI/SettingsView+SyncPanel.swift` |

## The wire shape

The body is `curfew-protocols/schemas/device.json` →
`#/definitions/DeviceStatusSnapshot`, in full and unextended:

```json
{
  "activeLockoutEndsAt": "2027-01-15T09:00:00Z",
  "deviceId": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
  "nextTransitionAt": "2027-01-15T08:00:00Z",
  "observedAt": "2027-01-15T07:59:59Z",
  "phase": "locked",
  "scheduleDigest": "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU",
  "statusVersion": 7,
  "timeZone": "America/Los_Angeles"
}
```

`DeviceStatusSnapshot` rather than `sync.json` →
`#/definitions/DeviceStatusPublication`, because the publication frame
additionally requires `type: "status"` and a `cursor`, and a cursor is a
coordinator-assigned stream position. A device has no way to mint one. The
publication is what a coordinator emits on the device socket; the snapshot is
what a device reports.

`DeviceStatusReportPayloadTests` asserts the key set and every value pattern
against literals transcribed by hand from the schema, not against the encoder.

## Privacy

The eight keys above are the whole of what leaves the machine. There is no key
for a camera frame, a window title, an application name, a URL, a document, or
any user-authored text, and the encoder's type admits none: every value is a
string, an integer, or null.

The schedule travels only as a one-way SHA-256 digest, so a coordinator can tell
whether two devices are running the same schedule without learning either.

This is the same rule the audit log follows — derived verdicts leave,
observations do not.

## Failure handling

Enforcement must work perfectly with the network down. Three structural
properties, not promises:

1. `DeviceStatusReporter.report(_:endpoint:bearerToken:)` is synchronous and
   non-throwing and awaits nothing. `tick()` cannot be suspended by it.
2. Every network outcome collapses to a log line. There is no path from a
   publish result back into the enforcement engine.
3. There is no retry. A failed report is dropped; the next transition or
   heartbeat carries fresher state anyway.

`DeviceStatusFailureIsolationTests` proves this differentially: the same lockout
scenario is run with reporting off and with reporting on against a broken
transport, and every enforcement-visible value is asserted equal — including
against a transport that accepts a publish and never returns.

## Staleness

The coordinator's guard is "reject any report whose `statusVersion` is not
greater than the stored one". Curfew holds up its end three ways:

- `statusVersion` is a persisted counter, not a clock, so a backwards clock step
  cannot rewind it.
- The reporter drops any report that does not advance
  `highestPublishedVersion`, so nothing goes out twice or backwards.
- Only one publish is in flight at a time; a report arriving mid-publish
  replaces any pending one rather than racing it.

## Configuration

Off by default with no endpoint. Settings → Integrations → Coordinator holds the
switch, the base URL, the device credential, and the heartbeat cadence.

No coordinator address is compiled in anywhere — no default host, no staging
fallback, no "if empty, use ours". HTTPS is required and not configurable.

The device identifier is a random UUID minted on first enable, not the machine's
hardware UUID, so the value Curfew sends cannot be joined against any other
software's idea of this Mac.

## Known gaps

These are real and unfixed. They are recorded here rather than worked around,
because every workaround available locally would mean coining a wire shape, and
wire-crossing shapes come from curfew-protocols.

### 1. No coordinator implements this endpoint

`curfew-sync/src/plugins/device-sync.ts` declares `endpoints: {}` and
`UserCoordinator.fetch` answers `501` to every non-WebSocket request. There is
no `POST /sync/status` and no `POST /sync/heartbeat` on the server today, so
**no live round-trip has been proved.** Everything here is verified against the
schema and a stubbed transport only.

The path Curfew posts to is `sync/heartbeat`, taken from
`curfew-sync/Documentation/ARCHITECTURE.md` §"API surface", which is the only
authority in the three repos that names a device status-report path. It is one
constant — `DeviceStatusReportingPolicy.statusPath` — if the route lands under
another name.

### 2. The schema has no presence field

`DeviceStatusSnapshot` has no representation for `PresenceState`. A Curfew
device cannot tell a coordinator whether a person is at the machine, only what
phase enforcement is in.

Presence transitions therefore *trigger* a report — the coordinator gets a fresh
`observedAt` at a moment that just mattered, which is real liveness information —
but the verdict itself does not travel. Carrying it needs a field added to
`curfew-protocols/schemas/device.json`, not one invented here.

### 3. Device authentication is a stand-in

curfew-sync's documented device-agent auth is a device session cookie issued by
`POST /sync/enroll/start`; the socket path uses a compact JWS identity
assertion. Neither enrollment nor the assertion exists on either side yet.

Curfew sends the user's configured credential as an HTTP bearer token — a
standard mechanism rather than a coined wire shape, and explicitly a stand-in
until the enrollment work lands.

### 4. A Mac set to a bare time zone will not report

The schema's `timeZone` pattern requires a region-qualified IANA identifier
(`America/Los_Angeles`). A Mac whose `TimeZone.current.identifier` is `UTC` or
`GMT` produces a report that fails `isWellFormed`, and Curfew stays quiet rather
than sending something the coordinator would reject. Rare, but it fails silently
apart from a log line.
