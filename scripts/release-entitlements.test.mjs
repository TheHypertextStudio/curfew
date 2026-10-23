import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { execFileSync } from "node:child_process";
import { validateReleaseEntitlements } from "./release-entitlements.mjs";

const releaseEntitlements = await readFile(
  "Curfew/Curfew-Release.entitlements",
  "utf8",
);
const releaseWorkflow = await readFile(".github/workflows/release.yml", "utf8");
const ciWorkflow = await readFile(".github/workflows/ci.yml", "utf8");
const releaseChecklist = await readFile("scripts/release-checklist.md", "utf8");
const productPlan = await readFile("Documentation/plan.md", "utf8");
const screenshotExtractor = await readFile(
  "scripts/extract-screenshots.sh",
  "utf8",
);
const projectFile = await readFile("Curfew.xcodeproj/project.pbxproj", "utf8");
const toolBundler = await readFile("scripts/bundle-cli-tools.sh", "utf8");
const packageManifest = await readFile("CurfewKit/Package.swift", "utf8");
const homebrewCask = await readFile("Casks/curfew.rb", "utf8");
const artifactVerifier = await readFile(
  "scripts/verify-release-artifact.sh",
  "utf8",
);

function buildConfigurationBlock(id, name) {
  const marker = `\t\t${id} /* ${name} */ = {`;
  const start = projectFile.indexOf(marker);
  assert.notEqual(start, -1, `missing ${name} build configuration ${id}`);
  const end = projectFile.indexOf("\n\t\t};", start);
  assert.notEqual(end, -1, `unterminated ${name} build configuration ${id}`);
  return projectFile.slice(start, end + "\n\t\t};".length);
}

test("signed entitlements resolve the approved Keychain prefix and declared file access", () => {
  const expected = JSON.parse(execFileSync("plutil", [
    "-convert", "json", "-o", "-", "Curfew/Curfew-Release.entitlements",
  ], { encoding: "utf8" }));
  const actual = {
    ...expected,
    "keychain-access-groups": ["T95VDD3A4W.studio.hypertext.curfew"],
    "com.apple.security.files.user-selected.read-only": true,
    "com.apple.application-identifier": "T95VDD3A4W.studio.hypertext.apps.curfew",
    "com.apple.developer.team-identifier": "T95VDD3A4W",
  };
  assert.doesNotThrow(() => validateReleaseEntitlements(actual, expected));
  for (const changed of [
    { "keychain-access-groups": ["OTHERTEAM.studio.hypertext.curfew"] },
    { "com.apple.security.files.user-selected.read-write": true },
    { "com.apple.security.application-groups": ["group.unrelated"] },
    { "com.apple.developer.team-identifier": "OTHERTEAM" },
    { "com.apple.application-identifier": "T95VDD3A4W.unrelated" },
    { "com.apple.security.app-sandbox": true },
  ]) {
    assert.throws(() => validateReleaseEntitlements({ ...actual, ...changed }, expected));
  }
  const missing = { ...actual };
  delete missing["com.apple.security.files.user-selected.read-only"];
  assert.throws(() => validateReleaseEntitlements(missing, expected));
});

test("app and command-line tools pin the same exact 0.0.x protocol release", () => {
  const swiftPin = packageManifest.match(
    /curfew-protocols\.git"[\s\S]*?exact: "(0\.0\.\d+)"/,
  );
  const xcodePin = projectFile.match(
    /repositoryURL = "https:\/\/github\.com\/TheHypertextStudio\/curfew-protocols\.git";[\s\S]*?version = (0\.0\.\d+);/,
  );
  assert.ok(swiftPin, "Swift package protocol pin missing");
  assert.ok(xcodePin, "Xcode protocol pin missing");
  assert.equal(xcodePin[1], swiftPin[1]);
  assert.match(
    swiftPin[1],
    /^0\.0\.\d+$/,
    "protocol consumers must remain on exact 0.0.x releases",
  );
  assert.equal(
    swiftPin[1],
    "0.0.13",
    "candidate must consume the reviewed published protocol contract",
  );
});

test("conservative initial Release keeps only the signed core entitlements", () => {
  assert.match(
    releaseEntitlements,
    /com\.apple\.security\.automation\.apple-events/,
  );
  assert.match(releaseEntitlements, /group\.studio\.hypertext\.apps\.curfew/);
  assert.doesNotMatch(releaseEntitlements, /com\.apple\.developer\.icloud-/);
  assert.doesNotMatch(releaseEntitlements, /aps-environment/);
});

test("Release app, widget and artifact verifier use the verified Studio signing team", () => {
  for (const id of ["9BD3FBA72F4D4587007B2E95", "C0FE00000000000000000012"]) {
    assert.match(
      buildConfigurationBlock(id, "Release"),
      /DEVELOPMENT_TEAM = T95VDD3A4W;/,
    );
  }
  assert.match(artifactVerifier, /EXPECTED_TEAM="T95VDD3A4W"/);
});

