# Reliable payment fulfillment

The existing issuer signs offline license envelopes and uses eventually consistent
KV. An event marker cannot prevent concurrent first delivery, and refunds are
not reconciled. Preserve public endpoints, existing prices, signers and envelopes.

Use a small optimistic transaction adapter over D1 for the issuer's existing
key/value records. Each transaction reads a global revision before any record, validates that
revision, then commits all writes and its event marker in one atomic batch.
A failed CHECK aborts the entire batch, including on read-only validation.
Conflict retries rerun only local computation; email delivery uses a durable
outbox written with its ticket and claimed with a short lease after commit.
Retrying a message sends the same still-valid link; delivery is at least once.
Rate-limit checks run once per external request, outside conflict retries. The public issuer has no KV fallback. Existing KV is
retained for a separately reviewed import and rollback; no production data is
moved or storage provisioned during implementation.

Alternatives: deterministic keys plus immutable KV records still leave refund
and ordering reads stale; a global Durable Object would serialize unrelated
customers and require a new runtime model. D1 fits existing Cloudflare operations
and retains the issuer's existing handlers. The agent selects this approach under
the delegated instruction to implement the smallest robust solution and prepare
any storage migration without provisioning it.

Record successful payment references and immutable full-refund tombstones. Resolve
all delivery/recovery paths against these records. Subscription grants require a
paid invoice's actual period and linked payment, never an arbitrary provisional
period. Modern `invoice_payment.paid` events supply payment references without a
new Stripe API credential. Cancellation keeps the final non-refunded paid period;
failed payment does not extend it. Partial refunds do not revoke full access.
Existing downloaded offline keys cannot be remotely revoked; disclose that limit.

Keep links inactive. Provider test access, data inventory/import, D1 binding and
schema application, current signed-device acceptance, webhook registration and
hosted account entitlement acceptance remain deployment gates.
