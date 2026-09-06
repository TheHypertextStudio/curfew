# Curfew Sync

## Curfew Sync

**Description:** A cloud coordinator that lets a single user gate access across all of their devices, with a remote MCP endpoint authorized via OAuth 2.1 so external AI hosts (Claude Desktop, ChatGPT, Cursor, web-based assistants) can reach Curfew's tools without running locally on the user's Mac.

Curfew Sync is optional. An account-free device keeps its local schedule, signed
offline license, alarm callbacks, and fixed morning release. Once a device
enrolls in a Curfew Account, Curfew Sync becomes the only cross-device writer
and the app disables competing CloudKit writes. The local MCP server remains
available for tools that run on the Mac. The remote MCP endpoint exposes only
the account metadata and bounded control tools defined by
`curfew-protocols`.

Sync is not an admin, parent, manager, or MDM product. One person owns an
account and every enrolled device. Curfew does not provide a path for one
account to control another person's device.

### Goals and non-goals

**Goals:**

- Coordinate schedule, budgets, pending requests, and lockout state across all of a user's devices, including devices on different Apple IDs.
- Expose a remote MCP endpoint authorized via OAuth 2.1 so AI hosts that don't run locally can read status and queue extension / override / schedule requests.
- Preserve Curfew's offline-first behavior: every device must continue enforcing locally with the last synced schedule when the coordinator is unreachable.
- Make account sync canonical when enabled so CloudKit and Curfew Sync never
  race to write the same setting.

**Non-goals (explicit, because the abuse surface is real):**

- No admin, parent, or manager role. The account model is single-user. Anything that lets account A control device B for a different person is out of scope and not a future feature of this design.
- No second-party enforcement. Sync does not let a third party (employer, partner, clinician) install enforcement on someone else's device.
- No MDM-style hardening. Sync does not resist uninstall, profile removal, or local "release me" actions. *Uninstall is a user right, not a bypass* — the same principle applies to exiting Sync.
- No anti-bypass features beyond the existing 24h cooldown on weakening schedule changes that `SchedulePolicyEngine` already enforces locally.

### Architecture

Three components:

- **Coordinator service.** HTTPS API hosted by Hypertext Studio. Holds the user's account, device registry, encrypted schedule / budget / activity blobs, and pending MCP write requests. Publishes deltas to enrolled devices via long-poll or push.
- **Per-device agent.** Lives inside the existing Curfew app (no new process). Subscribes to coordinator deltas, applies them locally subject to the anti-bypass asymmetry, and posts local state changes upstream. Retains *all* enforcement authority — see invariant below.
- **Remote MCP endpoint.** Exposed by the coordinator at a public URL. AI hosts authenticate via OAuth 2.1, then call MCP tools that read or queue writes through the coordinator. Reads return current state; writes land in the same pending-request queue the device already processes for F9.

**Topology:**

```
  AI host (Claude Desktop, web, etc.)
        │  OAuth 2.1 + PKCE
        ▼
  Coordinator (curfew-sync.hypertext.studio)  ◀────── Curfew app on Mac A
        │                                Curfew app on Mac B
        │  encrypted deltas              Curfew app on iPhone (future)
        ▼
  Per-device agent → local policy and wake deadline → device lockout
```

**Invariant:** Every device evaluates policy locally. An account wake campaign
can release the morning gate after a signed terminal wake status or an
authorized time-bounded override. Every selected device can compute the same
final deadline, so a partitioned Mac releases at that deadline instead of
remaining locked forever.

### Sync model

The coordinator holds:

- **Schedule** — the same weekly schedule shape F13 already syncs, but account-scoped instead of Apple-ID-scoped.
- **Budgets** — extension and override counters, weekly reset window.
- **Remote unlock requests** — reason-bearing requests with explicit device
  targets, 5–60 minute bounds, approval state, and audit history.
- **Device registry** — one entry per enrolled device with public signing and
  encryption keys, key epoch, revocation state, and privacy-minimal wake status.

Encrypted records use optimistic versions and per-device writer counters. A
stale writer receives a conflict and rebases after decrypting the current
record. The coordinator never merges ciphertext.

**Anti-bypass asymmetry (applied to sync):** schedule and budget deltas from the coordinator pass through the same `SchedulePolicyEngine` classification that already gates local edits.

- *Strengthening* deltas (earlier lock, fewer overrides, more day-on days) apply immediately on each device.
- *Weakening* deltas (later lock, more overrides, added day-off) wait out the existing 24h cooldown on the device they apply to. The cooldown is enforced locally, so a hostile coordinator cannot shorten it.
- *No-change* deltas no-op.

This means a compromised coordinator cannot push a "lock window shrinks to zero" update and have it take effect; it must wait 24h on each device, and during that window the user has time to notice and pull the local emergency release.

### Account and device enrollment

- **Authentication:** User-verified passkeys are the default account creation
  and sign-in method. Sign in with Apple appears only when its isolated Curfew
  provider credentials are configured. An Apple callback establishes AAL1 and
  remains restricted until the user completes TOTP or consumes a one-time
  backup code. Every account must confirm server-side recovery codes before it
  can grant remote-control scopes. Curfew has no password accounts.
