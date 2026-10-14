# Curfew Final Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one trustworthy 0.0.x Curfew release with a working signed Mac app, account connection, and authenticated remote MCP, while keeping paid access and the domain cutover behind their actual provider and recovery gates.

**Architecture:** Keep the Mac as the enforcement authority, Curfew Sync as the authenticated coordinator, and `curfew-protocols` as the exact shared wire contract. Prepare a signed, retained candidate separately from production activation; do not let a version tag implicitly publish a new site or appcast before the backend, identity providers, and recovery path are ready.

**Tech Stack:** Swift/AppKit/SwiftUI, Xcode, Swift Testing, Cloudflare Workers/D1/Durable Objects, TypeScript, pnpm, GitHub Actions, Apple Developer, Stripe, MCP Apps.

**Spec:** The owner's Curfew remote-MCP, 0.0.x, Hypertext Studio signing, domain-migration, and final-release requests; `Documentation/curfew-sync.md`, `Documentation/RELEASE.md`, `Documentation/remote-mcp-acceptance.md`, and the domain-migration runbook/evidence in Curfew PR #60.

## Global Constraints

- Versions stay `0.0.x`; pin exact protocol releases. Do not delete already-published `1.0.0` or rewrite immutable tags to disguise the mistake.
- Rebase/fast-forward only; never squash or create a merge commit. Preserve dirty work and use the repository's atomic staging chain and commit-body/co-author conventions.
- Use Hypertext Studio identities and GitHub Packages. A Development-signed Studio Dev app is not a Developer ID release artifact.
- No lock or unlock command, foreground UI automation, app restart, or disruptive system-lifecycle test without fresh specific authorization. The previously authorized physical lock is historical evidence, not standing permission.
- Do not repeat authenticator/recovery setup or erase enrolled device data. Preserve local schedules, encryption keys, receipts, purchases, and account ownership.
- Do not treat green CI, source code, a local preview, or a reachable endpoint as proof of production sign-in, installed-app connection, physical enforcement, billing, or notarized distribution.
- Production Stripe mutations and purchase-service rollout were explicitly stopped; keep that stop until the owner changes it. Staging Test mode is the authorized validation lane.

## Review Focus

- A browser-authenticated Mac whose token exchange or userinfo check fails must retain its prior enrollment and explain the actual stage; the native reconnect test owns this.
- Concurrent or stale MCP clients must not exhaust shared admission credits or make device state appear live; the backend rate tests and authenticated host read own this.
- An old-domain OAuth callback or token must not be redirected into the new authority or accepted after revocation; the domain-migration tests own this.
- A release candidate must not publish the new site/feed before coordinated activation; the release-workflow test and dry-run own this.
- A wrong-mode Stripe webhook must not touch purchase state or replay indexes; issuer tests and staging provider inspection own this.

## Current baseline (October 13, evening, Pacific)

- Other Curfew chats were idle and have been asked to hand off and stop overlapping pushes/provider actions. No open repository issues were listed; the open PRs are app #58, #60, #61 and backend #56.
- The installed `Curfew Studio Dev` app is signed by Studio team `T95VDD3A4W`, running with its helper, but the latest authenticated device read in this task reported the Mac offline. The earlier five-minute staging/Codex lock physically enforced and expired; current connection is not thereby proven.
- App #61 contains a failing-first native reconnect regression. Isolated macOS CI failed on that exact test; the production fix and current-device acceptance remain open.
- App #60 and backend #56 have green branch checks, but backend #56 conflicts with current main. Both pin protocol `1.0.0`, contrary to the owner's version rule. The latest prior `0.0.x` protocol tag is `v0.0.12`.
- App #58 is draft. Two tested local commits (Stripe mode guard and Test-mode clarification) are not in its PR checks. Production issuer auto-builds on main, so merging it is a production action, not only source integration.
- No current signed/notarized downloadable DMG or live appcast is verified. The current release workflow publishes the site/feed on a tag before signed-device acceptance, and the verifier still requires an old team ID.

### Task 1: Native account reconnect and current staging presence — owner: primary agent

**Files:** `Curfew/Core/Features/AccountEnrollmentController+ReadyReauthorization.swift`, `AccountOAuthEnrollment.swift` and related status/diagnostic code; `CurfewTests/Core/Sync/ReadyAccountReauthorizationSafetyTests.swift`; `Documentation/todos.md`, `Documentation/todo-test-matrix.md`, `Documentation/remote-mcp-acceptance.md`.

- [x] Add a regression for browser-complete/native-connection-failed while preserving the existing enrolled Mac and refresh token; observe its failure in isolated CI.
- [ ] Make the smallest state/copy correction and add privacy-safe boundary diagnostics for callback, token exchange, userinfo, credential commit, and status publication. Log stage/status only, never code, token, URL, recovery data, or account ID.
- [ ] Run targeted and full native tests, SwiftFormat/SwiftLint, and Debug build on isolated CI. Record the exact commit and failures rather than weakening a gate.
- [ ] Install a signed Studio Dev update only through a non-disruptive path; one normal reconnect, without repeating recovery setup, must restore the same account/device and make authenticated staging `list_devices` report current online presence. No lock/unlock is needed for this check.

### Task 2: Correct the shared version to 0.0.x — delegate: protocols/backend engineer

