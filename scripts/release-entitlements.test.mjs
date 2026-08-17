import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const releaseEntitlements = await readFile("Curfew/Curfew-Release.entitlements", "utf8");
const releaseWorkflow = await readFile(".github/workflows/release.yml", "utf8");
const ciWorkflow = await readFile(".github/workflows/ci.yml", "utf8");
const releaseChecklist = await readFile("scripts/release-checklist.md", "utf8");
const productPlan = await readFile("Documentation/plan.md", "utf8");
const screenshotExtractor = await readFile("scripts/extract-screenshots.sh", "utf8");

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

test("v0.1 release docs distinguish the current core-only launch from future sync and updater work", () => {
  assert.match(productPlan, /Release status \(v0\.1\).*forward-looking/s);
  assert.match(
    productPlan,
    /CloudKit, WidgetKit, Calendar, privileged-helper,\s*> and Sparkle features are deferred/s,
  );
  assert.match(
    releaseChecklist,
    /If \(and only if\) a later release enables Sparkle, publish its generated\s+`appcast\.xml`/,
  );
});

test("CI screenshot capture forwards its unsigned build settings to Xcode", () => {
  assert.match(
    ciWorkflow,
    /- name: Capture demo screenshots\n\s+env:\n\s+CURFEW_XCODEBUILD_SETTINGS: "CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO"\n\s+run: just capture/,
  );
  assert.match(screenshotExtractor, /\$\{CURFEW_XCODEBUILD_SETTINGS:-\}/);
});

test("CI preserves the unit-test result bundle when the check fails", () => {
  assert.match(
    ciWorkflow,
    /- name: Upload unit-test diagnostics\n\s+if: failure\(\)\n\s+uses: actions\/upload-artifact@v4\n\s+with:\n\s+name: curfew-unit-test-results\n\s+path: build\/CurfewTests\.xcresult/,
  );
});
