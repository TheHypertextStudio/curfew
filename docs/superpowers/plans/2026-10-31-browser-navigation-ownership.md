# Browser Navigation Ownership Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this finite repair inline.

**Goal:** A delayed Curfew blocker must not replace a newer work/authentication navigation or recreate a request for a closed tab.

**Architecture:** Keep transient ownership for each pending blocked navigation. Invalidate ownership synchronously on a different URL, tab closure, or a newer blocked navigation. Check ownership after asynchronous storage boundaries, discard only the abandoned operation's request, and retain current session checks before redirecting. This is a repair to existing navigation behavior, not a new enforcement mode.

**Tech stack:** Existing TypeScript Chrome controller and Vitest; no dependencies, protocol changes, browser installation or permissions.

**Spec:** Existing `Documentation/chrome-extension.md` navigation/request lifetime and this task's requirement to keep paid work and authentication accessible.

## Global Constraints

- Preserve signed candidate 0.0.17, producer `8eefbc72`, and successful run `40905506718`; do not build or publish another release.
- Preserve rule enforcement and destination-review requirements. Canceling a stale redirect must not allow an otherwise blocked destination.
- No real browser lock, extension installation, OS grant, account credential, production change or denied-PR retry.
- Checkout and Android owners retain their files. Claude ownership remains uncertain while the desktop is locked; use this isolated worktree.
- No native build or new waiting guard; execute finite existing-dependency checks only after resource admission.

## Review Focus

- A tab navigates away while request persistence is pending: never redirect it back or retain the abandoned URL.
- A tab closes while policy/storage is pending: never recreate its review request.
- A newer blocked navigation supersedes an older one: retain the newer request only.
- A same-navigation URL event or another tab's event must not cancel the legitimate blocker.
- A session ends while routing is pending: never show a blocker for the old session.

## Task 1: Retire Superseded Blocker Operations

**Files:** `web/extension/src/controller.ts`, `web/extension/test/controller.test.ts`, `Documentation/chrome-extension.md`, `Documentation/todos.md`, `Documentation/todo-test-matrix.md`.

- [x] Add controlled storage-read/write barriers to the existing test dependency harness.
- [x] Observe failing regressions for newer navigation, tab closure, newer blocked navigation, and session completion; retain passing same-navigation and other-tab controls. Parent cloud verified the exact r2 kit: baseline 46/46; expanded 54 total, 48 pass and six exact failures, no skips; typecheck exit 0.
- [x] Add per-tab transient ownership, check it after each relevant asynchronous boundary, and remove only stale operation-owned request data. Preserve ordinary DNR policy behavior.
- [x] Run the complete portable controller/rules/destination/watcher core and `tsc --noEmit`; retain exact results and bounded resource custody. Parent cloud final 57/57 GREEN, no skips, typecheck exit 0, same lock/tests and no reinstall.
- [x] Update the existing behavior docs/test matrix with actual verification and Chrome runtime limits. Obtain independent review and fix blocking findings. One Important finding verified RED→GREEN; one minor explicitly deferred.
- [x] Attempt normal formatting/hooks and retain the exact blocker: ordinary commit exited 1 before creation; formatter entry reports missing generated `runtime.json`, and the pinned 3.9.10 prepared cache is absent. Preserve the complete staged patch and all proof; integration remains pending without a bypass or publication.

The intended demo claim is limited to tested controller behavior under synthetic browser/storage dependencies. A production Chrome identity, actual installed-browser navigation acceptance and all-device enforcement remain separate gates.

## Execution Ledger

- Base: `8eefbc723397e3fa05657b89b2aff95bdad83fb3`. No shared task interfaces; checkout/Android owners retain their files.
- Ruling: reuse the parent's installed cloud Node 24.20.0/pnpm 11.9.0 tree instead of a local producer — internal reserve/shared pool are blocked; cost is a portable input/hash boundary, which each runner checks.
- Ruling: verify the entire portable controller/rules/destination/watcher core rather than rerunning native icon/packaging producers — those inputs are unchanged and resource admission is unavailable; cost is explicitly retaining packaged-extension and installed Chrome acceptance as release gates.
- Initial per-navigation ownership patch: controller SHA-256 `9575c4fcbe2e6a130a01e3919da75e30f290985bb4b2e2db220737959ec0ab8d`; original 54-test files and lock unchanged. Parent cloud observed 54/54 GREEN.
- Final review: one Important stale captured-policy-delivery finding. Ruling: keep all original tests byte-identical and add a separate three-case test file — this preserves the initial regression proof while exercising the missed interleaving; cost is one finite additional cloud RED before its fix.
- Final review minor (deferred): direct simulation of the blocker's own URL-update event before the tabs-update promise resolves; static review found no blocking defect, and installed Chrome event acceptance remains pending.
- Review RED: parent cloud observed 57 total, 54 passes and three exact policy-delivery failures, typecheck exit 0 and no skips, without reinstalling. Final guard controller SHA-256 `a83493e59a0162ec9afb7528870b9c56bd59f4f14a0691a8e27daddcb527c790` was written after that RED. Parent cloud final 57/57 GREEN and typecheck exit 0 bind this exact source; all test sources and the frozen lock are unchanged.
- Final: fixed Important stale policy delivery — separate three-case RED→GREEN, full portable suite 57/57 and typecheck passing.
- Normal integration preflight found inherited hooks bound to the frozen sibling checkout. The supported installer recomposed worktree-specific formatter and native commit-msg hooks from the exact retained native source, without tools/downloads or a commit under the bootstrap-only configuration. Wrapper/source hashes and correct worktree binding were verified. Pinned formatter/runtime preparation remains required; no downgrade or bypass.
- Ruling: recompose from the verified retained native hook source instead of forwarding the sibling's generated wrapper — the formatter must target this worktree; cost if wrong is checking or formatting the wrong checkout, so both retained check hashes and the generated worktree binding were verified before any commit attempt.
- Normal commit attempt: ordinary worktree-bound hooks ran without the bootstrap configuration or bypass. Git exited 1 at formatter startup; HEAD stayed `8eefbc72`, controller/test/index bytes stayed exact GREEN, and the frozen sibling source stayed clean. Targeted formatter diagnosis reported missing generated `runtime.json`; the pinned 3.9.10 cache is also absent. No source commit was created.
- Source-fix verification is complete; normal integration is blocked by supported pinned-tool preparation under the shared capacity policy. No local build/test producer, external publication or denied-PR retry occurred.
