import assert from "node:assert/strict";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { selectProfile } from "./configure-ci-display.mjs";

test("CI display chooses an advertised mode that fits default app windows", () => {
  const listing = `Persistent screen id: runner-display
Resolution: 1024x768
  mode 0: res:1024x768 hz:60 color_depth:8 scaling:off
  mode 1: res:1440x900 hz:60 color_depth:8 scaling:off
  mode 2: res:1920x1080 hz:60 color_depth:8 scaling:off`;
  assert.equal(selectProfile(listing), "id:runner-display mode:1 origin:(0,0) degree:0");
});

test("CI display fails instead of accepting a screen that crops default windows", () => {
  assert.throws(() => selectProfile("Persistent screen id: runner\n  mode 0: res:1024x768"), /fit/);
  assert.throws(() => selectProfile(""), /display/);
});

test("display configuration refuses to run on the local Mac", () => {
  const result = spawnSync(process.execPath, ["scripts/configure-ci-display.mjs"], {
    encoding: "utf8", env: { ...process.env, GITHUB_ACTIONS: "false" }
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /restricted to isolated GitHub runners/);
});
