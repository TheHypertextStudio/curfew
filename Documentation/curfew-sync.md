# Curfew Sync

## Curfew Sync

**Description:** A cloud coordinator that lets a single user gate access across all of their devices, with a remote MCP endpoint authorized via OAuth 2.1 so external AI hosts (Claude Desktop, ChatGPT, Cursor, web-based assistants) can reach Curfew's tools without running locally on the user's Mac.

Curfew Sync is **complementary** to F13 (CloudKit Sync), not a replacement. F13 already handles same-Apple-ID multi-device replication via the iCloud private database — no accounts, no third-party servers, ships behind the Pro gate. Sync adds the things F13 structurally cannot do: a publicly reachable MCP endpoint for AI hosts that aren't on the user's Mac, cross-Apple-ID coordination (a household with mixed iCloud accounts on shared hardware), and the AI-mediated / reflection-style use cases from horizons 2 and 3 of the product thesis. Sync is also a **peer** to F9 (local MCP server): F9 stays the on-device stdio/loopback surface for tools that spawn `curfew-mcp` as a subprocess; Sync exposes a strict subset of those same tools over an authenticated public endpoint.

Sync is **not** a replacement for F13, **not** an admin / parent / manager product, and **not** MDM. There is no "control someone else's device" path; the account model is single-user by design.

### Goals and non-goals

**Goals:**

- Coordinate schedule, budgets, pending requests, and lockout state across all of a user's devices, including devices on different Apple IDs.
- Expose a remote MCP endpoint authorized via OAuth 2.1 so AI hosts that don't run locally can read status and queue extension / override / schedule requests.
- Preserve Curfew's offline-first behavior: every device must continue enforcing locally with the last synced schedule when the coordinator is unreachable.
- Compose cleanly with F13. A Pro user with two Macs on one Apple ID keeps using F13 between those Macs; enabling Sync additionally lets a remote AI host reach their tools.

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
  Coordinator (sync.curfew.app)  ◀────── Curfew app on Mac A
        │                                Curfew app on Mac B
        │  encrypted deltas              Curfew app on iPhone (future)
        ▼
  Per-device agent → local SchedulePolicyEngine → device lockout
