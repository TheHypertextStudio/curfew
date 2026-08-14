# License Issuer Single Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent deployment of an obsolete license issuer by retaining one tested, reproducible Curfew Plus envelope-v2 Worker path.

**Architecture:** `web/worker/` remains the sole Worker source and `scripts/license-worker.mjs` remains the sole bootstrap interface. A Node regression test makes the forbidden legacy root artifacts part of the contract; documentation points operators only to the rendered-config flow, which keeps identifiers and secrets outside Git.

**Tech Stack:** Node.js built-in test runner, pnpm 11, TypeScript/Vitest, Cloudflare Wrangler, Swift/Xcode validation.

## Global Constraints

- Do not commit private signing seeds, Stripe secrets, Cloudflare account IDs, KV namespace IDs, or checkout URLs.
- Do not enable checkout; root `landing/index.html` must retain its sale gate.
- Preserve the separate staging Worker/KV/secrets path and use Stripe test mode for every staging proof.
- Do not change the envelope-v2 wire claims; the Worker and app verifier are one contract.
- Use `pnpm`; do not use npm or npx.
- Run the Curfew format, lint, unit-test, and Debug-build gates before completion.

---

### Task 1: Establish the single-issuer regression boundary

**Files:**
- Modify: `scripts/license-worker.test.mjs`
- Delete: `scripts/issue-license.ts`
- Delete: `scripts/gen-license-keypair.sh`
- Delete: `wrangler.toml`

**Interfaces:**
- Consumes: the committed canonical bootstrap entry point `scripts/license-worker.mjs` and canonical template `web/worker/wrangler.toml.example`.
- Produces: a Node test that fails whenever a root legacy issuer artifact returns.

- [ ] **Step 1: Write the failing regression test**

Add this test to `scripts/license-worker.test.mjs`:

```js
test("only the envelope-v2 Worker bootstrap remains deployable", async () => {
  for (const legacyPath of [
    "scripts/issue-license.ts",
    "scripts/gen-license-keypair.sh",
    "wrangler.toml",
  ]) {
    await assert.rejects(access(legacyPath));
  }
  await access("scripts/license-worker.mjs");
  await access("web/worker/wrangler.toml.example");
});
```

Import `access` from `node:fs/promises` alongside the existing imports.

- [ ] **Step 2: Run the regression test and verify the expected failure**

Run:

```sh
node --test scripts/license-worker.test.mjs
```

Expected: FAIL because all three legacy root artifacts still exist.

- [ ] **Step 3: Remove the obsolete issuer artifacts**

Delete exactly `scripts/issue-license.ts`, `scripts/gen-license-keypair.sh`, and root `wrangler.toml`. Do not delete `scripts/license-worker.mjs`, `web/worker/`, or any landing files.

- [ ] **Step 4: Re-run the regression test**

Run:

```sh
node --test scripts/license-worker.test.mjs
```

Expected: PASS, including existing keygen, validation, rendered-config, and workers.dev tests.

- [ ] **Step 5: Commit the boundary**

Commit only `scripts/license-worker.test.mjs` and the three deletions:

```sh
git restore --staged . && git -c advice.detachedHead=false add scripts/license-worker.test.mjs scripts/issue-license.ts scripts/gen-license-keypair.sh wrangler.toml && git commit -F /private/tmp/curfew-license-issuer-boundary-message.txt
```

### Task 2: Reconcile operator and release documentation

**Files:**
- Modify: `scripts/release-checklist.md`
- Modify: `Documentation/todos.md`
- Modify: `Documentation/todo-test-matrix.md`
- Modify: `Documentation/RELEASE.md`

**Interfaces:**
- Consumes: `Documentation/license-worker-bootstrap.md` and the commands exposed by `scripts/license-worker.mjs`.
- Produces: one reproducible production/staging deployment guide without legacy `curfew-pro`, root `wrangler.toml`, or shell-script keygen instructions.

- [ ] **Step 1: Write the failing documentation contract test**

Create `scripts/license-worker-documentation.test.mjs`:

```js
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const operatorDocs = await Promise.all([
  "scripts/release-checklist.md",
  "Documentation/todos.md",
  "Documentation/todo-test-matrix.md",
  "Documentation/RELEASE.md",
].map(path => readFile(path, "utf8")));

test("operator docs name only the envelope-v2 issuer bootstrap", () => {
  const text = operatorDocs.join("\\n");
  assert.match(text, /scripts\/license-worker\.mjs/);
  assert.match(text, /web\/worker\/wrangler\.toml\.example/);
  assert.doesNotMatch(text, /scripts\/issue-license\.ts/);
  assert.doesNotMatch(text, /scripts\/gen-license-keypair\.sh/);
  assert.doesNotMatch(text, /licensePublicKeyBase64/);
  assert.doesNotMatch(text, /REPLACE_WITH_CURFEW_PRO_PAYMENT_LINK/);
});
```

