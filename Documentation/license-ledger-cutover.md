# Transactional license ledger cutover

This runbook prepares the existing license issuer for concurrent webhook delivery
and refund-aware online recovery. It does not authorize resource creation, copy
credentials, open sales or perform a real charge. Preserve the existing signers,
KV namespaces, purchase URLs and USD20 lifetime/yearly prices.

## Source and acceptance contract

`index.ts` authenticates Stripe before database access and runs the existing
issuer core through a D1 transaction. A revision is read before all ledger reads;
a CHECK-failing guard and all writes/event markers commit in one atomic D1 batch.
Read-only key responses also validate the revision. Conflicts retry at most 16
times, then return 503 so Stripe can retry without a falsely acknowledged event.
The primary is used; no replica session or KV fallback is enabled.

`charge.refunded` closes a payment only when Stripe reports `refunded:true`.
Partial refunds retain access. A confirmed full refund is terminal for that
payment: replay cannot restore it. This does not claim immediate revocation of
an offline key already downloaded. All GET, activation, redeem, refresh and inbox
restoration routes consult the same funding records. A refunded renewal falls
back to the latest remaining funded period; cancellation retains paid periods.

A paid Curfew checkout establishes the order and one refresh identity. It does
not create a provisional subscription period. A signed paid invoice supplies the
actual period and amount; legacy `invoice.payment_intent` or modern
`invoice_payment.paid` allocation facts supply funding. Incomplete allocation
facts remain pending. Distinct allocations are retained and a legacy/modern
reference to the same PaymentIntent is not counted twice. Refunding allocated
funding below the invoice's paid amount removes that period from online delivery.

Email requests commit a ticket and durable outbox entry together. The outbox is
claimed with a 60-second lease and retried every five minutes. A crash can deliver
the same usable link twice; it cannot silently lose a committed valid request.
An outage lasting beyond the 15-minute ticket validity requires a fresh request.
Failed sends remain pending; no receipt or successful delivery is fabricated.

## Required inputs

- Existing separate production/staging Studio accounts, resources and keys.
- Reviewed signed app/configuration and exact accepted issuer source artifact.
- An explicitly selected D1 database UUID per environment. Prefer an isolated
  issuer database. If no suitable database already exists, prepare the resource
  choice/cost and obtain the applicable authorization before provisioning it.
  This change creates no database automatically. Never substitute the coordinator
  database or production storage merely to obtain a passing staging check.
- A complete private KV snapshot and Stripe provenance export from the same
  environment. KV namespace inventory currently returned401 for the inspected
  profile; resolve existing authorized read access without bypassing or creating
  credentials. Keep both source snapshots and subsequent ledger writes.
- Existing Test-mode authorization for staging. The currently authorized CLI
  account exposes live mode and no sandbox; that is missing test access, not
  evidence that historical Test mode was deleted. Do not create a replacement.

## Prepare and review the import offline

Snapshot JSON is `{version:1, mode, namespaceID, records:[{key,value,expiration?}]}`.
`expiration`, when present, is Unix seconds as in KV. Export every page without
logging values. The preparation bound is 10000 records/20 MiB per input; stop for a
larger inventory rather than truncate it. Store the files privately.

Provenance JSON is `{version:1, mode, orders, invoices, refunds}`. Derive it from
actual provider records, including refunded historical payments:

- `orders`: `{sessionID, plan:"lifetime", paymentIntent}` or
  `{sessionID, plan:"subscription", subscriptionID}`.
- `invoices`: `{id, subscriptionID, email, periodEnd, amountPaid, currency,
payments:[{id:<PaymentIntent>, amountPaid}]}`. Only include verified paid facts;
  amounts use the provider's smallest currency unit, periods use Unix seconds.
- `refunds`: `{paymentIntent, fullyRefunded}` from confirmed provider state.
  Pending/failed/partial refund initiation does not establish a full refund.

Use the public signer from the selected live/test issuer, independently matched
to the correct build. The command makes no network calls and writes its explicit
new output at 0600; it refuses overwrites and rejects invalid signatures or mixed
environments. Do not put snapshots, SQL, purchase keys or customer data in Git.

```sh
node scripts/license-ledger-import.mjs prepare \
  --snapshot /private/reviewed-kv.json \
  --provenance /private/reviewed-stripe-provenance.json \
  --mode staging --namespace EXISTING_STAGING_KV_ID \
  --public-key MATCHING_STAGING_PUBLIC_KEY \
  --output /private/license-import.sql
```

