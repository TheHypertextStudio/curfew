import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { spawnSync } from "node:child_process";

const releaseEntitlements = await readFile("Curfew/Curfew-Release.entitlements", "utf8");
const releaseWorkflow = await readFile("Documentation/legacy-release/release.yml.disabled", "utf8");
const releaseChecklist = await readFile("scripts/release-checklist.md", "utf8");
const productPlan = await readFile("Documentation/plan.md", "utf8");
const projectFile = await readFile("Curfew.xcodeproj/project.pbxproj", "utf8");
const homebrewCask = await readFile("Casks/curfew.rb", "utf8");

const projectResult = spawnSync("plutil", ["-convert", "json", "-o", "-", "Curfew.xcodeproj/project.pbxproj"], { encoding: "utf8" });
assert.equal(projectResult.status, 0, projectResult.stderr);
const objects = JSON.parse(projectResult.stdout).objects;

function buildConfiguration(id, name) {
  const configuration = objects[id];
  assert.equal(configuration?.name, name, `missing ${name} build configuration ${id}`);
  return configuration.buildSettings;
}

test("conservative initial Release keeps only the signed core entitlements", () => {
  assert.match(releaseEntitlements, /com\.apple\.security\.automation\.apple-events/);
  assert.match(releaseEntitlements, /group\.studio\.hypertext\.curfew/);
  assert.doesNotMatch(releaseEntitlements, /com\.apple\.developer\.icloud-/);
  assert.doesNotMatch(releaseEntitlements, /aps-environment/);
});

test("archived release guard inspects the active Curfew Plus verifier", () => {
  assert.match(releaseWorkflow, /configuredPublicKeyBase64/);
  assert.doesNotMatch(releaseWorkflow, /licensePublicKeyBase64/);
});

test("archived unprovisioned Sparkle releases upload only the generated DMG", () => {
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

test("native licensing acceptance rejects an unconfigured release verifier", async () => {
  const licenseSource = await readFile("Curfew/Core/Features/LicenseGate.swift", "utf8");
  const configured = /configuredPublicKeyBase64\s*=\s*"([^"]+)"/.exec(licenseSource)?.[1];
  assert.ok(configured, "missing active license public key");
  const bytes = Buffer.from(configured, "base64");
  assert.equal(bytes.length, 32);
  assert.ok(bytes.some(byte => byte !== 0), "placeholder license key blocks release");
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
  const buildPhases = objects["9BD3FB812F4D4584007B2E95"].buildPhases;
  const signedBuildGuard = buildPhases.indexOf("C0FE0000000000000000ABCD");
  const bundleTools = buildPhases.indexOf("9BD3FBCC2F4D4584007B2E95");
  assert.ok(signedBuildGuard >= 0 && bundleTools >= 0);
  assert.ok(signedBuildGuard < bundleTools);
});

test("a staging build compiles the app and every embedded tool for the same service boundary", () => {
  const projectDebug = buildConfiguration("9BD3FBA32F4D4587007B2E95", "Debug");
  const projectRelease = buildConfiguration("9BD3FBA42F4D4587007B2E95", "Release");
  const appRelease = buildConfiguration("9BD3FBA72F4D4587007B2E95", "Release");
  assert.ok(projectDebug.SWIFT_ACTIVE_COMPILATION_CONDITIONS.includes("$(CURFEW_SERVICE_SWIFT_FLAG)"));
  assert.equal(projectDebug.CURFEW_SERVICE_SWIFT_FLAG, "CURFEW_STAGING");
  assert.equal(projectRelease.CURFEW_SERVICE_SWIFT_FLAG, undefined);
  assert.equal(appRelease.CURFEW_SERVICE_SWIFT_FLAG, undefined);
  assert.match(projectFile, /SWIFT_SERVICE_FLAGS=.*-Xswiftc -DCURFEW_STAGING/);
  assert.match(projectFile, /swift build -c release --jobs 2 --product curfew-daemon \$SWIFT_SERVICE_FLAGS/);
  assert.match(projectFile, /if \[ \\"\$CONFIGURATION\\" != \\"Debug\\" \]/);
  assert.match(projectFile, /CURFEW_STAGING requires the isolated Debug app and helper identity/);
  assert.match(projectFile, /CURFEW_DAEMON_PLIST_NAME/);
});

test("every user-facing release version is the same 0.0.x version", () => {
  const marketingVersions = Object.values(objects)
    .filter(object => object.isa === "XCBuildConfiguration")
    .map(object => object.buildSettings.MARKETING_VERSION)
    .filter(Boolean);
  const caskVersion = /version "(\d+\.\d+\.\d+)"/.exec(homebrewCask)?.[1];

  assert.ok(marketingVersions.length > 0, "Xcode must declare a marketing version");
  assert.equal(new Set(marketingVersions).size, 1, "all Xcode targets must agree");
  assert.match(marketingVersions[0], /^0\.0\.\d+$/);
  assert.equal(caskVersion, marketingVersions[0]);
});

test("the shared scheme keeps the UI capture suite available", async () => {
  const scheme = await readFile("Curfew.xcodeproj/xcshareddata/xcschemes/Curfew.xcscheme", "utf8");
  const testables = /<Testables>([\s\S]*?)<\/Testables>/.exec(scheme)?.[1];
  assert.ok(testables, "the scheme must expose native test targets");
  assert.match(testables, /BlueprintName="CurfewTests"/);
  assert.match(testables, /BlueprintName="CurfewUITests"/);
});