- **Linking:** Curfew disables implicit same-email linking. The user must sign
  in through an existing method, complete fresh 2FA, and approve the new
  provider. Settings prevents removal of the last sign-in method.
- **Encryption:** The first device creates a random 256-bit account root key
  and a separate random 256-bit Curfew Recovery Key. HKDF-SHA256 and
  AES-256-GCM protect the recovery envelope. HPKE envelopes distribute the
  root key to enrolled device encryption keys.
- **Recovery:** Better Auth backup codes recover sign-in only. Decrypting
  account content after all enrolled keys are lost requires fresh AAL2 and the
  Curfew Recovery Key.
- **Native proof:** Device enrollment and every device, sync, and wake request
  bind the resource-scoped OAuth token, method, URL, body digest, server nonce,
  and one-time JTI to the enrolled ES256 signing key.
- **Privacy:** Enrollment carries device identifiers and public keys. Device
  names, platform, and presentation metadata remain inside encrypted account
  settings.

### Remote MCP endpoint (OAuth 2.1)

This is the AI-control surface — the reason Sync exists beyond F13. Its wire
authority is the exact `@thehypertextstudio/curfew-protocols@0.0.9` release.

- **Transport:** Streamable HTTP and discovery per MCP `2026-07-28`, exposed at
  `https://curfew-sync.hypertext.studio/mcp` with an MCP App resource for status
  and strengthening-only controls.
- **Authorization:** OAuth 2.1 Authorization Code with mandatory PKCE through
  Better Auth's `oauthProvider()`. The deprecated Better Auth `mcp()` plugin is
  not used. Access tokens are short-lived and resource-bound; refresh tokens
  rotate. CIMD accepts standards-compliant public HTTPS client metadata, including
  third-party AI hosts, through a no-redirect, bounded, SSRF-constrained fetch.
- **Scope categories.** Granted per-scope, not all-or-nothing. Read scopes cover
  devices, entitlements, wake state, and unlock-request state. The distinct
  `curfew:lock:device` scope authorizes exactly one opted-in device per tool call;
  only `curfew:lock:all` authorizes coordinator-side fan-out across every opted-in
  device. Neither scope authorizes an unlock or weaker schedule.
- **Tool surface.** The generated registry contains exactly `list_devices`,
  `list_entitlements`, `get_wake_status`, `request_remote_unlock`,
  `get_remote_unlock_request`, `cancel_remote_unlock`, `curfew.lock.device`, and
  `curfew.lock.all`. The two lock tools advertise destructive/idempotent hints,
  while the MCP App itself requires a visible five-minute confirmation, awaits
  the result, and announces queued or failed outcomes.
- **Revocation.** The Curfew app exposes a "Connected AI tools" panel listing every OAuth client with active tokens. Per-client revoke is one tap and takes effect on the next request the host makes; the coordinator's token cache is invalidated immediately.

Access tokens last 15 minutes. Rotating refresh tokens last 30 days. Tokens are
resource-bound, use PKCE, and remain subject to consent and live revocation.

### Authorization and consent

OAuth grants transport authority. Operations that could loosen Curfew remain a
separate, on-device decision. A fixed remote lock is different: the explicit lock
scope plus the MCP App confirmation authorizes a strengthening-only command so it
can work while the user is away from the Mac.

- A remote unlock `tools/call` enqueues a pending request via the coordinator,
  exactly like F9's local write tools enqueue through `MCPRequestQueue`. The
  coordinator does not approve that request itself.
- A remote lock is signed for one device at a time, or deterministically fanned
  out under the all-device scope. The daemon accepts it only for its enrolled
  account/device and only when the signed status version and schedule digest
  equal the Mac's last locally recorded status publication.
- The app stages opaque signed envelopes. The root daemon performs verification,
  replay protection, eligibility comparison, and atomic deadline/result commit.
  Cross-privilege inbox and result files live under root-owned Application Support
  and are accessed with no-follow, directory-relative filesystem operations.
- The approval prompt appears on whichever enrolled device the user is currently active on, picked using the same active-device heuristic F15 already uses (most recent input within 120 s). If no device is active, the request waits and surfaces a notification on every enrolled device.
- The user's existing AI consent policy (`AIConsentPolicy` — auto-approve / ask-each-time / always-deny) is consulted locally. The coordinator never overrides it.
- **Audit log.** Every server-driven device action — every remote MCP tool call that resulted in a state change, every consent prompt, every approval or denial — is visible in the in-app activity log with the OAuth client name, the originating device (if known), and a timestamp. Surprises are the failure mode here; the audit log is the antidote.

### Failure modes

- **Coordinator unreachable.** The device honors its last decrypted policy.
  During a wake campaign, it keeps the morning gate until a valid terminal
  update arrives or the deterministic campaign deadline passes.
