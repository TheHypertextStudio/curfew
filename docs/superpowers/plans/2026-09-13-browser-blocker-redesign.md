# Browser Blocker Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the self-narrating editorial blocker with a compact Curfew-native access request.

**Architecture:** Keep the existing blocker protocol and DOM identifiers. Reduce the static document to one semantic content column, then let `blocker.ts` supply task, destination, question, action, and state changes. Use extension-local CSS and the existing icon package so the page remains offline and CSP-safe.

**Tech Stack:** Manifest V3, semantic HTML, CSS, TypeScript, Vitest, esbuild.

---

### Task 1: Lock the reduced interface contract

**Files:**
- Modify: `web/extension/test/build.test.ts`

- [ ] **Step 1: Write the failing test**

Add a build assertion that requires the Curfew icon, task heading, hostname, question, one answer field, and `Request access` action. Reject `DESTINATION HELD`, `ACTIVE TASK`, `Stop. Name the work.`, `Your plan and deliverable`, and the offline footer.

```ts
it("builds one focused access request without self-narrating chrome", async () => {
  const output = await build("production", TEST_PRODUCTION_IDENTITY);

  expect(output.blocker).toContain('src="icons/icon-32.png"');
  expect(output.blocker).toContain('<h1 class="task" id="task-title"');
  expect(output.blocker).toContain('id="target-host"');
  expect(output.blocker).toContain('id="question"');
  expect(output.blocker).toContain('id="justification"');
  expect(output.blocker).toContain('>Request access</button>');
  for (const narration of [
    "DESTINATION HELD",
    "ACTIVE TASK",
    "Stop. Name the work.",
    "Your plan and deliverable",
    "Unknown destinations stay blocked",
  ]) {
    expect(output.blocker).not.toContain(narration);
  }
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```sh
cd web
pnpm --filter @curfew/chrome-extension test -- build.test.ts
```

Expected: the new interface assertion fails because the current document contains the removed narration and lacks the icon and action label.

### Task 2: Replace the blocker presentation

**Files:**
- Modify: `web/extension/blocker.html`
- Modify: `web/extension/blocker.css`
- Modify: `web/extension/src/blocker.ts`

- [ ] **Step 1: Reduce the document**

Use this structure while preserving every script-owned identifier:

```html
<main class="review" aria-labelledby="task-title">
  <header class="brand"><img src="icons/icon-32.png" alt=""><span>Curfew</span></header>
  <section class="request">
    <h1 class="task" id="task-title">Loading current task…</h1>
    <p class="host" id="target-host">Loading destination…</p>
    <p class="question" id="question">Checking this request…</p>
    <form id="review-form">
      <label class="visually-hidden" for="justification">Justification</label>
      <textarea id="justification" name="justification" aria-labelledby="question"></textarea>
      <div class="actions">
        <p id="status" role="status" aria-live="polite"></p>
        <button id="submit" type="submit">Request access</button>
      </div>
    </form>
  </section>
</main>
```

- [ ] **Step 2: Replace the visual system**

Use one 560-pixel column on `#f4f1eb`, body text `#211f1c`, muted destination text `#6f6a62`, and Curfew red `#b43b32` for the primary action. Remove the grid, card border, masthead, serif display face, badges, all-caps labels, hard shadow, and footer. Keep a visible keyboard focus ring, a 44-pixel minimum action height, and a single-column 390-pixel layout.

- [ ] **Step 3: Remove runtime narration**

Leave the initial and demo status empty. Use `Submit answer` for the one challenge. Use short outcome text such as `Checking…`, `More detail needed.`, `Opening destination…`, `This request expired. Open the destination again.`, and `Review is unavailable. The site remains blocked.`

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```sh
cd web
pnpm --filter @curfew/chrome-extension test -- build.test.ts
```

Expected: the focused build tests pass.

### Task 3: Verify behavior and appearance

**Files:**
- Modify: `Documentation/chrome-extension.md`

- [ ] **Step 1: Run the extension gate**

Run:

```sh
cd web
pnpm --filter @curfew/chrome-extension test
pnpm --filter @curfew/chrome-extension typecheck
pnpm --filter @curfew/chrome-extension build:development
pnpm --filter @curfew/chrome-extension package:draft
```

Expected: all tests and type checking pass, and both development and draft packages build.

- [ ] **Step 2: Reload and inspect the installed extension**

Reload `web/extension/dist/development` in the Hypertext Studio profile. Open the development fixture and inspect both the desktop layout and a 390-pixel-wide window. Confirm that every required datum remains visible, no horizontal scrolling occurs, and the removed narration is absent.

- [ ] **Step 3: Update the operator guide**

Replace the old screenshot wording with the reduced interface contract. Keep the warning that the development fixture is visual evidence only and does not prove live enforcement.

- [ ] **Step 4: Commit**

Stage only the blocker design, tests, implementation, and operator guide. Commit with `fix(enforcement): Remove narration from the browser blocker` and explain that the protocol did not change.
