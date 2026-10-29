# Reliable Payment Fulfillment Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, with failing-first tests and one whole-change review.

**Goal:** Concurrent and refunded purchases must not mint conflicting or restored access.
**Architecture:** D1 transaction adapter around existing issuer records, immutable payment/refund references and invoice-backed subscription periods.
**Tech Stack:** TypeScript, Cloudflare D1, Vitest, real SQLite for local SQL tests.
**Spec:** `docs/superpowers/specs/2026-10-29-payment-fulfillment-design.md`

## Global Constraints

- Preserve existing USD20 offers, envelope v2, signers, URLs and user data.
- No real charges, new credentials, production storage provisioning or migrations.
- Keep sale links inactive until actual product/fulfillment acceptance.
- Run local runtime checks through the installed resource guard.

## Review Focus

- Concurrent first delivery: one canonical key/token survives successful commit.
- Refund before purchase/invoice: replay cannot resurrect revoked entitlement.
- Failed transaction or eviction: no partial order, marker or premature email.
- Renewal refund/cancellation: recover prior valid paid period, never extend it.
- Legacy import and missing authority: fail closed without discarding old data.

### Task 1: Atomic issuer storage

Files: `src/transaction-store.ts`, `src/core.ts`, `src/index.ts`, `src/types.ts`,
`migrations/0001_license_store.sql`, `test/transactional-flow.test.ts`, test SQLite helper.
Interface: `withLicenseTransaction(request, env): Promise<Response>` routes public
purchase requests; `LicenseStore` retains get/put/delete/list signatures.

- [x] Write public-handler regressions for no-authority503, no KV writes and concurrent fulfillment; observe failure.
- [x] Implement global-revision guarded commit and bounded conflict retries; persist and lease the durable email outbox after commit.
- [x] Verify transaction rollback, read-only validation, prefix phantoms, ABA, outbox crash/retry and TTL across fresh request instances.

### Task 2: Refund-aware invoice fulfillment

Files: issuer handlers/purchases/stripe helpers and transactional flow tests.
Interface: existing HTTP endpoints and envelope v2 unchanged; `invoice_payment.paid`
and `charge.refunded` join existing signed webhook dispatch.

- [x] Add failing tests for refund before/after checkout, renewal/refund ordering, replay, cancellations and recovery routes.
- [x] Record payment references/refund tombstones; require actual backed invoice periods; resolve all endpoints consistently.
- [x] Run complete Worker suite and TypeScript check after every behavior change.

### Task 3: Delivery and migration

Files: deployment configuration, explicit migration/import tooling, existing launch docs.

- [x] Prepare environment-specific D1 binding without provisioning; retain KV identities and signing secrets.
- [x] Document export/import/backfill, verification, rollback and go-live commands with --provision=false.
- [x] Run formatter, tests, typecheck, local cf build and independent review.
- [ ] Commit through normal hooks with Studio identity and Codex attribution; open draft PR, never approval review.
