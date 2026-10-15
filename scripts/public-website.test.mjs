import assert from "node:assert/strict";
import test from "node:test";
import {
  mkdtemp,
  mkdir,
  readFile,
  writeFile,
  rm,
  access,
} from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createArtifact } from "./deployment-config.mjs";
import { sealWebsite } from "./pages-artifact.mjs";

async function fixture(t) {
  const base = await mkdtemp(join(tmpdir(), "curfew-public-website-"));
  t.after(() => rm(base, { recursive: true, force: true }));
  const directory = join(base, "website");
  await mkdir(join(directory, "_worker.js"), { recursive: true });
  await writeFile(
    join(directory, "index.html"),
    '<a href="/account">Account</a><a href="https://github.com/TheHypertextStudio/curfew/releases/latest">Download</a>',
  );
  await writeFile(join(directory, "_worker.js/index.js"), "export default {}");
  await writeFile(
    join(directory, "_routes.json"),
    '{"version":1,"include":["/*"],"exclude":[]}',
  );
  const deployment = createArtifact(
    {
      version: 1,
      environments: {
        production: {
          siteOrigin: "https://new.example",
          legacySiteOrigin: "https://old.example",
          accountOrigin: "https://account.new.example",
          syncOrigin: "https://sync.new.example",
          licenseOrigin: "https://license.new.example",
          passkeyRPID: "new.example",
          recoveryEmailFrom: "accounts@new.example",
        },
      },
    },
    "a".repeat(40),
  );
  return {
    website: {
      directory,
      deployment,
      stamp: await sealWebsite(directory, deployment),
    },
    websiteRun: {
      id: 123,
      repository: { full_name: "TheHypertextStudio/curfew" },
      status: "completed",
      conclusion: "success",
      event: "push",
      path: ".github/workflows/website.yml",
      head_branch: "main",
      head_sha: "a".repeat(40),
    },
    currentMainCommit: "a".repeat(40),
    destination: join(base, "ready"),
    domains: ["new.example", "old.example"].map((name) => ({
      name,
      status: "active",
    })),
  };
}
async function api() {
  const value = await import("./public-website.mjs").catch(() => null);
  assert.equal(
    typeof value?.preparePublicWebsite,
    "function",
    "Public website publication must be independent of a signed native candidate",
  );
  return value;
}
const feed =
  '<?xml version="1.0"?><rss><channel><item><enclosure url="https://github.com/TheHypertextStudio/curfew/releases/download/v0.0.1/Curfew.dmg" sparkle:edSignature="existing-signature"/></item></channel></rss>';
function network(feedResponse = () => new Response(feed)) {
  return async (url, options) => {
    assert.equal(options.redirect, "manual");
    if (url === "https://new.example/appcast.xml") return feedResponse();
    if (url === "https://new.example" || url === "https://old.example/account")
      return new Response("existing site or account");
    throw new Error("Unexpected cross-service access: " + url);
  };
}

test("public-only publication retains native update bytes and uses the existing account portal", async (t) => {
  const input = await fixture(t);
  const { preparePublicWebsite } = await api();
  const result = await preparePublicWebsite(input, network());
  assert.equal(
    await readFile(join(input.destination, "appcast.xml"), "utf8"),
    feed,
  );
  assert.equal(
    await readFile(join(input.destination, "index.html"), "utf8"),
    '<a href="https://old.example/account">Account</a><a href="https://github.com/TheHypertextStudio/curfew/releases/latest">Download</a>',
  );
  assert.equal(
    await readFile(join(input.destination, "_worker.js/retained.js"), "utf8"),
    "export default {}",
  );
  assert.equal(
    await readFile(join(input.website.directory, "index.html"), "utf8"),
    '<a href="/account">Account</a><a href="https://github.com/TheHypertextStudio/curfew/releases/latest">Download</a>',
  );
  assert.equal(result.feed.status, 200);
  assert.equal(result.accountPortal, "https://old.example/account");
});

test("a site with no published appcast does not invent an app release", async (t) => {
  const input = await fixture(t);
  const { preparePublicWebsite } = await api();
  const result = await preparePublicWebsite(
    input,
    network(() => new Response("missing", { status: 404 })),
  );
  await assert.rejects(() => access(join(input.destination, "appcast.xml")), {
    code: "ENOENT",
  });
  assert.deepEqual(result.feed, { status: 404 });
});

test("unverified website source, failed checks, changed main and inactive domains stop publication", async (t) => {
  const { preparePublicWebsite } = await api();
  for (const mutate of [
    (input) => {
      input.currentMainCommit = "b".repeat(40);
    },
    (input) => {
      input.websiteRun.conclusion = "failure";
    },
    (input) => {
      input.websiteRun.event = "pull_request";
    },
    (input) => {
      input.websiteRun.repository.full_name = "someone/curfew";
    },
    (input) => {
      input.domains[0].status = "pending";
    },
    (input) =>
      writeFile(join(input.website.directory, "index.html"), "unverified"),
  ]) {
    const input = await fixture(t);
    await mutate(input);
    await assert.rejects(() => preparePublicWebsite(input, network()));
    await assert.rejects(() => access(input.destination), { code: "ENOENT" });
  }
});

test("feed failures and redirects cannot silently delete or replace native updates", async (t) => {
  const { preparePublicWebsite } = await api();
  for (const response of [
    () => new Response("failed", { status: 500 }),
    () =>
      new Response("", {
        status: 302,
        headers: { location: "https://elsewhere.example/feed" },
      }),
    () => new Response("<html>fallback</html>"),
  ]) {
    const input = await fixture(t);
    await assert.rejects(() => preparePublicWebsite(input, network(response)));
    await assert.rejects(() => access(input.destination), { code: "ENOENT" });
  }
});

