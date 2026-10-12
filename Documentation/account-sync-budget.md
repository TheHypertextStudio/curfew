# Account sync resource budget

The October 12 staging outage exhausted D1's daily row-write allowance with one
development Mac, not public traffic. A protected read was not read-only: proof
challenges, nonce consumption, replay protection and cleanup wrote indexed rows.
Four protected reads every 15 seconds created 23,040 protected reads per day,
before status publication, token refresh or account traffic.

## Architecture

Authenticated `/sync/socket` notifications invalidate local views. They never
authorize commands, acknowledge HTTP sync or update semantic enforcement state.
Commands still arrive by signed HTTP envelopes and retain exact daemon version
and schedule validation. The coordinator throttles socket liveness updates to
one per device per minute and does not rewrite enforcement report timestamps.

The native reconciliation scheduler owns five independent channels. Commands
have a 60-second lost-hint fallback, within the five-minute delivery TTL. Wake,
peers and overrides have five-minute fallbacks. Local pending-result checks run
every 15 seconds and do not send requests when empty. Per-channel in-flight work
coalesces hints into one trailing reconciliation with ten-second minimum spacing;
failures use bounded exponential backoff which hints cannot bypass.

Unchanged enforcement reports coalesce while in flight and after acknowledgement.
Failed reports retry, and semantic changes retain the exact local eligibility
fence. Connection liveness is independent of report freshness.

Socket credentials are headers, never query parameters. DPoP signs the canonical
HTTPS resource while the transport uses WSS. Opening a socket is not a successful
handshake: the first pong confirms it. Handshakes have a 30-second deadline;
established connections require a pong within 75 seconds. Reconnects back off
from 15 seconds to five minutes with bounded jitter; only a healthy minute resets
backoff. Revocation stops network tasks until explicit reconnection. System wake
and restored network paths explicitly replace the socket and resume independent
reconciliation without presenting UI. Deallocation closes the connection rather
than leaving an outstanding receive task. The native polling owner is not retained
across its timer sleeps.

Explicit restoration preserves accumulated socket failures instead of restarting
the backoff ladder. Status POSTs share the single-refresh retry path used by
reconciliation. Teardown cancels owned refresh work; generation checks before
refresh and cancellation checks before HTTP and credential persistence prevent
stale work from affecting replacement connections.

## Evidence and remaining acceptance

The deterministic idle schedule performs 1,440 command reads plus 288 each for
overrides, wake and peers: **2,304 protected reads per day**, a 90% reduction.
The 5,760 empty result checks are local. This is a scheduling regression, not a
claim that D1 indexed writes were measured after deployment. Nonce/replay cleanup,
rate-limit reservations, socket reconnects, refreshes and retention must be counted
in the final actual write budget. Multiple Macs and sustained active-user hint
traffic must not be equated with the one-Mac idle baseline.

Coordinator PRs 48 and 49 are deployed to staging. The native app work remains
draft: full consumer CI, lifecycle-adapter runtime proof and installed non-lock
verification are outstanding. CI 38305592933 passed the stale socket-refresh
generation regression and reproduced the status POST refresh failure before its
retry integration. The final fixes still require green native CI. Headless socket
restoration retains observed failing-first coverage, including backoff preservation.
Deploying source cannot restore
an already-exhausted daily quota. No billing change or new lock is authorized.

Rollback is the prior signed native build, with enrollment retained. Do not
install only semantic deduplication without the socket liveness implementation.
No protocol shape, schema migration, package version or daemon fence changed.
