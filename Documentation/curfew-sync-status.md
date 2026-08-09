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
| The signed credential | `Sources/CurfewKit/Sync/DeviceIdentityAssertion.swift` |
| Where the shared secret lives | `Curfew/Core/Features/DeviceAssertionSecretStore.swift` |
| Monotonic `statusVersion` | `Sources/CurfewKit/Sync/DeviceStatusVersionCounter.swift` |
| Settings, defaults, endpoint resolution | `Sources/CurfewKit/Settings/DeviceStatusReportingPolicy.swift` |
| Transport and ordering guarantees | `Curfew/Core/Features/DeviceStatusReporter.swift` |
| Wiring into the tick loop | `Curfew/App/Model/CurfewAppModel+StatusReporting.swift` |
| The Settings surface | `Curfew/UI/SettingsView+SyncPanel.swift` |

## The endpoint

`POST <base URL>/sync/status`, with the body below and
`Authorization: Bearer <credential>`.

That is the route curfew-sync implements: `src/routes/device-status.ts`,
mounted at `/sync` by `src/worker.ts`. It answers `204` when the publication
became the stored status, `400` if the body is not a valid publication, `403`
for a device the credential does not cover or one that has been revoked, `409`
when `statusVersion` is not strictly greater than the stored one, and `500` if
the write fails.

Not `sync/heartbeat`, which `curfew-sync/Documentation/ARCHITECTURE.md` §"API
surface" lists as a *planned* liveness ping for devices not holding a WebSocket
open. It is unimplemented, and its job is a strict subset of what a status
publication already does.

## The wire shape

The body is `curfew-protocols/schemas/sync.json` →
`#/definitions/DeviceStatusPublication`, in full and unextended:

```json
{
  "activeLockoutEndsAt": "2027-01-15T09:00:00Z",
  "cursor": "Bd5Xt1ZHm3mQI6-higG-aglSo9xTHTpy4Z4lr_Sd97g",
  "deviceId": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
  "nextTransitionAt": "2027-01-15T08:00:00Z",
  "observedAt": "2027-01-15T07:59:59Z",
  "phase": "locked",
  "scheduleDigest": "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU",
  "statusVersion": 7,
  "timeZone": "America/Los_Angeles",
  "type": "status"
}
```

`DeviceStatusPublication` because it is what the route parses:
`parseDeviceStatusPublication` enforces the definition's `required` list, its
patterns, and `additionalProperties: false`. `device.json` →
`#/definitions/DeviceStatusSnapshot` is the *response* shape — what
`GET /sync/status` hands a reader — and a body in that shape is answered
`400 {"error":"invalid_status_publication"}` for want of `type` and `cursor`.

`DeviceStatusReportPayloadTests` asserts the key set and every value pattern
against literals transcribed by hand from the schema, not against the encoder.

## The credential

Every request carries `Authorization: Bearer <compactJws>`, minted on the device
immediately before it is sent. Nothing is published without one.

The JWS is `sync.json#/definitions/CompactJWS`; its payload is
`#/definitions/InternalDeviceIdentityClaims`, all six keys and no others:

```json
{
  "audience": "curfew-user-coordinator",
  "deviceId": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
  "expiresAt": "2027-01-15T08:02:00Z",
  "issuedAt": "2027-01-15T08:00:00Z",
  "keyThumbprint": "J-XysTmp_T1ZipF5b6fSuK6W6Sqr7tSRAYQw82KMCys",
  "userId": "user_01HZTESTACCOUNT"
}
```

The header is `{"alg":"HS512"}` and the signature is HMAC-SHA-512 over
`base64url(header).base64url(payload)`, keyed with the coordinator's shared
`AUTH_SECRET`. All three segments are unpadded base64url. The algorithm is
pinned by the wire format twice over: `verifyDeviceIdentityAssertion` rejects any
header whose `alg` is not exactly `"HS512"`, and `CompactJWS`'s
`[A-Za-z0-9_-]{86}` last segment is the encoding of a 64-byte MAC, which SHA-256
cannot produce.

