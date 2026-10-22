import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = path => readFile(path, "utf8");
const deployment = (await import("../deployment/generated/environments.mjs")).default;
const config = JSON.parse(await read("web/docs/docs.json"));
const pages = config.navigation.groups.flatMap(group => group.pages);

test("documentation uses the homepage typefaces with local licensed font assets", async () => {
  const styles = await read("landing/public/site-assets/design/tokens.css");
  const source = JSON.parse(await read("web/docs/docs.site.json"));
  const family = role => styles.match(new RegExp(`--${role}:\\s*"([^"]+)"`))?.[1];
  assert.equal(source.fonts?.body?.family, family("body"), "Docs must select the homepage body font instead of the provider default");
  assert.equal(source.fonts?.heading?.family, family("display"));
  assert.equal(Object.hasOwn(source.fonts, "family"), false, "A global family makes the provider discard the heading/body overrides");
  assert.deepEqual(config.fonts, source.fonts, "Generated typography must match the product configuration");
  for (const face of [source.fonts.body, source.fonts.heading]) {
    assert.equal(face.format, "woff2");
    assert.match(face.source, /^\/docs\/fonts\/[A-Za-z]+\.woff2$/, "Local font URLs must retain the documentation mount");
    const bytes = await readFile(`web${face.source}`);
    assert.equal(bytes.subarray(0, 4).toString(), "wOF2");
    assert.ok(bytes.length > 1000);
  }
  for (const name of ["Calistoga", "HankenGrotesk"]) {
    assert.equal(await read(`web/docs/fonts/${name}-OFL.txt`), await read(`landing/public/site-assets/design/fonts/${name}-OFL.txt`));
  }
});

test("documentation colors follow the homepage light and dark tokens", async () => {
  const styles = await read("landing/public/site-assets/design/tokens.css");
  const [light, dark] = styles.split(':root[data-theme="dark"]');
  const token = (scope, role) => scope.match(new RegExp(`--${role}:\\s*([^;]+);`))?.[1];
  assert.equal(config.colors.primary, token(light, "primary"));
  assert.equal(config.colors.dark, token(light, "docs-control"));
  assert.equal(config.colors.light, token(dark, "primary"));
  assert.equal(config.background?.color?.light, token(light, "surface"));
  assert.equal(config.background?.color?.dark, token(dark, "surface"));
});

test("documentation buttons remain visible in both themes with readable labels", () => {
  const luminance = hex => {
    const channels = hex.slice(1).match(/../g).map(value => Number.parseInt(value, 16) / 255)
      .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  const contrast = (first, second) => {
    const values = [luminance(first), luminance(second)].sort((a, b) => b - a);
    return (values[0] + 0.05) / (values[1] + 0.05);
  };
  for (const [theme, background] of Object.entries(config.background.color)) {
    assert.ok(contrast(config.colors.dark, background) >= 3, `Buttons need 3:1 contrast against the ${theme} background`);
  }
  assert.ok(contrast(config.colors.dark, "#ffffff") >= 4.5, "Button labels need 4.5:1 contrast");
});

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

test("published help follows current Settings labels", async () => {
  for (const page of pages) {
    assert.doesNotMatch(await read(`web/docs/${page}.mdx`), /Settings\s+→\s+Integrations|Settings\s+→\s+Enforcement|Show\s+Getting\s+Started|Enable\s+MCP\s+Control\s+Plane|Paste license key…/);
  }
  assert.match(await read("web/docs/mcp-guide.mdx"), /Allow assistants on this Mac/);
});

test("installation help retains macOS requirements and the canonical download destination", async () => {
  const content = await read("web/docs/install.mdx");
  const deployment = JSON.parse(await read("deployment/environments.json"));
  assert.match(content, /\*\*macOS 26 or later\*\*/);
  assert.ok(content.includes(`[download page](${deployment.environments.production.siteOrigin}/download)`));
});

test("setup help explains seven-day consent and the choice to leave automatic lockouts off", async () => {
  const content = await read("web/docs/install.mdx");
  assert.match(content, /all seven days/i);
  assert.match(content, /No automatic schedule — remote controls only/);
  assert.match(content, /Enable schedule and finish/);
  assert.match(content, /Settings → Warnings/);
  assert.doesNotMatch(content, /Curfew starts enforcing your schedule\./);
});

test("purchase help explains app activation, inbox restoration, and manual fallback", async () => {
  const content = await read("web/docs/licensing.mdx");
  assert.match(content, /Activate in Curfew/);
  assert.match(content, /Restore Purchase…/);
  assert.match(content, /Restore in Curfew/);
  assert.match(content, /Enter a license key/);
  assert.match(content, /Activation links and purchase restoration require an internet connection/);
  assert.match(content, /mailto:support@thecurfew\.app/);
  assert.doesNotMatch(content, /iCloud sync.*keeps your schedule in sync|Calendar.*shows today's events/);
});

test("release help requires the official app and retains restoration data sharing", async () => {
  const licensing = await read("web/docs/licensing.mdx");
  assert.match(licensing, /Activation and restore links require the\s+\[latest Curfew release\]/);
  assert.doesNotMatch(licensing, /next Curfew release adds activation and restore links/);
  for (const page of ["install", "lockout", "privacy", "troubleshooting"]) {
    assert.match(await read(`web/docs/${page}.mdx`), /General.*earlier versions/);
  }
  assert.match(await read("web/docs/privacy.mdx"), /purchase email.*license service/s);
  assert.match(licensing, /No restore email arrives/);
  assert.match(licensing, /The app does not open/);
});

test("release help uses public download and restore entry points without private checkout links", async () => {
  const licensing = await read("web/docs/licensing.mdx");
  assert.ok(licensing.includes(`](${deployment.production.siteOrigin}/download)`));
  assert.ok(licensing.includes(`](${deployment.production.siteOrigin}/restore)`));
  assert.match(licensing, /your\s+(?:purchase\s+)?confirmation page/);
  for (const page of pages) {
    const content = await read(`web/docs/${page}.mdx`);
    assert.doesNotMatch(content, /releases\/download\/untagged-|curfew-site-preview-|cs_(?:test|live)_|[?&]session_id=|#token=/);
    assert.doesNotMatch(content, /\]\(https:\/\/thecurfew\.app\/success(?:[)#])/);
  }
});