```

**Invariant:** *The device evaluates lockout locally against its last synced schedule. The coordinator is a publisher, not a real-time authority.* A compromised or partitioned coordinator cannot directly lock or unlock a device — it can only publish a delta the device chooses to apply (subject to the anti-bypass asymmetry).

### Sync model

The coordinator holds:

- **Schedule** — the same weekly schedule shape F13 already syncs, but account-scoped instead of Apple-ID-scoped.
- **Budgets** — extension and override counters, weekly reset window.
- **Pending MCP requests** — extension / override / schedule-change requests queued by remote AI hosts, mirroring the local `MCPRequestQueue` shape used by F9.
- **Device registry** — one entry per enrolled device with last-seen timestamp, public key, and OS / app version. Heartbeats reuse the F14 / F15 cadence (60 s active, 120 s freshness threshold).

**Relation to F13's last-write-wins.** Where F13 uses `modifiedAt` for conflict resolution on iCloud-private records, Sync uses the same scheme on coordinator records, with one strict addition: deltas are classified before they apply on the device.

**Anti-bypass asymmetry (applied to sync):** schedule and budget deltas from the coordinator pass through the same `SchedulePolicyEngine` classification that already gates local edits.

- *Strengthening* deltas (earlier lock, fewer overrides, more day-on days) apply immediately on each device.
- *Weakening* deltas (later lock, more overrides, added day-off) wait out the existing 24h cooldown on the device they apply to. The cooldown is enforced locally, so a hostile coordinator cannot shorten it.
- *No-change* deltas no-op.

This means a compromised coordinator cannot push a "lock window shrinks to zero" update and have it take effect; it must wait 24h on each device, and during that window the user has time to notice and pull the local emergency release.

### Account and device enrollment

- **Authentication:** passkey-based. No passwords, no SMS 2FA. Account creation is a passkey ceremony; sign-in is passkey-only.
- **Initial enrollment:** the first device enrolls during account creation and becomes the seed device.
- **Adding a device:** a new device requesting enrollment must be approved from an *already-enrolled* device, not just from the account passkey. Approval surfaces in-app on the existing device with the new device's name, OS, and a short verification code shown side-by-side. This closes the credential-theft → enroll-attacker-device path.
- **Single-user only.** Accounts have exactly one human owner. There is no admin role, no "family" container, no shared-account flow. Cross-references the matching non-goal above.
- **Device removal.** Any device can remove itself locally without coordinator approval (mirrors uninstall). The coordinator can also be told from any enrolled device to remove another device; that operation requires the local passkey on the requesting device and a short cooldown before the removed device loses sync access.

### Remote MCP endpoint (OAuth 2.1)

This is the AI-control surface — the reason Sync exists beyond F13. Architectural sketch only; wire-level details are deferred to a future implementation doc.

- **Transport:** Streamable HTTP per MCP spec 2025-03-26, exposed at the coordinator's public endpoint (illustratively `https://sync.curfew.app/mcp`; the production URL is an implementation detail). This is the same transport shape F9 already supports on loopback via `StreamableHTTPTransport` — Sync extends it to a public, authenticated endpoint.
- **Authorization:** OAuth 2.1 with PKCE per the MCP spec. Authorization Code flow. Refresh tokens issued; access tokens short-lived. Tokens live on the AI host (the user's Claude Desktop config, browser keychain, etc.), never on Curfew's servers beyond what's needed to validate them on the way in. Dynamic client registration is supported where the host implements it; static registration is the fallback for hosts that don't.
- **Scope categories.** Granted per-scope, not all-or-nothing. Named at the level of *kinds*:
  - Read scopes — status, activity, budget.
  - Write scopes — `request_extension`, `request_override`, `set_schedule`. Each write scope is independently grantable.
  - Least-privilege defaults: the consent screen pre-selects read-only.
- **Tool surface (subset of F9).** All read tools (`curfew.status`, `curfew.schedule`, `curfew.budget`, `curfew.activity`, `curfew.get_time_remaining`, `curfew.get_weekly_summary`) plus the queue-and-poll write tools (`curfew.request_extension`, `curfew.request_override`, `curfew.set_schedule`, `curfew.request_status`). Per-tool consent decisions still happen on the user's device — see *Authorization and consent* below.
- **Revocation.** The Curfew app exposes a "Connected AI tools" panel listing every OAuth client with active tokens. Per-client revoke is one tap and takes effect on the next request the host makes; the coordinator's token cache is invalidated immediately.

Deferred to a future implementation doc: exact endpoint paths, authorization-server metadata, exact token-lifetime numbers, host-by-host dynamic-client-registration support matrix, and wire-level error semantics.

### Authorization and consent

OAuth grants *transport* permission. Per-tool consent is a separate, on-device decision.

- A remote MCP `tools/call` for a write tool enqueues a pending request via the coordinator, exactly like F9's local write tools enqueue through `MCPRequestQueue`. The coordinator does not approve writes itself.
- The approval prompt appears on whichever enrolled device the user is currently active on, picked using the same active-device heuristic F15 already uses (most recent input within 120 s). If no device is active, the request waits and surfaces a notification on every enrolled device.
- The user's existing AI consent policy (`AIConsentPolicy` — auto-approve / ask-each-time / always-deny) is consulted locally. The coordinator never overrides it.
- **Audit log.** Every server-driven device action — every remote MCP tool call that resulted in a state change, every consent prompt, every approval or denial — is visible in the in-app activity log with the OAuth client name, the originating device (if known), and a timestamp. Surprises are the failure mode here; the audit log is the antidote.

### Failure modes

- **Coordinator unreachable.** *Fail-open by default.* The device honors its last synced schedule and continues operating normally. Curfew was offline-first before Sync and stays offline-first after. The menu bar surfaces a *"Sync offline — last synced 14 min ago"* status; nothing else changes.
- **Opt-in fail-closed.** A setting — *"Lock harder if I haven't synced in 24 hours"* — lets users who specifically want the stricter posture opt in. Never the default. Even in fail-closed mode, the local emergency release (below) still works.
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

- **Settings → Curfew Sync** is the entry point. Off by default. Enrollment is the passkey ceremony described above.
- **Devices panel.** Lists all enrolled devices with last-seen time, active-state pill from F15, and a per-device "Remove" action.
- **Connected AI tools panel.** Lists every OAuth client (one row per token grant), with the granted scopes, last-used timestamp, and a "Revoke" button. New connections appear here within seconds of the OAuth flow completing.
- **Sync status indicator.** Replaces F13's status string when Sync is enabled: *"Synced across 2 devices · 1 AI tool connected"*. Offline state: *"Sync offline — last synced 14 min ago"*.
- **Remote-driven lockout surface.** When a remote MCP call triggers an extension or schedule change on the current device, the standard consent prompt appears with the originating client named inline: *"Claude (web) is requesting +15 minutes. Reason: 'shipping a release.' Approve?"*
- **Emergency release UI.** A dedicated screen with the cooldown clearly visible: *"This device will exit Curfew Sync in 23h 47m. The coordinator cannot stop or extend this."* The user can cancel during the cooldown; cancellation is also local.

### Security & Privacy

Curfew Sync is opt-in. When disabled, the offline-first defaults in `PRIVACY.md` apply unchanged.

When enabled, user content is **end-to-end encrypted with user-held keys**. The coordinator stores schedule, activity, and override-reason payloads as ciphertext; it cannot read them even under subpoena. Keys are derived from the account passkey and held on enrolled devices, never on the server.

What the coordinator *can* see (metadata, intentionally minimal): device count, sync timestamps, OAuth client identities, per-client tool-call counts for rate-limiting, and the device's IP address at request time (used only for transport-layer rate-limiting; not retained). What the coordinator *cannot* see: override reason text, schedule contents, activity event details, or the content of any tool argument that touches user data.

**Threat model summary:**

- *Account compromise* → mitigated by passkey auth, device-to-device approval for new enrollments, and the local emergency release that the coordinator cannot block.
- *Server compromise* → mitigated by E2E encryption; the server's worst-case disclosure is metadata.
- *Coercion* → mitigated by local emergency release and the single-user-only account model.
- *Operator subpoena* → mitigated by E2E encryption; Hypertext Studio cannot produce plaintext it does not have.
- *Hostile AI host* → mitigated by per-scope OAuth grants, per-tool on-device consent, per-client rate limits, and one-tap revoke.

**Single-user only.** Restated here because it's the single biggest stalkerware-prevention decision in the design. Any future "family" or "team" surface must be a separate product with its own design doc and its own threat model — not a flag on this one.

See `PRIVACY.md` for the offline-first defaults; this section describes only what changes when Sync is enabled.

### Open questions

- Coordinator hosting region and provider (data-residency implications for GDPR / CCPA).
- Free vs. Pro gating. F13 is gated as Pro today; Sync may be bundled with Pro, a separate paid layer, or free with a usage cap.
- iOS device-agent strategy. iOS sandboxing constrains the agent shape; full design is its own future doc.
- Retention defaults for coordinator-held ciphertext (rolling 90 days? per-record TTL? user-configurable?).
- Choice of OAuth library / framework for the coordinator implementation.
- Dynamic client registration support matrix across known AI hosts (Claude Desktop, web Claude, ChatGPT, Cursor) — needed to decide how heavy the static-registration fallback path has to be.
- Whether the emergency-release cooldown should be configurable above 24h (Ulysses-contract framing) or capped at the 24h default to keep the safety guarantee uniform.