test("both Release executables enable Hardened Runtime for notarization", () => {
  for (const id of ["9BD3FBA72F4D4587007B2E95", "C0FE00000000000000000012"]) {
    assert.match(
      buildConfigurationBlock(id, "Release"),
      /ENABLE_HARDENED_RUNTIME = YES;/,
      "the app and its widget must both opt into Hardened Runtime",
    );
  }
});

test("Debug test bundles are isolated beneath the development app identity", () => {
  assert.match(
    buildConfigurationBlock("9BD3FBA92F4D4587007B2E95", "Debug"),
    /PRODUCT_BUNDLE_IDENTIFIER = studio\.hypertext\.apps\.curfew\.dev\.tests;/,
  );
  assert.match(
    buildConfigurationBlock("9BD3FBAC2F4D4587007B2E95", "Debug"),
    /PRODUCT_BUNDLE_IDENTIFIER = studio\.hypertext\.apps\.curfew\.dev\.uitests;/,
  );
});

test("release guard inspects the active Curfew Plus verifier", () => {
  assert.match(releaseWorkflow, /configuredPublicKeyBase64/);
  assert.doesNotMatch(releaseWorkflow, /licensePublicKeyBase64/);
});

// Candidate retention/publication behavior is exercised by release-candidate.test.mjs.

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
    /- name: Upload unit-test diagnostics\n\s+if: failure\(\)\n\s+uses: actions\/upload-artifact@v\d+(?:\.\d+){0,2}\n\s+with:\n\s+name: curfew-unit-test-results\n\s+path: build\/CurfewTests\.xcresult/,
  );
});

test("unsigned CI builds skip embedded tool signing", () => {
  assert.match(toolBundler, /CODE_SIGNING_ALLOWED.*NO/);
  assert.match(toolBundler, /EXPANDED_CODE_SIGN_IDENTITY/);
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
  const projectDebug = buildConfigurationBlock(
    "9BD3FBA32F4D4587007B2E95",
    "Debug",
  );
  const projectRelease = buildConfigurationBlock(
    "9BD3FBA42F4D4587007B2E95",
    "Release",
  );
  const appRelease = buildConfigurationBlock(
    "9BD3FBA72F4D4587007B2E95",
    "Release",
  );
  assert.match(
    projectDebug,
    /SWIFT_ACTIVE_COMPILATION_CONDITIONS = "[^"]*\$\(CURFEW_SERVICE_SWIFT_FLAG\)[^"]*";/,
  );
  assert.match(projectDebug, /CURFEW_SERVICE_SWIFT_FLAG = CURFEW_STAGING;/);
  assert.doesNotMatch(projectRelease, /CURFEW_SERVICE_SWIFT_FLAG/);
  assert.doesNotMatch(appRelease, /CURFEW_SERVICE_SWIFT_FLAG/);
  assert.match(projectFile, /scripts\/bundle-cli-tools\.sh/);
  assert.match(toolBundler, /build_args\+=\(-Xswiftc -DCURFEW_STAGING\)/);
  assert.match(toolBundler, /if \[\[ "\$CONFIGURATION" != Debug \]\]/);
  assert.match(toolBundler, /CURFEW_STAGING requires an isolated Debug app and helper identity/);
  assert.match(toolBundler, /CURFEW_DAEMON_PLIST_NAME/);
});

test("every user-facing release version is the same 0.0.x version", () => {
  const marketingVersions = [
    ...projectFile.matchAll(/MARKETING_VERSION = (\d+\.\d+\.\d+);/g),
  ].map((match) => match[1]);
  const caskVersion = /version "(\d+\.\d+\.\d+)"/.exec(homebrewCask)?.[1];

  assert.ok(
    marketingVersions.length > 0,
    "Xcode must declare a marketing version",
  );
  assert.equal(
    new Set(marketingVersions).size,
    1,
    "all Xcode targets must agree",
  );
  assert.match(marketingVersions[0], /^0\.0\.\d+$/);
  assert.equal(caskVersion, marketingVersions[0]);
});

test("production app and widget share the new snapshot group without changing legacy Keychain access", () => {
  for (const path of [
    "Curfew/Curfew-Release.entitlements",
    "CurfewWidget/CurfewWidget.entitlements",
  ]) {
    const entitlements = JSON.parse(
      execFileSync("plutil", ["-convert", "json", "-o", "-", path], {
        encoding: "utf8",
      }),
    );
    assert.deepEqual(entitlements["com.apple.security.application-groups"], [
      "group.studio.hypertext.apps.curfew",
    ]);
    if (path.startsWith("Curfew/"))
      assert.deepEqual(entitlements["keychain-access-groups"], [
        "$(AppIdentifierPrefix)studio.hypertext.curfew",
      ]);
  }
});
