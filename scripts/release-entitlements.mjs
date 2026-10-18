import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const team = "T95VDD3A4W";

export function validateReleaseEntitlements(actual, expected) {
  for (const [key, value] of Object.entries({
    "com.apple.application-identifier": `${team}.studio.hypertext.apps.curfew`,
    "com.apple.developer.team-identifier": team,
  })) {
    if (Object.hasOwn(actual, key)) assert.equal(actual[key], value, key);
  }
  const normalized = { ...actual };
  delete normalized["com.apple.application-identifier"];
  delete normalized["com.apple.developer.team-identifier"];
  const resolved = {
    ...expected,
    "keychain-access-groups": expected["keychain-access-groups"].map((group) =>
      group.replaceAll("$(AppIdentifierPrefix)", `${team}.`),
    ),
  };
  assert.deepEqual(normalized, resolved, "Release entitlements differ");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [actual, expected] = process.argv.slice(2);
  assert.ok(actual && expected, "Actual and source entitlements are required");
  const readPlist = (path) => JSON.parse(execFileSync("plutil", [
    "-convert", "json", "-o", "-", path,
  ], { encoding: "utf8" }));
  validateReleaseEntitlements(readPlist(actual), readPlist(expected));
  console.log("Release entitlements verified");
}
