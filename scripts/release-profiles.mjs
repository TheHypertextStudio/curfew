import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  readFile,
  writeFile,
  mkdir,
  lstat,
  unlink,
  open,
  mkdtemp,
  rename,
  rm,
} from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnvironment } from "./deployment-config.mjs";

const team = "T95VDD3A4W";
const bundles = [
  "studio.hypertext.apps.curfew",
  "studio.hypertext.apps.curfew.widget",
];
const uuidPattern = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const paths = ({ home, temporary }) => ({
  directory: join(home, "Library/MobileDevice/Provisioning Profiles"),
  manifest: join(temporary, "curfew-provisioning-files.json"),
});
function decodeProfile(bytes) {
  const plist = execFileSync("/usr/bin/security", ["cms", "-D"], {
    input: bytes,
    stdio: ["pipe", "pipe", "pipe"],
  });
  return JSON.parse(
    execFileSync(
      "python3",
      [
        "-c",
        "import sys,plistlib,json,datetime,base64; json.dump(plistlib.loads(sys.stdin.buffer.read()),sys.stdout,default=lambda x:x.isoformat()+'Z' if isinstance(x,datetime.datetime) else base64.b64encode(x).decode())",
      ],
      { input: plist, stdio: ["pipe", "pipe", "pipe"] },
    ),
  );
}
export async function installProfiles(
  secret,
  {
    home = homedir(),
    temporary = process.env.RUNNER_TEMP,
    decode = decodeProfile,
  } = {},
) {
  assert.ok(
    secret && temporary,
    "Approved provisioning profiles and runner directory are required",
  );
  const encoded = JSON.parse(secret);
  assert.ok(
    Array.isArray(encoded) && encoded.length === 2,
    "Exactly two approved production profiles are required",
  );
  const config = await loadEnvironment("production");
  const profiles = encoded.map((value) => {
    assert.ok(
      typeof value === "string" && value.length > 0 && value.length < 1_000_000,
      "Invalid profile input",
    );
    const bytes = Buffer.from(value, "base64");
    assert.equal(bytes.toString("base64"), value, "Invalid profile encoding");
    const profile = decode(bytes);
    const entitlements = profile.Entitlements;
    assert.match(profile.UUID, uuidPattern, "Invalid profile UUID");
    assert.deepEqual(
      profile.TeamIdentifier,
      [team],
      "Incorrect production team",
    );
    assert.equal(entitlements?.["com.apple.developer.team-identifier"], team);
    assert.ok(profile.Platform?.includes("OSX"), "A macOS profile is required");
    assert.equal(
      profile.ProvisionsAllDevices,
      true,
      "Developer ID distribution is required",
    );
    assert.ok(
      Date.parse(profile.ExpirationDate) > Date.now(),
      "Expired provisioning profile",
    );
    assert.ok(
      Array.isArray(profile.DeveloperCertificates) &&
        profile.DeveloperCertificates.length > 0,
      "Missing signing certificate",
    );
    assert.ok(
      !entitlements["com.apple.security.get-task-allow"] &&
        !entitlements["get-task-allow"],
      "Development profiles cannot be released",
    );
    const bundle = bundles.find((id) =>
      profile.AppIdentifierPrefix?.some(
        (prefix) =>
          entitlements["com.apple.application-identifier"] ===
          `${prefix}.${id}`,
      ),
    );
    assert.ok(bundle, "The exact production bundle identity is required");
    const allowedAppGroups =
      entitlements["com.apple.security.application-groups"];
    assert.ok(
      Array.isArray(allowedAppGroups) &&
        allowedAppGroups.includes("group.studio.hypertext.apps.curfew"),
      "The production widget App Group must be provisioned for both app and widget",
    );
    if (bundle === bundles[0]) {
      const allowedKeychainGroups = entitlements["keychain-access-groups"];
      assert.ok(
        Array.isArray(allowedKeychainGroups) &&
          (allowedKeychainGroups.includes(`${team}.studio.hypertext.curfew`) ||
            allowedKeychainGroups.includes(`${team}.*`)),
        "The retained Keychain access group must be provisioned by the signing team",
      );
      for (const kind of ["applinks", "webcredentials"]) {
        const allowed = entitlements["com.apple.developer.associated-domains"];
        assert.ok(
          Array.isArray(allowed) &&
            (allowed.includes("*") ||
              allowed.includes(
                `${kind}:${new URL(config.accountOrigin).hostname}`,
              )),
          "The configured account association must be provisioned",
        );
      }
    }
    return { uuid: profile.UUID, bundle, bytes };
  });
  assert.deepEqual(
    profiles.map((p) => p.bundle).sort(),
    [...bundles].sort(),
    "App and widget profiles must both be present",
  );
  assert.equal(
    new Set(profiles.map((p) => p.uuid.toLowerCase())).size,
    2,
    "Duplicate profile UUID",
  );
  const { directory, manifest } = paths({ home, temporary });
  for (const p of profiles)
    await assert.rejects(
      () => lstat(join(directory, `${p.uuid}.provisionprofile`)),
      { code: "ENOENT" },
      "Refusing to replace an installed profile",
    );
  await mkdir(temporary, { recursive: true });
  await mkdir(directory, { recursive: true });
  const owned = [];
  await writeFile(manifest, "[]", { mode: 0o600, flag: "wx" });
  const create = async (kind, name, bytes) => {
    const file = join(kind === "profile" ? directory : temporary, name);
    const handle = await open(file, "wx", 0o600);
    try {
      await handle.writeFile(bytes);
      const next = [...owned, { kind, name, sha256: digest(bytes) }];
      const staging = await mkdtemp(
        join(temporary, ".curfew-provisioning-ledger-"),
      );
      try {
        const pending = join(staging, "manifest.json");
        await writeFile(pending, JSON.stringify(next), {
          mode: 0o600,
          flag: "wx",
        });
        await rename(pending, manifest);
        owned.push(next.at(-1));
      } finally {
        await rm(staging, { recursive: true, force: true });
      }
    } catch (error) {
      await unlink(file);
      throw error;
    } finally {
      await handle.close();
    }
  };
  for (const p of profiles) {
    await create("profile", `${p.uuid}.provisionprofile`, p.bytes);
  }
  const values = bundles.map(
    (id) => profiles.find((p) => p.bundle === id).uuid,
  );
  await create(
    "auxiliary",
    "provisioning.xcconfig",
    `CURFEW_APP_PROFILE = ${values[0]}\nCURFEW_WIDGET_PROFILE = ${values[1]}\n`,
  );
  await create(
    "auxiliary",
    "ExportOptions.plist",
    `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>method</key><string>developer-id</string><key>teamID</key><string>${team}</string><key>signingStyle</key><string>manual</string><key>provisioningProfiles</key><dict>${bundles.map((id, index) => `<key>${id}</key><string>${values[index]}</string>`).join("")}</dict></dict></plist>\n`,
  );
}
export async function cleanupProfiles({
  home = homedir(),
  temporary = process.env.RUNNER_TEMP,
} = {}) {
  assert.ok(temporary, "Runner directory is required");
  const { directory, manifest } = paths({ home, temporary });
  let entries;
  try {
    entries = JSON.parse(await readFile(manifest, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return;
    throw error;
  }
  assert.ok(
    Array.isArray(entries) && entries.length <= 4,
    "Invalid job profile manifest",
  );
  const files = [];
  const unique = new Set();
  for (const entry of entries) {
    assert.ok(entry.kind === "profile" || entry.kind === "auxiliary");
    if (entry.kind === "profile") {
      assert.ok(entry.name.endsWith(".provisionprofile"));
      assert.match(
        entry.name.slice(0, -".provisionprofile".length),
        uuidPattern,
      );
    } else
      assert.ok(
        ["provisioning.xcconfig", "ExportOptions.plist"].includes(entry.name),
      );
    assert.ok(
      !unique.has(`${entry.kind}/${entry.name}`),
      "Duplicate owned file",
    );
    unique.add(`${entry.kind}/${entry.name}`);
    assert.match(entry.sha256, /^[a-f0-9]{64}$/);
    const file = join(
      entry.kind === "profile" ? directory : temporary,
      entry.name,
    );
    try {
      assert.equal(
        digest(await readFile(file)),
        entry.sha256,
        "Installed provisioning file changed; refusing cleanup",
      );
      files.push(file);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  for (const file of files) await unlink(file);
  await unlink(manifest);
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    if (process.argv[2] === "install")
      await installProfiles(process.env.APPLE_PROVISIONING_PROFILES);
    else if (process.argv[2] === "cleanup") await cleanupProfiles();
    else throw new Error("Use install or cleanup");
  } catch {
    console.error(
      "Provisioning profile operation failed; approved production app/widget profiles are required.",
    );
    process.exitCode = 1;
  }
}
