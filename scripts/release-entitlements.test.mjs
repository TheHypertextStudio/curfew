import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const releaseEntitlements = await readFile("Curfew/Curfew-Release.entitlements", "utf8");
const releaseWorkflow = await readFile(".github/workflows/release.yml", "utf8");
const ciWorkflow = await readFile(".github/workflows/ci.yml", "utf8");
const releaseChecklist = await readFile("scripts/release-checklist.md", "utf8");
const productPlan = await readFile("Documentation/plan.md", "utf8");
const screenshotExtractor = await readFile("scripts/extract-screenshots.sh", "utf8");
const projectFile = await readFile("Curfew.xcodeproj/project.pbxproj", "utf8");
const homebrewCask = await readFile("Casks/curfew.rb", "utf8");

function buildConfigurationBlock(id, name) {
  const marker = `\t\t${id} /* ${name} */ = {`;
  const start = projectFile.indexOf(marker);
  assert.notEqual(start, -1, `missing ${name} build configuration ${id}`);
  const end = projectFile.indexOf("\n\t\t};", start);
  assert.notEqual(end, -1, `unterminated ${name} build configuration ${id}`);
  return projectFile.slice(start, end + "\n\t\t};".length);
}

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

test("unsigned CI builds skip embedded tool signing", () => {
  assert.match(projectFile, /CODE_SIGNING_ALLOWED.*NO/);
  assert.match(projectFile, /EXPANDED_CODE_SIGN_IDENTITY/);
});

test("interactive builds reject an unresolved signing identity before TCC can mislead", () => {
  assert.match(
    projectFile,
    /CODE_SIGNING_ALLOWED[^]*EXPANDED_CODE_SIGN_IDENTITY[^]*requires a resolved Apple Development certificate/,
  );
  assert.doesNotMatch(
    projectFile,
    /if \[\[ \\"\$CODE_SIGN_IDENTITY\" == \\"-\" \]\]/,
  );
  const buildPhases = projectFile.indexOf("buildPhases = (");
  const signedBuildGuard = projectFile.indexOf(
    "C0FE0000000000000000ABCD /* Require Signed Build */",
    buildPhases,
  );
  const bundleTools = projectFile.indexOf(
    "9BD3FBCC2F4D4584007B2E95 /* Bundle CLI Tools */",
    buildPhases,
  );
  assert.ok(signedBuildGuard >= 0 && bundleTools >= 0);
  assert.ok(signedBuildGuard < bundleTools);
});

test("a staging build compiles the app and every embedded tool for the same service boundary", () => {
  const projectDebug = buildConfigurationBlock("9BD3FBA32F4D4587007B2E95", "Debug");
  const projectStudioDev = buildConfigurationBlock("C0FE00000000000000000310", "StudioDev");
  const projectRelease = buildConfigurationBlock("9BD3FBA42F4D4587007B2E95", "Release");
  const appRelease = buildConfigurationBlock("9BD3FBA72F4D4587007B2E95", "Release");
  assert.match(
    projectDebug,
    /SWIFT_ACTIVE_COMPILATION_CONDITIONS = "[^"]*\$\(CURFEW_SERVICE_SWIFT_FLAG\)[^"]*";/,
  );
  assert.match(projectDebug, /CURFEW_SERVICE_SWIFT_FLAG = CURFEW_STAGING;/);
  assert.match(
    projectStudioDev,
    /SWIFT_ACTIVE_COMPILATION_CONDITIONS = "[^"]*\$\(CURFEW_SERVICE_SWIFT_FLAG\)[^"]*";/,
  );
  assert.match(projectStudioDev, /CURFEW_SERVICE_SWIFT_FLAG = CURFEW_STAGING;/);
  assert.doesNotMatch(projectRelease, /CURFEW_SERVICE_SWIFT_FLAG/);
  assert.doesNotMatch(appRelease, /CURFEW_SERVICE_SWIFT_FLAG/);
  assert.match(projectFile, /SWIFT_SERVICE_FLAGS=.*-Xswiftc -DCURFEW_STAGING/);
  assert.match(projectFile, /swift build -c release --jobs 2 --product curfew-daemon \$SWIFT_SERVICE_FLAGS/);
  assert.match(projectFile, /if \[ \\"\$CONFIGURATION\\" != \\"Debug\\" \]/);
  assert.match(projectFile, /CURFEW_STAGING requires an isolated Debug or StudioDev app and helper identity/);
  assert.match(projectFile, /CURFEW_DAEMON_PLIST_NAME/);
});

test("every user-facing release version is the same 0.0.x version", () => {
  const marketingVersions = [
    ...projectFile.matchAll(/MARKETING_VERSION = (\d+\.\d+\.\d+);/g),
  ].map((match) => match[1]);
  const caskVersion = /version "(\d+\.\d+\.\d+)"/.exec(homebrewCask)?.[1];

  assert.ok(marketingVersions.length > 0, "Xcode must declare a marketing version");
  assert.equal(new Set(marketingVersions).size, 1, "all Xcode targets must agree");
  assert.match(marketingVersions[0], /^0\.0\.\d+$/);
  assert.equal(caskVersion, marketingVersions[0]);
});
