import test from "node:test";
import assert from "node:assert/strict";
import { preparePagesDomain } from "./pages-domain.mjs";

const host = "product.example";
const options = { siteOrigin: `https://${host}`, project: "existing-site" };
function fixture(existing = []) {
  const calls = [];
  const invoke = (args) => {
    calls.push(args);
    if (args[2] === "list") return existing;
    return { name: host, status: "pending" };
  };
  return { calls, invoke };
}

test("status only inspects the existing project without attaching a host", () => {
  const { calls, invoke } = fixture();
  assert.deepEqual(
    preparePagesDomain(invoke, { ...options, action: "status" }),
    {
      hostname: host,
      status: "absent",
      changed: false,
    },
  );
  assert.equal(calls.length, 1);
});

test("preview validates creation through cf without applying it", () => {
  const { calls, invoke } = fixture();
  assert.equal(
    preparePagesDomain(invoke, { ...options, action: "preview" }).status,
    "preview",
  );
  assert.deepEqual(calls[1], [
    "pages",
    "domains",
    "create",
    "existing-site",
    "--name",
    host,
    "--dry-run",
  ]);
});

test("attach preserves existing domains and reads the new host back", () => {
  const { calls, invoke } = fixture([
    { name: "previous.example", status: "active" },
  ]);
  assert.deepEqual(
    preparePagesDomain(invoke, { ...options, action: "attach" }),
    {
      hostname: host,
      status: "pending",
      changed: true,
    },
  );
  assert.deepEqual(
    calls.map((args) => args[2]),
    ["list", "create", "get"],
  );
  assert.deepEqual(calls[2], [
    "pages",
    "domains",
    "get",
    host,
    "--project-name",
    "existing-site",
  ]);
});

test("reruns read an attached host without creating or deleting domains", () => {
  const { calls, invoke } = fixture([{ name: host, status: "active" }]);
  assert.equal(
    preparePagesDomain(invoke, { ...options, action: "attach" }).changed,
    false,
  );
  assert.deepEqual(
    calls.map((args) => args[2]),
    ["list", "get"],
  );
});

test("a second configured domain needs no code changes", () => {
  const { calls, invoke } = fixture();
  const result = preparePagesDomain(invoke, {
    ...options,
    siteOrigin: "https://other.example",
    action: "preview",
  });
  assert.equal(result.hostname, "other.example");
  assert.ok(calls[1].includes("other.example"));
});

test("invalid origins and unknown actions fail before any provider operation", () => {
  for (const siteOrigin of [
    "http://product.example",
    "https://product.example/path",
    "https://user@product.example",
    "https://product.example?x=1",
  ]) {
    assert.throws(() =>
      preparePagesDomain(() => assert.fail("provider called"), {
        ...options,
        siteOrigin,
        action: "attach",
      }),
    );
  }
  assert.throws(() =>
    preparePagesDomain(() => assert.fail("provider called"), {
      ...options,
      action: "delete",
    }),
  );
});

test("provider failures and mismatched readback never report activation", () => {
  assert.throws(
    () =>
      preparePagesDomain(
        () => {
          throw new Error("403");
        },
        { ...options, action: "attach" },
      ),
    /403/,
  );
  assert.throws(
    () =>
      preparePagesDomain(
        (args) =>
          args[2] === "list" ? [] : { name: "wrong.example", status: "active" },
        { ...options, action: "attach" },
      ),
    /readback/,
  );
});
