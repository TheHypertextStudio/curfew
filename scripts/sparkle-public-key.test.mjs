import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";

// RFC 8032, section 7.1, test 1. This is published test material.
const seed = Buffer.from("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", "hex").toString("base64");
const publicKey = Buffer.from("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "hex").toString("base64");

function derive(value) {
  return spawnSync(process.execPath, ["scripts/sparkle-public-key.mjs"], {
    encoding: "utf8",
    env: { PATH: process.env.PATH, SPARKLE_PRIVATE_KEY: value },
  });
}

test("derives the public key from a known Ed25519 seed without printing the seed", () => {
  const result = derive(seed);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `${publicKey}\n`);
  assert.equal(result.stderr, "");
  assert.ok(!result.stdout.includes(seed));
});

for (const [name, value] of [
  ["missing", ""],
  ["wrong length", Buffer.alloc(31).toString("base64")],
  ["invalid base64", `${seed}!`],
]) {
  test(`rejects a ${name} signing seed without disclosing it`, () => {
    const result = derive(value);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /SPARKLE_PRIVATE_KEY must be a base64-encoded 32-byte Ed25519 seed/);
    if (value) assert.ok(!result.stderr.includes(value));
  });
}
