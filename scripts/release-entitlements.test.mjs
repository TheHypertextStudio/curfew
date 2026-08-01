import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const releaseEntitlements = await readFile("Curfew/Curfew-Release.entitlements", "utf8");
const releaseWorkflow = await readFile(".github/workflows/release.yml", "utf8");

test("conservative initial Release keeps only the signed core entitlements", () => {
  assert.match(releaseEntitlements, /com\.apple\.security\.automation\.apple-events/);
  assert.match(releaseEntitlements, /group\.studio\.hypertext\.curfew/);
  assert.doesNotMatch(releaseEntitlements, /com\.apple\.developer\.icloud-/);
  assert.doesNotMatch(releaseEntitlements, /aps-environment/);
});

test("release guard inspects the active Curfew Plus verifier", () => {
  assert.match(releaseWorkflow, /configuredPublicKeyBase64/);
  assert.doesNotMatch(releaseWorkflow, /licensePublicKeyBase64/);
});

test("unprovisioned Sparkle releases upload only the generated DMG", () => {
  assert.match(
    releaseWorkflow,
    /files: \|\n\s+\$\{\{ runner\.temp \}\}\/Curfew-\$\{\{ github\.ref_name \}\}\.dmg/,
  );
  assert.doesNotMatch(releaseWorkflow, /\$\{\{ runner\.temp \}\}\/appcast\.xml/);
});
