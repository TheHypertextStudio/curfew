import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = path => readFile(path, "utf8");
const deployment = (await import("../deployment/generated/environments.mjs")).default;
const config = JSON.parse(await read("web/docs/docs.json"));
const pages = config.navigation.groups.flatMap(group => group.pages);

test("public help covers setup, everyday use, Plus, integrations, and recovery", () => {
  for (const page of ["index", "install", "schedules", "lockout", "exceptions", "reflections",
    "licensing", "sync", "widgets", "calendar", "mcp-guide", "cli", "troubleshooting", "privacy", "uninstall"]) {
    assert.ok(pages.includes(page), `Missing user journey: ${page}`);
  }
  assert.equal(new Set(pages).size, pages.length, "Navigation must not repeat pages");
});

test("every public page has reader metadata and working local page links", async () => {
  for (const page of pages) {
    const content = await read(`web/docs/${page}.mdx`);
    const metadata = content.match(/^---\n([\s\S]*?)\n---/);
    assert.ok(metadata, `${page} needs page metadata`);
    assert.match(metadata[1], /^title: .+$/m);
    assert.match(metadata[1], /^description: .+$/m);
    if (page === "mcp-guide") {
      assert.equal(metadata[1].match(/^canonical: (.+)$/m)?.[1], new URL("/docs/mcp", deployment.production.siteOrigin).href);
    }
    for (const match of content.matchAll(/(?:\]\(|href=")[\/]([^"\s)#]+)(?:#[^"\s)]+)?[)"]/g)) {
      const target = match[1];
      if (target.includes(".")) continue;
      assert.ok(pages.includes(target), `${page} links to missing page ${target}`);
    }
    assert.doesNotMatch(content, /curfew-license\.hypertext\.studio\/(?:reference|openapi\.json)/);
  }
});

test("activation help matches the app's About tab instead of the removed License tab", async () => {
  for (const path of ["web/docs/licensing.mdx", "landing/src/components/PurchasePanel.astro"]) {
    const content = await read(path);
    assert.match(content, /Settings → About/);
    assert.doesNotMatch(content, /Settings → License/);
  }
});

test("purchase help never claims a missing key is in the receipt or proves payment succeeded", async () => {
  const content = await read("landing/src/components/PurchasePanel.astro");
  assert.doesNotMatch(content, /key is also in your receipt email|check your receipt email|Your payment went through/);
  assert.match(content, /Stripe emails your payment receipt/);
});

test("assistant help discloses provider processing instead of promising local-only reads", async () => {
  const content = await read("web/docs/mcp-guide.mdx");
  assert.match(content, /provider/);
  assert.doesNotMatch(content, /Reflections are \*\*read-only\*\* and never leave your Mac/);
});

test("upcoming Plus guides identify their launch status", async () => {
  for (const page of ["licensing", "sync", "widgets", "calendar"]) {
    assert.match(await read(`web/docs/${page}.mdx`), /not on sale yet|not available yet/);
  }
});

test("documentation regressions run in repository CI", async () => {
  assert.match(await read(".github/workflows/ci.yml"), /node --test scripts\/user-docs\.test\.mjs/);
});

test("disconnect help requires removing assistant configuration, not just the app toggle", async () => {
  for (const page of ["mcp-guide", "privacy"]) {
    const content = await read(`web/docs/${page}.mdx`);
    assert.match(content, /can still read|remain readable/i);
    assert.match(content, /configuration/);
    assert.match(content, /restart/i);
  }
});

test("journal and uninstall help protect older entries before deletion", async () => {
  assert.match(await read("web/docs/reflections.mdx"), /current calendar week/);
  const cli = await read("web/docs/cli.mdx");
  assert.match(cli, /reflections --days 365 --json > /);
  assert.match(cli, /all entries you want to keep/);
  assert.match(await read("web/docs/uninstall.mdx"), /older entries/);
});

test("CLI help explains that legacy override requests are rejected", async () => {
  assert.match(await read("web/docs/cli.mdx"), /legacy.*override[\s\S]*rejects/i);
});

test("assistant help does not present its countdown as current enforcement", async () => {
  const content = await read("web/docs/mcp-guide.mdx");
  assert.match(content, /countdown.*saved schedule/);
  assert.match(content, /hours-based/);
  assert.match(content, /temporary extensions or active overrides/);
});

test("public help avoids self-narration and unnecessary contrast", async () => {
  const narration = /\b(?:this guide covers|this guide connects|the Plus guides cover|these policies govern|this page is where it lives|the key only lives here|rather than|as proof|does not confirm|does not promise|not a substitute|do not assume)\b/i;
  for (const path of [...pages.map(page => `web/docs/${page}.mdx`), "landing/src/components/PurchasePanel.astro"]) {
    const content = await read(path);
    assert.equal(narration.test(content), false, `${path} contains editorial narration or unnecessary contrast`);
  }
});

test("published help follows current Settings labels and installer availability", async () => {
  for (const page of pages) {
    assert.doesNotMatch(await read(`web/docs/${page}.mdx`), /Settings\s+→\s+Integrations|Settings\s+→\s+Enforcement|Show\s+Getting\s+Started|Enable\s+MCP\s+Control\s+Plane|Paste license key…/);
  }
  assert.match(await read("web/docs/install.mdx"), /public Mac installer has not been released yet/);
  assert.match(await read("web/docs/mcp-guide.mdx"), /Allow assistants on this Mac/);
});
