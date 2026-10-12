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

Final ordering review found that independent command/result tasks could fetch
newer commands while a terminal result upload failed. CI 38308503697 reproduced
the forbidden command fetch with a clean inverted-expectation failure before
repair. Both channels now share an owned result-publication task; command fetching
waits for successful receipt recording. Failed uploads prevent the fetch, while
unrelated channels remain independent. This orders results present when reporting
begins, not a cross-process atomic barrier against subsequently created results.
Generation-fenced task cleanup happens before completion so a token-refresh retry
cannot rejoin a completed failed task. Full hosted verification remains required.

CI 38309791533 exposed a second successful POST of the same daemon result in
the sequential polling regression. The daemon retains pending results until it
validates the coordinator receipt. The transport now remembers only results it
successfully uploaded and wrote receipts for in this connection, prunes that
memory against the pending snapshot, and clears it on teardown. It does not trust
a user-created receipt file as evidence of server acceptance. Failures and changed
results remain retryable; reconnect permits idempotent re-reporting. Authorized
HTTP checks cancellation before challenges and after the challenge suspension.
Cadence fixtures await URLSession invalidation before clearing their handlers,
preserving failures without contaminating the next test. Hosted verification of
these corrections remains required.

CI 38307160113 also exposed late network work after fixture teardown. The crash
attachment traces a nil URLProtocol handler to a background XCTest assertion,
not a UI launch. A stale poll can currently invoke its operation before checking
generation/cancellation; CI 38308319780 and 38308503697 observed one operation
instead of zero in the explicit no-operation-after-disconnect regression. The
entry fence now precedes credentials and operation invocation. The synchronous
eligibility fixture disconnects its transport, and HTTP fixture cancellation
suppresses queued delayed responses without hiding missing-handler failures.
Do not hide these failures by increasing timeouts or dropping handler assertions.

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
