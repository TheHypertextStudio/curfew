import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const releaseEntitlements = await readFile("Curfew/Curfew-Release.entitlements", "utf8");
const releaseWorkflow = await readFile(".github/workflows/release.yml", "utf8");
const releaseChecklist = await readFile("scripts/release-checklist.md", "utf8");
const productPlan = await readFile("Documentation/plan.md", "utf8");

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

test("v0.1 release docs match the shipping feature contract", () => {
  assert.match(productPlan, /Release status \(v0\.1\).*forward-looking/s);
  assert.match(
    productPlan,
    /includes\s*> WidgetKit, MCP, the authenticated privileged helper, and Sparkle/s,
  );
  assert.match(
    productPlan,
    /CloudKit and\s*> Calendar remain compiled but dormant/s,
  );
  assert.match(releaseChecklist, /Generates and attaches a signed appcast/);
});
