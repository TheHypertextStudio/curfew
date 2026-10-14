import assert from "node:assert/strict";
import test from "node:test";
import { access } from "node:fs/promises";
import deployment from "../deployment/generated/environments.mjs";

async function handler() {
  const bundle = new URL(
    "../landing/dist/_worker.js/index.js",
    import.meta.url,
  );
  await assert.doesNotReject(
    () => access(bundle),
    "The validated website must include its compiled redirect middleware",
  );
  return (await import(bundle.href)).default;
}
const context = { waitUntil() {} };
test("the compiled Pages artifact redirects public paths and retires sensitive traffic", async () => {
  const worker = await handler();
  const config = deployment.production;
  const env = { ASSETS: { fetch: () => new Response("static content") } };
  const publicResponse = await worker.fetch(
    new Request(`${config.legacySiteOrigin}/download?from=guide`),
    env,
    context,
  );
  assert.equal(publicResponse.status, 308);
  assert.equal(
    publicResponse.headers.get("location"),
    `${config.siteOrigin}/download?from=guide`,
  );
  for (const path of [
    "/api/auth/callback/google?code=private",
    "/oauth/authorize",
    "/download?access_token=private",
  ]) {
    const response = await worker.fetch(
      new Request(`${config.legacySiteOrigin}${path}`),
      env,
      context,
    );
    assert.equal(response.status, 410);
    assert.equal(response.headers.get("location"), null);
  }
  const current = await worker.fetch(
    new Request(`${config.siteOrigin}/download`),
    env,
    context,
  );
  assert.equal(await current.text(), "static content");
});
test("the compiled Pages artifact preserves the selected documentation mode", async (t) => {
  const worker = await handler();
  const originalFetch = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
  let upstream;
  globalThis.fetch = async (request) => {
    upstream = request;
    return new Response("documentation");
  };
  const env = { ASSETS: { fetch: () => new Response("HTML guide") } };
  const request = new Request(
    `${deployment.production.siteOrigin}/docs/mcp?source=guide`,
  );
  assert.equal(
    await (await worker.fetch(request, env, context)).text(),
    "HTML guide",
  );
  assert.equal(upstream, undefined);
  assert.equal(
    await (
      await worker.fetch(request, { ...env, DOCS_MODE: "mintlify" }, context)
    ).text(),
    "documentation",
  );
  assert.equal(
    upstream.url,
    "https://curfew.mintlify.site/docs/mcp-guide?source=guide",
  );
  assert.equal(
    upstream.headers.get("x-forwarded-host"),
    new URL(deployment.production.siteOrigin).host,
  );
});
