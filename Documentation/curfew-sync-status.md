# Curfew Sync device status

How an enrolled Mac reports the local facts that make a remote lock eligible,
and how those facts remain separate from the command that can strengthen its
lockout.

Companion to `curfew-sync.md`. The coordinator's storage and authorization
internals live in the `curfew-sync` repository.

## What status reporting does

An enrolled Curfew app periodically sends a privacy-minimal status publication
to its selected Curfew Sync environment. The publication lets the coordinator
show whether a Mac is online and gives a later remote command an exact local
eligibility snapshot.

Status is not itself a command. A status response cannot change a schedule or
arm a lockout. Remote locks travel through a separate signed-command path and
are accepted only when the privileged daemon verifies the enrolled account,
device, command signature, replay state, and the status snapshot described
below.

| Concern | Implementation |
|---|---|
| Environment selection | `Sources/CurfewKit/Sync/CurfewServiceEndpoints.swift` |
| Status construction | `Curfew/App/Model/CurfewAppModel+StatusReporting.swift` |
| OAuth and device-proof transport | `Curfew/Core/Features/NativeAccountSyncTransport.swift` |
| Wire mapping | `Curfew/Core/Features/NativeAccountSyncTransport+Mapping.swift` |
| Local command eligibility | `Sources/CurfewKit/Sync/DaemonRemoteCommandController.swift` |
| Root-owned command exchange | `Sources/CurfewKit/Storage/RemoteCommandInboxStore.swift` |

## Authentication and environment boundary

There is no pasted coordinator secret or user-configurable server URL. Browser
OAuth enrolls the Mac against one compile-time, closed-world endpoint set. The
app stores OAuth and account key material in Keychain and registers the Mac's
public signing and encryption keys with Curfew Sync.

Successful browser authorization is never rolled back into a sign-in failure.
Before Curfew submits device registration, it checkpoints the exact device,
OAuth binding, generated Recovery Key, and encrypted recovery envelope. An
ambiguous response or app relaunch retries that same registration idempotently
without reopening browser OAuth. After the coordinator returns a receipt,
Curfew adds it to the checkpoint before local finalization or recovery upload.
Recovery retries refresh an expired access token and remain single-flight.

Every status request carries a resource-bound OAuth access token plus an ES256
device proof. The proof binds the token, method, URL, body digest, coordinator
nonce, and one-time identifier to the enrolled device key. A key from one Mac
cannot authenticate another Mac, and revocation invalidates the device.

Production uses only:

- `https://curfew-account.hypertext.studio`
- `https://curfew.hypertext.studio/account`
- `https://curfew-sync.hypertext.studio`

The `CURFEW_STAGING` Debug flavor selects the three corresponding
`curfew-*-staging.hypertext.studio` hosts, an isolated Keychain service, the
development helper label, and separate user/root state paths. Release rejects
that flag. Runtime input cannot redirect the daemon to a different command
signer.

## Wire publication

The app sends the released `curfew-protocols` `DeviceStatusPublication` to
`POST /sync/status`. It contains identifiers and enforcement facts only:

- device identifier;
- monotonic status version and opaque cursor;
- observed time and IANA time zone;
- current enforcement phase;
- next transition and active lockout deadline when present;
- a one-way schedule digest.

It does not contain schedules, reflection text, callback secrets, application
names, window titles, URLs, camera images, or presence observations. Encrypted
account records use the separate E2EE sync routes.

`NativeAccountSyncTransportTests` checks the exact released payload mapping,
proof headers, nonce use, response bounds, refresh behavior, and transport
failure handling. `AccountStatusSyncTests` and lifecycle wiring tests cover the
local publication cadence and state transitions.

## Why commands bind to status

Each accepted local publication records its `statusVersion` and
`scheduleDigest` in root-owned state. A coordinator-signed lock command must
repeat both exact values. The daemon rejects a command when either value is
missing or stale.

That prevents a command created from an older view of the Mac from racing a
local schedule change. It also keeps policy authority on the device: the
coordinator can request a fixed strengthening lock, but it cannot invent a
different local schedule or bypass the daemon's current eligibility.

The status version is monotonic rather than clock-derived. Clock changes cannot
rewind it. A valid remote command still has its own short delivery expiry,
sequence, nonce, and idempotency key, so a captured publication does not create
an open-ended command window.

## Delivery and result path

The unprivileged app polls Curfew Sync, stages only opaque signed envelopes into
the root-owned exchange, and wakes the daemon. The daemon:

1. refreshes the bounded coordinator JWKS from the selected Curfew Sync host;
2. verifies the ES256 envelope and enrolled account/device;
3. compares the command's status version and schedule digest with local state;
4. applies the strongest eligible deadline through the shared daemon backend;
5. persists its result before acknowledging the command.

Local MCP and remote MCP use different inputs but converge on that injected
daemon backend. Neither transport owns enforcement policy. Transport failure
therefore cannot erase or shorten an existing durable lockout.

Results and signed coordinator receipts use a two-phase exchange. The app does
not fetch a newer command past an unreported terminal result, and the daemon
does not discard a result until it sees the exact authenticated acknowledgement.

## Failure behavior

- **No account or incomplete Recovery Key step:** no account transport starts;
  local Curfew continues normally.
- **Expired OAuth access token:** enrollment recovery and sync rotate the refresh
  token before exposing the paired access token, then retry once. Refresh failure
  leaves remote sync offline without changing the completed browser sign-in.
- **Coordinator unavailable:** the account transport reports the request as
  rejected or unavailable while local and already-durable daemon enforcement
  continue.
- **Stale status or schedule digest:** the daemon rejects the remote command;
  a newer publication is required.
- **Malformed, oversized, linked, or misowned exchange file:** the daemon
  rejects or quarantines it without treating later work as trusted.
- **Revoked device or changed remote authority:** Sync and MCP access fail
  closed on the next request.

## Current proof boundary

Repository tests cover the protocol mapping, OAuth/device proof, status
publication, command binding, signed-envelope verification, replay defense,
root-owned file handling, result acknowledgement, and shared daemon backend.
The staging Worker and account hosts are deployed.

Release acceptance still requires a real enrolled, signed Mac to publish a
status, receive a command from an OAuth-authorized remote MCP host, and visibly
enter lockout. Until that phone-to-Mac round trip is recorded, the code and
deployment are implementation evidence, not end-to-end product proof.