- [ ] **Step 2: Run the documentation contract and verify the expected failure**

Run:

```sh
node --test scripts/license-worker-documentation.test.mjs
```

Expected: FAIL because the release checklist and distribution todo still name the retired path.

- [ ] **Step 3: Update operator documentation to the canonical flow**

Make these exact policy changes:

- In `scripts/release-checklist.md`, replace legacy keygen/config/deploy steps with `node scripts/license-worker.mjs keygen`, `validate-config`, `render-config`, `dry-run`, and the documented `pnpm exec wrangler deploy --config /secure/user-owned/wrangler.toml` production action.
- State that the canonical product is `curfew-plus` envelope-v2; do not publish a payment link or ungate `landing/index.html` until live delivery is proven.
- In `Documentation/todos.md`, replace the legacy `wrangler.toml` completion claim and stale Curfew Pro wording with the canonical Worker/template and the remaining external production-delivery gate.
- In `Documentation/todo-test-matrix.md`, map the new documentation contract test to the single-path requirement.
- In `Documentation/RELEASE.md`, replace references to the removed bootstrap artifacts with `Documentation/license-worker-bootstrap.md` and distinguish the staging Curfew hostname from the production rollout.

- [ ] **Step 4: Re-run the documentation contract**

Run:

```sh
node --test scripts/license-worker-documentation.test.mjs
rg -n "issue-license\.ts|gen-license-keypair\.sh|licensePublicKeyBase64|REPLACE_WITH_CURFEW_PRO_PAYMENT_LINK" \
  scripts Documentation README.md
```

Expected: test PASS; search returns no operator-facing legacy references.

- [ ] **Step 5: Commit documentation reconciliation**

Commit `scripts/license-worker-documentation.test.mjs`, the four documentation files, and no runtime credentials:

```sh
git restore --staged . && git -c advice.detachedHead=false add scripts/license-worker-documentation.test.mjs scripts/release-checklist.md Documentation/todos.md Documentation/todo-test-matrix.md Documentation/RELEASE.md && git commit -F /private/tmp/curfew-license-issuer-docs-message.txt
```

### Task 3: Run the full local release-readiness verification

**Files:**
- Modify: none unless a verification failure identifies a defect.
- Test: `scripts/license-worker.test.mjs`, `scripts/license-worker-documentation.test.mjs`, `web/worker/test/crypto.test.ts`, `CurfewTests/`

**Interfaces:**
- Consumes: the single issuer boundary and reconciled documentation from Tasks 1–2.
- Produces: evidence that the Worker and macOS app retain their tested envelope-v2 path without enabling production checkout.

- [ ] **Step 1: Install locked Worker dependencies**

Run:

```sh
pnpm install --dir web --frozen-lockfile
```

Expected: lockfile install succeeds without modifying repository files.

- [ ] **Step 2: Run Worker and bootstrap checks**

Run:

```sh
pnpm --dir web test
pnpm --dir web typecheck
node --test scripts/license-worker.test.mjs scripts/license-worker-documentation.test.mjs
```

Expected: all checks PASS.

- [ ] **Step 3: Run Curfew quality gates**

Run:

```sh
swiftformat Curfew CurfewTests CurfewUITests --lint
swiftlint lint --strict
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests
xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Debug -destination 'platform=macOS'
```

Expected: all commands exit 0. Release archive/notarization remains an Apple-credential-only external gate and must not be bypassed.

- [ ] **Step 4: Verify public safety posture**

Run:

```sh
curl -fsSL https://curfew.hypertext.studio/ | rg "Curfew Pro is not on sale yet"
curl -fsS https://curfew-license-staging.hypertext.studio/health
```

Expected: the sale gate remains present and staging health reports envelope version 2.

- [ ] **Step 5: Commit any verification-only doc adjustments**

If verification requires no edits, do not create an empty commit. Otherwise use the repository’s atomic staging chain and a `/private/tmp/` message file created through `apply_patch`.

## Self-review

- Spec coverage: Tasks 1–2 remove the incompatible path and reconcile every listed operator surface; Task 3 proves Worker, app, format/lint, and public sale-gate behavior.
- No placeholders: all file paths, commands, legacy paths, and expected outcomes are explicit.
- Consistency: every task retains `scripts/license-worker.mjs` and `web/worker/wrangler.toml.example` as the canonical boundary; neither modifies checkout or live Stripe configuration.