**Files:** `curfew-protocols/package.json`, generated version metadata/changelog/contracts; `curfew-sync/package.json` and lockfile; `curfew/CurfewKit/Package.swift`, Xcode package pins and resolved locks.

- [ ] Add/retain portability contract tests and publish one additive `0.0.13` protocol package/tag from the reviewed source; do not rewrite the published `1.0.0` artifact.
- [ ] Update both consumers to the exact `0.0.13` tag/package and regenerate lockfiles; run protocol codegen/contracts, Swift package tests, backend type/lint/test, and native build/tests.
- [ ] Review each cross-repo PR in protocol → backend → app order. Keep the version correction coordinated so no consumer points to an unpublished artifact.

### Task 3: Domain migration integration and release sequencing — delegate: backend/release engineer

**Files:** Curfew Sync PR #56 migration branch and Curfew PR #60 migration branch; `Documentation/domain-migration.md`; `.github/workflows/release.yml`; release verifier/tests.

- [ ] Rebase backend #56 onto current main, resolving only the todo/test-matrix conflicts while retaining both newer MCP admission work and migration requirements; rerun full backend CI.
- [ ] Add a failing release-workflow regression that demonstrates premature site/appcast publication. Separate candidate build/sign/notarize/retain from controlled activation, and verify the signed candidate's exact configuration hash, artifact hash, team, helper/widget, and update signature.
- [ ] Reconcile Studio team ID and `0.0.x` version in build settings, verifier, workflow, runbook, and evidence. Do not accept secret-name presence as signing proof.
- [ ] Rehearse migration against isolated staging/test data, including old-domain callback rejection, account/device retention, pending-command cancellation, rollback and resume gates. No production revocation in a rehearsal.

### Task 4: Plus/license staging boundary — delegate: licensing engineer

**Files:** Curfew PR #58 branch; `web/worker/src/index.ts`, issuer tests, `Documentation/plus-activation.md`, `Documentation/license-worker-bootstrap.md`.

- [ ] Read back the staging Build variable and verify it actually saved `CURFEW_LICENSE_STRIPE_MODE=test`; then push the two local tested commits and let staging CI deploy the guard. Missing/incorrect mode must fail closed.
- [ ] Verify Test-mode webhook, purchase, signed-app activation, and restoration in staging without creating another sandbox or changing live Stripe objects.
- [ ] Keep production billing and issuer deployment stopped pending the owner's explicit reversal of that stop; before any later activation verify `STRIPE_MODE=live`, historical-purchase restore, renewal/cancel/refund revocation, and checkout/portal permissions.

### Task 5: Authenticated MCP app and client experience — delegate: MCP/UI engineer after Task 1 presence

**Files:** Curfew Sync MCP app UI/tests and `Documentation/remote-mcp-acceptance.md`.

- [ ] Verify the deployed native-style MCP panel in the actual authenticated Codex host, including keyboard/focus, device selection, offline/error state, and a readable refresh action. A localhost preview does not satisfy this.
- [ ] From Codex on phone, perform a read-only device list and confirm the same online Mac. Record the client, environment, account type, timestamp, and response; do not infer Claude support from Codex proof.
- [ ] Preserve the prior authorized lock-enforcement evidence; any new physical lock needs new authorization and is not part of this plan's automatic execution.

### Task 6: Signed release candidate and coordinated production activation — owner: primary agent; provider-specific work delegated only after prerequisites

**Files:** `.github/workflows/release.yml`, `scripts/verify-release-artifact.sh`, `Documentation/RELEASE.md`, `Documentation/release-evidence/`, site/appcast deployment configuration, backend migration runbook.

- [ ] Validate actual Developer ID Application signing for the Studio team, notarization credentials, Sparkle key pair, entitlements, and package provenance; build/retain one `0.0.x` candidate without publishing the site/feed.
- [ ] Download and install that exact candidate on an authorized validation Mac; verify Gatekeeper, stapling, updater, helper, widget, retained settings, CLI/local MCP, accessibility, and non-destructive account recovery. Destructive shutdown/reboot checks require a sacrificial host and specific authorization.
- [ ] Before production domain activation, verify Cloudflare zone/DNS/TLS, Apple/Google callbacks, passkey migration/recovery for existing accounts, mail, backups, provider receipts, pending-command drain, and a usable rollback path.
- [ ] Only after all hard gates pass, execute the recorded cutover, activate the new site/feed and services together, verify same-account/device/assistant reconnect and encrypted-data readability, and monitor. If a hard gate fails, keep the public release withheld and name that exact gate rather than publishing a misleading success.

## Dependency and handoff order

Task 1 and the read-only audits for Tasks 2–4 can proceed independently. Task 2 must precede final integration of Tasks 3 and 6. Task 5 depends on Task 1's online presence. Task 6 depends on Tasks 2–5 and real provider/signed-device evidence. No branch is merged merely because its own CI is green; integration is by rebase/fast-forward with final combined checks.

## End-of-night decision

The target is a connected staging Mac, a reviewed/merged 0.0.x source line, and a retained signed candidate if signing gates pass. A public domain/billing release is conditional on the enumerated recovery, provider, identity, and artifact checks. Record completed versus blocked chunks at the deadline; never represent an unverified production cutover as finished.
