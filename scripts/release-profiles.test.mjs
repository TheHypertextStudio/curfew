import assert from "node:assert/strict";
import test from "node:test";
import {
  mkdtemp,
  readFile,
  writeFile,
  mkdir,
  rm,
  readdir,
  stat,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import { syncBuiltinESMExports } from "node:module";

const team = "T95VDD3A4W";
const bundles = [
  "studio.hypertext.apps.curfew",
  "studio.hypertext.apps.curfew.widget",
];
const uuids = [
  "11111111-1111-4111-8111-111111111111",
  "22222222-2222-4222-8222-222222222222",
];
function profiles() {
  return bundles.map((bundle, index) => ({
    UUID: uuids[index],
    TeamIdentifier: [team],
    AppIdentifierPrefix: [team],
    Platform: ["OSX"],
    ExpirationDate: "2099-01-01T00:00:00Z",
    ProvisionsAllDevices: true,
    DeveloperCertificates: ["certificate-fixture"],
    Entitlements: {
      "com.apple.application-identifier": `${team}.${bundle}`,
      "com.apple.developer.team-identifier": team,
      "com.apple.security.application-groups": [
        "group.studio.hypertext.apps.curfew",
      ],
      ...(index === 0
        ? {
            "com.apple.developer.associated-domains": ["*"],
            "keychain-access-groups": [`${team}.studio.hypertext.curfew`],
          }
        : {}),
    },
  }));
}
async function api() {
  const value = await import("./release-profiles.mjs").catch(() => null);
  assert.equal(
    typeof value?.installProfiles,
    "function",
    "The signed candidate must install its approved production profiles",
  );
  return value;
}
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "curfew-release-profiles-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  return { root, home: join(root, "home"), temporary: join(root, "temporary") };
}

test("release profiles install exact app and widget identities and remove only job-owned files", async (t) => {
  const { installProfiles, cleanupProfiles } = await api();
  const f = await fixture(t);
  const payload = profiles();
  const secret = JSON.stringify(
    payload.map((_, i) => Buffer.from(`signed-${i}`).toString("base64")),
  );
  const decode = (bytes) => payload[Number(bytes.toString().at(-1))];
  await installProfiles(secret, { ...f, decode });
  const config = await readFile(
    join(f.temporary, "provisioning.xcconfig"),
    "utf8",
  );
  for (const [index, variable] of [
    "CURFEW_APP_PROFILE",
    "CURFEW_WIDGET_PROFILE",
  ].entries())
    assert.ok(config.includes(`${variable} = ${uuids[index]}`));
  const directory = join(f.home, "Library/MobileDevice/Provisioning Profiles");
  for (const [index, uuid] of uuids.entries()) {
    const file = join(directory, `${uuid}.provisionprofile`);
    assert.equal(await readFile(file, "utf8"), `signed-${index}`);
    assert.equal((await stat(file)).mode & 0o777, 0o600);
  }
  await writeFile(join(directory, "unrelated.provisionprofile"), "keep");
  await cleanupProfiles(f);
  assert.deepEqual(await readdir(directory), ["unrelated.provisionprofile"]);
  await cleanupProfiles(f);
});

test("release profiles reject missing, wrong, expired, development, or incomplete identities before installation", async (t) => {
  const { installProfiles } = await api();
  const mutations = [
    (p) => p.pop(),
    (p) => p.push(p[0]),
    (p) => (p[1] = p[0]),
    (p) => (p[0].UUID = "../escape"),
    (p) => (p[0].TeamIdentifier = ["39AB9DY3K8"]),
    (p) => (p[0].ExpirationDate = "2000-01-01T00:00:00Z"),
    (p) => (p[0].ProvisionsAllDevices = false),
    (p) => (p[0].Platform = ["iOS"]),
    (p) => (p[0].DeveloperCertificates = []),
    (p) =>
      (p[0].Entitlements["com.apple.application-identifier"] =
        `${team}.studio.hypertext.apps.curfew.dev`),
    (p) =>
      (p[0].Entitlements["com.apple.developer.team-identifier"] = "39AB9DY3K8"),
    (p) => (p[0].Entitlements["com.apple.security.get-task-allow"] = true),
    (p) => delete p[0].Entitlements["com.apple.developer.associated-domains"],
  ];
  for (const mutate of mutations) {
    const f = await fixture(t);
    const p = profiles();
    mutate(p);
    const secret = JSON.stringify(
      p.map((_, i) => Buffer.from(String(i)).toString("base64")),
    );
    await assert.rejects(() =>
      installProfiles(secret, {
        ...f,
        decode: (bytes) => p[Number(bytes.toString())],
      }),
    );
    await assert.rejects(() =>
      readdir(join(f.home, "Library/MobileDevice/Provisioning Profiles")),
    );
  }
  const f = await fixture(t);
  await assert.rejects(() => installProfiles("", { ...f }));
});

