import { describe, expect, it } from "vitest";

import { base64url, PRODUCT, signLicenseKey } from "../src/crypto.js";

describe("license envelope", () => {
  it("uses the Curfew Plus product and signs the decoded JSON bytes", async () => {
    expect(PRODUCT).toBe("curfew-plus");

    const keyPair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
    const privateKey = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));

    await expect(
      signLicenseKey(
        {
          email: "buyer@example.com",
          plan: "lifetime",
          orderID: "cs_test_contract",
        },
        base64url(privateKey.slice(-32))
      )
    ).resolves.toContain(".");
  });
});