test("the public phase stops if the existing account portal is unavailable", async (t) => {
  const input = await fixture(t);
  const { preparePublicWebsite } = await api();
  await assert.rejects(() =>
    preparePublicWebsite(input, async (url, options) =>
      url === "https://old.example/account"
        ? new Response("unavailable", { status: 503 })
        : network()(url, options),
    ),
  );
  await assert.rejects(() => access(input.destination), { code: "ENOENT" });
});

test("live public cutover verifies canonical content, redirects, the preserved feed and old account access", async (t) => {
  const input = await fixture(t);
  const { preparePublicWebsite, verifyPublicWebsite } = await api();
  const result = await preparePublicWebsite(input, network());
  const live = async (url, options) => {
    if (url === "https://new.example")
      return new Response('<link rel="canonical" href="https://new.example/">');
    if (url === "https://old.example/download?curfew_migration_check=1")
      return new Response(null, {
        status: 308,
        headers: {
          location: "https://new.example/download?curfew_migration_check=1",
        },
      });
    return network()(url, options);
  };
  await verifyPublicWebsite(input.website.deployment, result, live);
  await assert.rejects(() =>
    verifyPublicWebsite(
      input.website.deployment,
      result,
      async (url, options) =>
        url === "https://new.example/appcast.xml"
          ? new Response(feed + "changed")
          : live(url, options),
    ),
  );
  await assert.rejects(() =>
    verifyPublicWebsite(
      input.website.deployment,
      result,
      async (url, options) =>
        url.startsWith("https://old.example/download")
          ? new Response("old site")
          : live(url, options),
    ),
  );
});

test("live verification accepts the static homepage canonical and rejects another domain", async (t) => {
  const input = await fixture(t);
  const { preparePublicWebsite, verifyPublicWebsite } = await api();
  const publication = await preparePublicWebsite(input, network());
  const live = (canonical) => async (url, options) => {
    if (url === "https://new.example")
      return new Response(`<link rel="canonical" href="${canonical}">`);
    if (url === "https://old.example/download?curfew_migration_check=1")
      return new Response(null, {
        status: 308,
        headers: {
          location: "https://new.example/download?curfew_migration_check=1",
        },
      });
    return network()(url, options);
  };
  await verifyPublicWebsite(
    input.website.deployment,
    publication,
    live("https://new.example/index.html"),
  );
  await assert.rejects(() =>
    verifyPublicWebsite(
      input.website.deployment,
      publication,
      live("https://old.example/index.html"),
    ),
  );
});

test("the retained public worker enables only the public phase while preserving request and bindings", async (t) => {
  const input = await fixture(t);
  await writeFile(
    join(input.website.directory, "_worker.js/index.js"),
    "export default {fetch(request, env) {return Response.json({phase: env.CURFEW_PUBLIC_SITE_ONLY ?? null, mode: env.DOCS_MODE, url: request.url})}}",
  );
  input.website.stamp = await sealWebsite(
    input.website.directory,
    input.website.deployment,
  );
  const { preparePublicWebsite } = await api();
  await preparePublicWebsite(input, network());
  const { default: worker } = await import(
    join(input.destination, "_worker.js/index.js")
  );
  const response = await worker.fetch(
    new Request("https://old.example/success?session_id=existing"),
    { DOCS_MODE: "mintlify" },
    {},
  );
  assert.deepEqual(await response.json(), {
    phase: "true",
    mode: "mintlify",
    url: "https://old.example/success?session_id=existing",
  });
});

test("publication verification waits for edge propagation without repeating publication", async (t) => {
  const input = await fixture(t);
  const { preparePublicWebsite, waitForPublicWebsite } = await api();
  assert.equal(
    typeof waitForPublicWebsite,
    "function",
    "Publication must tolerate a stale edge response after upload",
  );
  const publication = await preparePublicWebsite(input, network());
  let time = 0,
    homepages = 0;
  const pauses = [];
  const fetcher = async (url, options) => {
    if (url === "https://new.example")
      return new Response(
        `<link rel="canonical" href="${++homepages === 1 ? "https://old.example/" : "https://new.example/"}">`,
      );
    if (url === "https://old.example/download?curfew_migration_check=1")
      return new Response(null, {
        status: 308,
        headers: {
          location: "https://new.example/download?curfew_migration_check=1",
        },
      });
    return network()(url, options);
  };
  await waitForPublicWebsite(input.website.deployment, publication, {
    fetcher,
    now: () => time,
    pause: async (milliseconds) => {
      pauses.push(milliseconds);
      time += milliseconds;
    },
    timeoutMs: 20,
    intervalMs: 5,
  });
  assert.equal(homepages, 2);
  assert.deepEqual(pauses, [5]);
});

test("a persistent publication mismatch fails at the verification deadline", async (t) => {
  const input = await fixture(t);
  const { preparePublicWebsite, waitForPublicWebsite } = await api();
  assert.equal(
    typeof waitForPublicWebsite,
    "function",
    "Propagation waiting must remain bounded and fail closed",
  );
  const publication = await preparePublicWebsite(input, network());
  let time = 0,
    homepages = 0;
  await assert.rejects(
    () =>
      waitForPublicWebsite(input.website.deployment, publication, {
        fetcher: async () => {
          homepages++;
          return new Response(
            '<link rel="canonical" href="https://old.example/">',
          );
        },
        now: () => time,
        pause: async (milliseconds) => {
          time += milliseconds;
        },
        timeoutMs: 10,
        intervalMs: 5,
      }),
    /Homepage must identify the new canonical domain/,
  );
  assert.equal(time, 10);
  assert.equal(homepages, 2);
});