test("profile installation preserves an existing profile and cleanup refuses changed owned bytes", async (t) => {
  const { installProfiles, cleanupProfiles } = await api();
  const f = await fixture(t);
  const directory = join(f.home, "Library/MobileDevice/Provisioning Profiles");
  await mkdir(directory, { recursive: true });
  const file = join(directory, `${uuids[0]}.provisionprofile`);
  await writeFile(file, "existing");
  const p = profiles();
  const secret = JSON.stringify(["MA==", "MQ=="]);
  const options = { ...f, decode: (bytes) => p[Number(bytes.toString())] };
  await assert.rejects(() => installProfiles(secret, options));
  assert.equal(await readFile(file, "utf8"), "existing");
  await rm(file);
  await installProfiles(secret, options);
  await writeFile(file, "changed");
  await assert.rejects(() => cleanupProfiles(f));
  assert.equal(await readFile(file, "utf8"), "changed");
});

test("the candidate archive consumes target-specific installed profiles and export retains their mapping", async (t) => {
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/release.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const steps = workflow.jobs.release.steps;
  const install = steps.findIndex(
    (s) => s.name === "Install approved production provisioning profiles",
  );
  const archive = steps.findIndex((s) => s.name === "Archive");
  assert.ok(
    install > steps.findIndex((s) => s.name === "Run quality gate") &&
      install < archive,
    "Production profiles must be installed after quality checks and before archive",
  );
  const project = JSON.parse(
    execFileSync(
      "plutil",
      ["-convert", "json", "-o", "-", "Curfew.xcodeproj/project.pbxproj"],
      { encoding: "utf8" },
    ),
  );
  for (const [index, bundle] of bundles.entries()) {
    const configuration = Object.values(project.objects).find(
      (o) =>
        o.isa === "XCBuildConfiguration" &&
        o.name === "Release" &&
        o.buildSettings.PRODUCT_BUNDLE_IDENTIFIER === bundle,
    );
    assert.equal(
      configuration.buildSettings.PROVISIONING_PROFILE_SPECIFIER,
      `$(CURFEW_${index === 0 ? "APP" : "WIDGET"}_PROFILE)`,
    );
  }
  const f = await fixture(t);
  await mkdir(f.temporary, { recursive: true });
  await installProfilesFixture(f);
  await writeFile(
    join(f.root, "xcodebuild"),
    `#!/usr/bin/env node
import {readFileSync} from 'node:fs';
const args=process.argv.slice(2);
const path=args[args.indexOf('-xcconfig')+1];
if(!args.includes('-xcconfig')||!readFileSync(path,'utf8').includes('CURFEW_WIDGET_PROFILE = 22222222-2222-4222-8222-222222222222'))process.exit(64);
`,
    { mode: 0o700 },
  );
  const script = steps[archive].run.replaceAll(
    "${{ github.ref_name }}",
    "v0.0.2",
  );
  const result = spawnSync("bash", ["-e", "-c", script], {
    cwd: f.root,
    env: {
      ...process.env,
      PATH: `${f.root}:${process.env.PATH}`,
      RUNNER_TEMP: f.temporary,
    },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const exported = JSON.parse(
    execFileSync(
      "plutil",
      ["-convert", "json", "-o", "-", join(f.temporary, "ExportOptions.plist")],
      { encoding: "utf8" },
    ),
  );
  assert.deepEqual(exported.provisioningProfiles, {
    "studio.hypertext.apps.curfew": uuids[0],
    "studio.hypertext.apps.curfew.widget": uuids[1],
  });
});
async function installProfilesFixture(f) {
  const { installProfiles } = await api();
  const p = profiles();
  await installProfiles(JSON.stringify(["MA==", "MQ=="]), {
    ...f,
    decode: (bytes) => p[Number(bytes.toString())],
  });
}

test("partial profile installation preserves pre-existing auxiliary files during cleanup", async (t) => {
  const { cleanupProfiles } = await api();
  for (const name of ["provisioning.xcconfig", "ExportOptions.plist"]) {
    const f = await fixture(t);
    await mkdir(f.temporary, { recursive: true });
    const file = join(f.temporary, name);
    await writeFile(file, "existing auxiliary file");
    await assert.rejects(() => installProfilesFixture(f));
    await cleanupProfiles(f);
    assert.equal(await readFile(file, "utf8"), "existing auxiliary file");
  }
});

test("profile cleanup runs independently when transient credential cleanup fails", () => {
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/release.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const steps = workflow.jobs.release.steps;
  const cleanup = steps.find(
    (s) => s.name === "Remove job-installed provisioning profiles",
  );
  assert.equal(cleanup?.if, "always()");
  assert.ok(
    steps.indexOf(cleanup) <
      steps.findIndex((s) => s.uses?.startsWith("actions/upload-artifact@")),
  );
});

test("a failed ownership update rolls back the new profile and preserves earlier ledger entries", async (t) => {
  const { cleanupProfiles } = await api();
  for (const failureAt of [1, 2]) {
    const f = await fixture(t);
    let updates = 0;
    const original = fs.writeFile;
    const mocked = t.mock.method(
      fs,
      "writeFile",
      async function (path, data, options) {
        if (
          String(path).endsWith(".json") &&
          String(data) !== "[]" &&
          ++updates === failureAt
        )
          throw Object.assign(new Error("simulated manifest I/O failure"), {
            code: "EACCES",
          });
        return original(path, data, options);
      },
    );
    syncBuiltinESMExports();
    try {
      await assert.rejects(
        () => installProfilesFixture(f),
        /simulated manifest I\/O failure/,
      );
    } finally {
      mocked.mock.restore();
      syncBuiltinESMExports();
    }
    await cleanupProfiles(f);
    assert.deepEqual(
      await readdir(join(f.home, "Library/MobileDevice/Provisioning Profiles")),
      [],
    );
  }
});

test("release app profile must authorize the retained Keychain group before installation", async (t) => {
  const { installProfiles } = await api();
  for (const allowed of [
    undefined,
    [],
    [`${team}.studio.hypertext.apps.curfew`],
    ["39AB9DY3K8.studio.hypertext.curfew"],
    ["39AB9DY3K8.*"],
    ["*"],
    [`${team}.studio.hypertext.curfew.dev`],
  ]) {
    const f = await fixture(t);
    const p = profiles();
    p[0].Entitlements["keychain-access-groups"] = allowed;
    await assert.rejects(
      () =>
        installProfiles(JSON.stringify(["MA==", "MQ=="]), {
          ...f,
          decode: (bytes) => p[Number(bytes.toString())],
        }),
      /retained Keychain access group/,
    );
    await assert.rejects(() =>
      readdir(join(f.home, "Library/MobileDevice/Provisioning Profiles")),
    );
  }
});

test("release app profile accepts the exact retained Keychain group or its same-team wildcard", async (t) => {
  const { installProfiles, cleanupProfiles } = await api();
  for (const allowed of [[`${team}.studio.hypertext.curfew`], [`${team}.*`]]) {
    const f = await fixture(t);
    const p = profiles();
    p[0].Entitlements["keychain-access-groups"] = allowed;
    await installProfiles(JSON.stringify(["MA==", "MQ=="]), {
      ...f,
      decode: (bytes) => p[Number(bytes.toString())],
    });
    await cleanupProfiles(f);
  }
});

test("both production profiles must authorize the new widget snapshot group before installation", async (t) => {
  const { installProfiles } = await api();
  for (const index of [0, 1]) {
    for (const allowed of [
      undefined,
      [],
      "group.studio.hypertext.apps.curfew",
      ["group.studio.hypertext.curfew"],
      ["group.studio.hypertext.curfew.dev"],
      ["group.studio.hypertext.curfew.studio.dev"],
      ["*"],
    ]) {
      const f = await fixture(t);
      const p = profiles();
      p[index].Entitlements["com.apple.security.application-groups"] = allowed;
      await assert.rejects(
        () =>
          installProfiles(JSON.stringify(["MA==", "MQ=="]), {
            ...f,
            decode: (bytes) => p[Number(bytes.toString())],
          }),
        /production widget App Group/,
      );
      await assert.rejects(() =>
        readdir(join(f.home, "Library/MobileDevice/Provisioning Profiles")),
      );
    }
  }
});
