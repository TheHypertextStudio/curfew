import { describe, expect, it } from "vitest";

import {
  DEVELOPMENT_EXTENSION_ID,
  DEVELOPMENT_PUBLIC_KEY,
  buildManifest,
} from "../scripts/manifest.mjs";

describe("buildManifest", () => {
  it.each(["development", "production"] as const)(
    "builds a least-privilege MV3 %s manifest with the pinned identity",
    (flavor) => {
      const manifest = buildManifest(flavor);

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
      expect(DEVELOPMENT_EXTENSION_ID).toBe("loammdknmfbkjnckaeeagnmakinknbck");
    },
  );
});