- **Network partition.** Same as coordinator unreachable. Deltas queued upstream from the partitioned device are sent on reconnect; deltas the device missed are applied in `modifiedAt` order on reconnect, subject to the anti-bypass asymmetry.
- **Clock skew.** All timestamps are coordinator-issued for cross-device ordering. Device-local enforcement (warning escalations, lock windows) continues to use device-local time so clock-skew doesn't open or close lock windows incorrectly.
- **Rate limits.** The coordinator rate-limits per-account and per-OAuth-client (a misbehaving AI host shouldn't be able to drain a week's override budget in 50 ms). Limits are communicated via standard `Retry-After`; hosts back off.

### Local emergency release

Every device retains a local *"Release me from Sync"* action that the coordinator cannot block. This is the single most important safety mitigation in this design. It is a direct application of an established principle in this codebase: *uninstall is a user right, not a bypass.* The same logic applies to exiting an account. The mechanism:

- The action is reachable in Settings → Curfew Sync without coordinator participation.
- Invoking it kicks off a local cooldown (24h default; 72h is the longest the user can opt into). The cooldown is enforced device-locally; the coordinator can refuse to *strengthen* during the cooldown but cannot extend it, shorten it, or block release at the end.
- When the cooldown elapses, the device removes its account binding locally, falls back to the standalone schedule it had before enrollment, and the next coordinator delta is rejected.

This protects against two distinct threats: account compromise leading to indefinite remote lockout, and real-world coercion (a user must always be able to walk away from their account on their own device).

### UX notes

- **Settings → Curfew Account** is the entry point. It opens browser OAuth,
  completes 2FA, enrolls device keys, and requires the user to save or enter
  the separate Curfew Recovery Key before sync starts.
- **Staging proof.** A build made with
  `CURFEW_SERVICE_SWIFT_FLAG=CURFEW_STAGING` binds the app, OAuth exchanges,
  sync transport, account portal, MCP resource, and embedded daemon JWKS trust
  to the three `curfew-*-staging.hypertext.studio` hosts and selects an isolated
  account-encryption Keychain service. It is restricted to Curfew's Debug
  identity, separate development LaunchDaemon label, and separate user/root
  storage paths. Release rejects the staging flag. Production remains the
  compile-time default; runtime environment variables cannot redirect a shipped
  helper to an arbitrary command signer.
- **Devices panel.** Lists all enrolled devices with last-seen time, active-state pill from F15, and a per-device "Remove" action.
- **Connected AI tools panel.** Lists every OAuth client (one row per token grant), with the granted scopes, last-used timestamp, and a "Revoke" button. New connections appear here within seconds of the OAuth flow completing.
- **Sync status indicator.** Replaces F13's status string when Sync is enabled: *"Synced across 2 devices · 1 AI tool connected"*. Offline state: *"Sync offline — last synced 14 min ago"*.
- **Remote-driven lockout surface.** When a remote MCP call triggers an extension or schedule change on the current device, the standard consent prompt appears with the originating client named inline: *"Claude (web) is requesting +15 minutes. Reason: 'shipping a release.' Approve?"*
- **Emergency release UI.** A dedicated screen with the cooldown clearly visible: *"This device will exit Curfew Sync in 23h 47m. The coordinator cannot stop or extend this."* The user can cancel during the cooldown; cancellation is also local.

### Security & Privacy

Curfew Sync is opt-in. When disabled, the offline-first defaults in `PRIVACY.md` apply unchanged.

When enabled, user content is end-to-end encrypted with user-held keys. The
coordinator stores schedule, callback, campaign, and account-setting payloads
as ciphertext. A random account root key protects namespace keys. Authentication
credentials never derive this root key.

The coordinator can see identities, entitlements, public device keys and
revocation state, ciphertext headers and timing, routing handles, OAuth and MCP
grants, and remote-unlock audits. The application does not retain request IP
addresses. The coordinator cannot see schedules, callback secrets, campaign
content, or account-wide settings.

**Threat model summary:**

- *Account compromise* → mitigated by mandatory AAL2, separate E2EE recovery,
  per-device keys, revocation, and local deadline enforcement.
- *Server compromise* → mitigated by E2E encryption; the server's worst-case disclosure is metadata.
- *Coercion* → mitigated by local emergency release and the single-user-only account model.
- *Operator subpoena* → mitigated by E2E encryption; Hypertext Studio cannot produce plaintext it does not have.
- *Hostile AI host* → mitigated by per-scope OAuth grants, per-tool on-device consent, per-client rate limits, and one-tap revoke.

**Single-user only.** Restated here because it's the single biggest stalkerware-prevention decision in the design. Any future "family" or "team" surface must be a separate product with its own design doc and its own threat model — not a flag on this one.

See `PRIVACY.md` for the offline-first defaults; this section describes only what changes when Sync is enabled.

### Remaining release gates

- Complete live Apple and Google operator flows against the isolated Curfew
  Better Auth deployment.
- Prove token refresh and revocation, new-device recovery, epoch rotation, and
  account deletion against staging.
- Prove the seven cross-platform wake and remote-unlock scenarios before a
  production rollout.