`audience` is a constant, not a setting — the schema declares it `const`.
`deviceId` is the same UUID the publication beside it carries, because the route
answers `403 device_mismatch` when they differ. `userId` is the account the user
enters in Settings.

**The validity window is 120 seconds**, matching the coordinator's own freshness
threshold and so the longest gap Curfew leaves between publishes: an assertion
outlives the 10-second request it was minted for and dies before the report that
would carry its replacement. The verifier adds 60 seconds of clock-skew
tolerance on each end, so the real acceptance window is 180 seconds.

`DeviceIdentityAssertionTests` pins the whole serialisation with a fixed vector:
a fixed secret and fixed claims produce one exact string, computed with a
separate HMAC-SHA-512 implementation. It also re-verifies a freshly minted
signature the way the coordinator does, and asserts that the same claims signed
with a different secret do not match.

### Where the keyThumbprint comes from

Curfew mints it, as unpadded base64url SHA-256 over
`"curfew.device-key-thumbprint.v1\n<deviceId>"`.

**Nothing validates it today.** `verifyDeviceIdentityAssertion` checks the
header's `alg`, the MAC, and the two instants, and never reads `keyThumbprint`.
The route stores it verbatim on the `device` row without comparing it against
any registered key, because there is no enrollment yet to have registered one.
The only live constraint is the schema's `^[A-Za-z0-9_-]{43}$`.

**Derived, not random**, because the field's eventual meaning is "the thumbprint
of this device's key" and its eventual behaviour is to stay put while that key
does. A fresh random value per request would satisfy the pattern while rewriting
the stored row on every heartbeat, and would turn the day enrollment starts
checking it into an intermittent 401 rather than a clean one. It reveals nothing
the assertion does not already carry in `deviceId` beside it. It is not a key
thumbprint: when enrollment lands and a device holds a real
`DevicePublicKeyJWK`, this becomes that key's RFC 7638 thumbprint and changes
once, at enrollment.

### Where the secret lives

In the **Keychain**, as one generic-password item
(`studio.hypertext.curfew.coordinator` / `device-assertion-secret`), and nowhere
else. Not in `UserDefaults`, not in the settings plist, not in a bundled file.

The rest of the coordinator configuration — address, cadence, account, device
identifier — is configuration and lives in the settings plist. This is not: it
is the credential that authenticates every report, and a plist is readable by
anything running as this user, copied into backups, and printed in full by
`defaults read`. A shared secret that leaks authenticates every device on the
account.

It is empty on a fresh install and must be entered by hand in Settings, which is
the same "off unless the user turned it on" discipline every privacy-sensitive
surface in Curfew follows. While it is empty, `publishDeviceStatus` returns
before the version counter advances and `DeviceStatusReporter` refuses any report
without a bearer credential, so an unconfigured Mac opens no socket at all.

### Where the cursor comes from

Curfew mints it, as unpadded base64url SHA-256 over
`"curfew.device-status.v1\n<deviceId>\n<statusVersion>"`.

**A device is allowed to.** `sync.json#/definitions/Cursor` is a bare string
pattern — `^[A-Za-z0-9_-]{22,128}$` — with no issuer, no signature, and no
registry. `POST /sync/status` checks only that pattern and stores the value
verbatim on the `device_status` row; it never compares it against anything it
handed out. The one place a coordinator does mint a cursor is the device socket,
where `DeviceSocketWelcome.cursor` is a stream position a client echoes back as
`DeviceSocketHello.resumeCursor`. There is no such stream on this HTTP path, so
the cursor is the publisher's own name for the frame.

**Derived, not random**, so a publication is idempotent by name: the same status
re-sent carries the same cursor, and a coordinator deduplicating by cursor sees
one frame rather than two. Because the version counter never reissues a version
and the reporter refuses to publish one twice, distinct publications from this
device always carry distinct cursors. Hashing hides nothing — `deviceId` and
`statusVersion` are both in the same body — it is a shape decision, because a
SHA-256 lands inside the 22–128 character window for every input.

## Cadence

`Documentation/curfew-sync.md` §"Sync model" documents the device registry's
heartbeat as the F14/F15 cadence: **60 s active, 120 s freshness threshold**.
Both numbers are in the code as bounds, not just as a default:
`heartbeatFloorSeconds` is 60, `heartbeatCeilingSeconds` is 120, and the setting
is clamped into that range on assignment and on decode.