Exit 0 means all copied license records have matching funding provenance. Exit 2
means unresolved records remain; do not accept that migration. Exit 1 is invalid
input/output. The tool always leaves readiness closed. It verifies the signature
of every stored envelope, preserves existing records/expiry and adds verified
funding/index records. This local receipt is not provider verification or operator approval.
Existing envelopes with missing paid-period/refund
provenance are preserved but cannot gain new online delivery by fallback.

D1 SQL import does not support explicit BEGIN statements. Apply only to an empty
or identical partially imported, closed ledger. Each prepared insert checks
`ready=0`; a mismatched snapshot receipt prevents mixing imports. Identical retries
are additive. Partial import remains unavailable and must never be marked ready.
Before acceptance, compare the private source receipt, total unique record count
(receipt.records+1 including the receipt), each imported value/expiration, signer,
mode, namespace and unresolved count. A second import is not a rollback strategy.

## Controlled staging deployment

1. Inventory the retained D1 target and backup/recovery path. Preserve the existing
   KV and Stripe event history. Arrange a bounded webhook pause/retry window for
   the final snapshot; existing renewals can occur even while links are inactive.
2. Apply `web/worker/migrations/0001_license_store.sql`, then the reviewed private
   import through the authorized D1 operator. The additive schema defaults to
   `ready=0`. No source file or build command runs either migration remotely.
3. Verify import equality and payment/refund provenance. Only after acceptance,
   explicitly execute `UPDATE curfew_license_meta SET ready=1,revision=revision+1
WHERE id=1 AND ready=0`. This readiness change is operator execution against
   the reviewed target, not an automatic side effect of a build or import.
4. Set `CURFEW_LICENSE_STAGING_DATABASE_ID` to that existing UUID and retain the
   existing staging Worker/KV/configuration pins. Retain the approved app
   configuration artifact independently of the newer issuer source revision;
   do not relabel its configuration commit merely to match this code change.
   Build, inspect and deploy the
   exact accepted output with the repository's pinned CLI:

   ```sh
   pnpm --dir web/worker exec cf build --mode staging
   pnpm --dir web/worker exec cf deploy --prebuilt --mode staging --dry-run --provision=false
   pnpm --dir web/worker exec cf deploy --prebuilt --mode staging --provision=false
   ```

   Missing D1 configuration is allowed for local/CI bundle inspection, but
   purchase APIs and health fail closed without a ready ledger. Inspect the
   retained D1 identity and five-minute scheduled trigger before publication.

5. Update the existing staging license webhook event set, preserving current
   events and adding `checkout.session.async_payment_succeeded`,
   `invoice_payment.paid` and `charge.refunded`. No replacement secret is needed.
6. Verify Test-mode checkout, delayed/failing payments, duplicate/concurrent
   delivery, paid renewal, partial/full refunds, cancellation, expired access,
   confirmation, receipt, inbox delivery/retry and browser-to-app restoration.
   Use the matching signed Dev build; a staging key must not activate Release.
7. Verify public health reports `license_storage:"ready"` with the expected mode,
   configuration and public signer. Health alone does not close the purchase
   journey or hosted account-entitlement claim.

## Production and recovery

Repeat the inventory, final snapshot/import acceptance and separate backup for
production. Set `CURFEW_LICENSE_PRODUCTION_DATABASE_ID`; never reuse the staging
UUID. Follow `production-domain-promotion.md` using the accepted artifacts and
`--provision=false`. Existing links remain inactive until functional signed-app,
fulfillment and paid hosted-feature acceptance pass. Enabling those existing
links then belongs to the requested launch; new credentials, scopes, agreements,
security changes or new storage creation require their applicable authorization.

Sandbox end-to-end purchase, license delivery, download and activation in the
matching signed test build are sufficient payment acceptance. Never make a
production test charge or require a real purchase or production-license activation
as an acceptance gate. Verify production mode, endpoint/signer pairing, prices,
redirects and retained resource configuration read-only. Keep Release trust fixed;
do not make it accept a sandbox signer. Synthetic webhook tests are separate
from actual sandbox checkout. Other release gates and production-change
authorization remain in force.

After cutover, the D1 ledger is authoritative. Do not roll back to KV: it lacks
new purchases/refunds and would resurrect access. On failure, keep links closed,
stop new ledger-dependent delivery with a reviewed readiness change and deploy a
forward fix against retained D1 data. Preserve the outbox, processed events and
refund tombstones. Use the database backup only with a plan to replay every later
provider fact and retain later valid writes. No destructive down migration is
provided.
