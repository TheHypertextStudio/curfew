import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

test("an unbundled process acquires and releases ownership with its canonical flavor identity", {
  skip: process.platform !== "darwin",
}, () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const directory = mkdtempSync(join(tmpdir(), "curfew-owner-identity-"));
  try {
    const source = path => resolve(root, path);
    // Compile the real ownership implementation and its filesystem dependencies,
    // without loading the app or accessing an installed helper or user state.
    execFileSync("swiftc", [
      "-emit-library", "-emit-module", "-module-name", "CurfewKit",
      source("CurfewKit/Sources/CurfewKit/Settings/CurfewFlavor.swift"),
      source("CurfewKit/Sources/CurfewKit/Settings/SharedPaths.swift"),
      source("CurfewKit/Sources/CurfewKit/Domain/EnforcementOwner.swift"),
      source("CurfewKit/Sources/CurfewKit/Storage/BoundedRegularFileReader.swift"),
      "-o", join(directory, "libCurfewKit.dylib"),
      "-emit-module-path", join(directory, "CurfewKit.swiftmodule"),
    ], { cwd: directory, stdio: "pipe", timeout: 60_000 });
    const harness = join(directory, "OwnershipIdentityCheck.swift");
    writeFileSync(harness, `
import CurfewKit
import Foundation

@main struct OwnershipIdentityCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == nil)
        let lock = URL(fileURLWithPath: CommandLine.arguments[1])
        let result = EnforcementOwnership.acquire(lockURL: lock, isAlive: { _ in false })
        guard case .acquired = result,
              let owner = EnforcementOwnership.currentOwner(lockURL: lock, isAlive: { _ in true }),
              owner.bundleIdentifier == CurfewFlavor.current.bundleIdentifier,
              owner.hasRecognizedIdentity else {
            print("Ownership must use the canonical \\(CurfewFlavor.current.bundleIdentifier) identity")
            exit(1)
        }
        EnforcementOwnership.release(lockURL: lock)
        guard !FileManager.default.fileExists(atPath: lock.path) else {
            print("The same default identity must release its ownership record")
            exit(1)
        }
    }
}
`);
    const executable = join(directory, "check-identity");
    execFileSync("swiftc", [
      "-I", directory, "-L", directory, "-lCurfewKit",
      "-Xlinker", "-rpath", "-Xlinker", directory,
      source("Curfew/App/Infrastructure/EnforcementOwnership.swift"), harness,
      "-o", executable,
    ], { cwd: directory, stdio: "pipe", timeout: 60_000 });
    for (const flavor of ["production", "development"]) {
      const result = spawnSync(executable, [join(directory, `${flavor}.json`)], {
        encoding: "utf8",
        env: { ...process.env, CURFEW_FLAVOR: flavor },
        timeout: 10_000,
      });
      assert.equal(result.status, 0, `${flavor}: ${result.stdout}${result.stderr}`);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
