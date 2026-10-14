import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";

test("Cloudflare inventory uses read-only operations and emits selected metadata only", async () => {
  const { collectInventory } = await import("./cloudflare-inventory.mjs");
  const calls = [];
  const output = collectInventory((args) => {
    calls.push(args);
    return {
      status: 0,
      stdout: JSON.stringify([
        { name: "public-name", status: "active", secret: "DO-NOT-LOG" },
      ]),
    };
  }, "example.test");
  assert.ok(
    calls.some((args) => args.join(" ").includes("pages domains list")),
  );
  assert.ok(
    calls.some((args) => args.join(" ").includes("workers secrets list")),
  );
  assert.ok(calls.every((args) => args.includes("list")));
  assert.ok(!JSON.stringify(output).includes("DO-NOT-LOG"));
});

test("permission failures do not hide independent inventory or expose CLI output", async () => {
  const { collectInventory } = await import("./cloudflare-inventory.mjs");
  let calls = 0;
  const output = collectInventory(
    () =>
      ++calls === 1
        ? {
            status: 1,
            stderr: "HTTP 403 secret=DO-NOT-LOG",
            stdout: "DO-NOT-LOG",
          }
        : { status: 0, stdout: "[]" },
    "example.test",
  );
  assert.equal(output[0].status, "unavailable");
  assert.equal(output[0].httpStatus, "403");
  assert.ok(output.some((item) => item.status === "available"));
  assert.ok(!JSON.stringify(output).includes("DO-NOT-LOG"));
});

test("CI inventories Cloudflare with the pinned CLI and existing secrets", async () => {
  const workflow = await readFile(".github/workflows/website.yml", "utf8");
  assert.ok(workflow.includes("node scripts/cloudflare-inventory.mjs"));
  assert.ok(
    workflow.includes(
      "github.event.pull_request.head.repo.full_name == github.repository",
    ),
  );
});
