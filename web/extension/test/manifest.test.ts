import { describe, expect, it } from "vitest";

import {
  DEVELOPMENT_EXTENSION_ID,
  DEVELOPMENT_PUBLIC_KEY,
  buildManifest,
  extensionIDFromPublicKey,
} from "../scripts/manifest.mjs";
import {
  TEST_NON_RSA_PUBLIC_KEY,
  TEST_PRODUCTION_EXTENSION_ID,
  TEST_PRODUCTION_PUBLIC_KEY,
} from "./production-identity";

describe("buildManifest", () => {
  it("builds a least-privilege MV3 development manifest with its pinned identity", () => {
    const manifest = buildManifest("development");

    expect(manifest.manifest_version).toBe(3);
    expect(manifest.minimum_chrome_version).toBe("120");
    expect(manifest.permissions).toEqual([
      "declarativeNetRequest",
      "storage",
      "tabs",
      "webNavigation",
      "nativeMessaging",
      "alarms",
    ]);
    expect(manifest.host_permissions).toEqual(["http://*/*", "https://*/*"]);
    expect(manifest.key).toBe(DEVELOPMENT_PUBLIC_KEY);
    expect(manifest.background).toEqual({ service_worker: "background.js", type: "module" });
    expect(manifest.homepage_url).toBe("https://curfew.hypertext.studio");
    expect(manifest.icons).toEqual({
      16: "icons/icon-16.png",
      32: "icons/icon-32.png",
      48: "icons/icon-48.png",
      128: "icons/icon-128.png",
    });
    expect(DEVELOPMENT_EXTENSION_ID).toBe("loammdknmfbkjnckaeeagnmakinknbck");
    expect(extensionIDFromPublicKey(DEVELOPMENT_PUBLIC_KEY)).toBe(DEVELOPMENT_EXTENSION_ID);
  });

  it("requires an explicit matching production identity", () => {
    expect(() => buildManifest("production")).toThrowError(
      /production public key.*extension ID/i,
    );
    expect(() => buildManifest("production", {
      productionPublicKey: TEST_PRODUCTION_PUBLIC_KEY,
      productionExtensionID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    })).toThrowError(/does not match/i);

    const manifest = buildManifest("production", {
      productionPublicKey: TEST_PRODUCTION_PUBLIC_KEY,
      productionExtensionID: TEST_PRODUCTION_EXTENSION_ID,
    });
    expect(manifest.key).toBe(TEST_PRODUCTION_PUBLIC_KEY);
    expect(extensionIDFromPublicKey(manifest.key ?? "")).toBe(TEST_PRODUCTION_EXTENSION_ID);
  });

  it("builds a keyless draft before the Web Store assigns its identity", () => {
    const manifest = buildManifest("draft");

    expect(manifest.name).toBe("Curfew Browser");
    expect(manifest).not.toHaveProperty("key");
  });

  it("rejects malformed keys and the development identity in production", () => {
    for (const malformedKey of ["not base64", "AQIDBA=="]) {
      expect(() => buildManifest("production", {
        productionPublicKey: malformedKey,
        productionExtensionID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      })).toThrowError(/public key/i);
    }
    expect(() => buildManifest("production", {
      productionPublicKey: DEVELOPMENT_PUBLIC_KEY,
      productionExtensionID: DEVELOPMENT_EXTENSION_ID,
    })).toThrowError(/development identity/i);
    expect(() => buildManifest("production", {
      productionPublicKey: TEST_NON_RSA_PUBLIC_KEY,
      productionExtensionID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    })).toThrowError(/RSA public key/i);
  });
});