The ceiling is the interesting one. A device publishing less often than the
coordinator waits before calling it stale reads as offline *between its own
heartbeats* — reporting something false, which is worse than not reporting. So
the settable range is exactly the range in which the documented contract holds,
and a 300 s cadence persisted by an earlier build is corrected to 120 s when it
decodes rather than honoured.

## Privacy

The ten keys above are the whole of what leaves the machine. There is no key
for a camera frame, a window title, an application name, a URL, a document, or
any user-authored text, and the encoder's type admits none: every value is a
string, an integer, or null. Two of the ten carry nothing new — `type` is the
constant `"status"`, and `cursor` is a digest of the other two identifying
fields.

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

Off by default with no endpoint and no credential. Settings → Integrations →
Coordinator holds the switch, the base URL, the account id, the shared signing
secret, and the heartbeat cadence (60–120 s, defaulting to 60 — see *Cadence*
above). Everything but the secret is written to the settings plist; the secret
goes to the Keychain, as above.

No coordinator address is compiled in anywhere — no default host, no staging
fallback, no "if empty, use ours". HTTPS is required and not configurable.

The device identifier is a random UUID minted on first enable, not the machine's
hardware UUID, so the value Curfew sends cannot be joined against any other
software's idea of this Mac.

## Known gaps

These are real and unfixed. They are recorded here rather than worked around,
because every workaround available locally would mean coining a wire shape, and
wire-crossing shapes come from curfew-protocols.

### 1. No live round-trip has been run

`POST /sync/status` **is implemented** on curfew-sync `main`
(`src/routes/device-status.ts`, mounted by `src/worker.ts`), and everything in
this document is verified against that route's source and against the schema it
parses with. What has not happened is a request from this app reaching a
deployed coordinator: the suite proves the shape against literals and a stubbed
transport, not against a running Worker.

What that leaves unproven is the parts no schema pins down — TLS and redirect
behaviour through a real deployment, the `409` path against a coordinator that
actually holds a newer version, and the credential (see gap 3).

### 2. The schema has no presence field

`DeviceStatusPublication` has no representation for `PresenceState`. A Curfew
device cannot tell a coordinator whether a person is at the machine, only what
phase enforcement is in.

Presence transitions therefore *trigger* a report — the coordinator gets a fresh
`observedAt` at a moment that just mattered, which is real liveness information —
but the verdict itself does not travel. Carrying it needs a field added to
`curfew-protocols/schemas/sync.json`, not one invented here.

### 3. The credential is a shared secret, not a device key

Curfew now mints its own assertion (see *The credential* above), so nothing has
to be pasted in out of band and the `deviceId` in the claims is the same UUID
the publication carries by construction rather than by the user getting it
right. What remains is what the scheme proves.

An HS512 MAC over a secret the coordinator and every enrolled device hold proves
the assertion was minted by *something holding that secret*. It does not prove
possession of this device's own key, and a secret compromised on one Mac
authenticates every Mac on the account. curfew-sync's own comment in
`src/auth/device-assertion.ts` says the same and names the successor: ES256 over
the enrolled `DevicePublicKeyJWK`, verified against the key stored at
enrollment, with the Better Auth session as the browser-side path. Enrollment
(`POST /sync/enroll/start`) does not exist on either side yet, which is why this
is the scheme. When it lands, `DeviceIdentityAssertion` keeps its claims and its
compact serialisation and changes only how the signature is computed — and
`keyThumbprint` starts naming a real key.

`keyThumbprint` is also unvalidated today; see *Where the keyThumbprint comes
from* for exactly what it is and is not.

### 4. A Mac set to a bare time zone will not report

The schema's `timeZone` pattern requires a region-qualified IANA identifier
(`America/Los_Angeles`). A Mac whose `TimeZone.current.identifier` is `UTC` or
`GMT` produces a report that fails `isWellFormed`, and Curfew stays quiet rather
than sending something the coordinator would reject. Rare, but it fails silently
apart from a log line.
