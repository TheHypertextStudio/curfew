import { createHash, createPublicKey } from "node:crypto";

export const DEVELOPMENT_EXTENSION_ID = "loammdknmfbkjnckaeeagnmakinknbck";
export const DEVELOPMENT_PUBLIC_KEY = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnkryYyqIa7WjKAl8AMW9WssGLFlpm7HD7ThzyVexN7/Udrqdra5KpUPzXodE78gPCHMb9wPpguwgF/vD1impEdDEsDkzpIxN4aDWGxZxTDkxxWtmOntOS2YKWwGnbpz5myGO7gC/SSkc9zWOwSH8q6HbzWys0gaSJFNparL6kk+2COd/MUXwG88FYfqDgehlPn61LLvBOtNHjI8k8f2OxZL0P9VjF4DospQpDTLzq40kSRQAlV6iEnQEYWeKtaR0XgWtfDYM8x6phmprONuAE1xhbWAtZ+xZYB2HwOsE2zTwKBMUqOgcZRBoq1ShYvYLWv9rAF6MjjSsk8TOwVVnrwIDAQAB";

const extensionIDAlphabet = "abcdefghijklmnop";

/** @param {string} publicKey */
export function extensionIDFromPublicKey(publicKey) {
  const keyBytes = Buffer.from(publicKey, "base64");
  if (keyBytes.length === 0 || keyBytes.toString("base64").replace(/=+$/, "") !== publicKey.replace(/=+$/, "")) {
    throw new Error("The Chrome extension public key must be valid base64");
  }
  try {
    const key = createPublicKey({ key: keyBytes, format: "der", type: "spki" });
    if (key.asymmetricKeyType !== "rsa") {
      throw new Error("not RSA");
    }
  } catch {
    throw new Error("The Chrome extension public key must be a valid RSA public key in DER SPKI format");
  }
  const prefix = createHash("sha256").update(keyBytes).digest().subarray(0, 16);
  return [...prefix]
    .flatMap((byte) => [extensionIDAlphabet[byte >> 4], extensionIDAlphabet[byte & 0x0f]])
    .join("");
}

/**
 * @param {string | undefined} productionPublicKey
 * @param {string | undefined} productionExtensionID
 */
function validatedProductionIdentity(productionPublicKey, productionExtensionID) {
  if (!productionPublicKey || !productionExtensionID) {
    throw new Error(
      "Production public key and extension ID are required. Set " +
      "CURFEW_BROWSER_EXTENSION_PUBLIC_KEY and CURFEW_BROWSER_EXTENSION_ID.",
    );
  }
  if (!/^[a-p]{32}$/.test(productionExtensionID)) {
    throw new Error("The production extension ID must be 32 characters in the range a-p");
  }
  if (
    productionPublicKey === DEVELOPMENT_PUBLIC_KEY ||
    productionExtensionID === DEVELOPMENT_EXTENSION_ID
  ) {
    throw new Error("The production build cannot reuse the development identity");
  }
  const derivedID = extensionIDFromPublicKey(productionPublicKey);
  if (derivedID !== productionExtensionID) {
    throw new Error(
      `The production public key derives ${derivedID}, which does not match ${productionExtensionID}`,
    );
  }
  return { publicKey: productionPublicKey, extensionID: productionExtensionID };
}

/**
 * @param {"development" | "draft" | "production"} flavor
 * @param {{productionPublicKey?: string, productionExtensionID?: string}} [identity]
 */
export function buildManifest(flavor, identity = {}) {
  const publicKey = flavor === "development"
    ? DEVELOPMENT_PUBLIC_KEY
    : flavor === "production"
      ? validatedProductionIdentity(
        identity.productionPublicKey,
        identity.productionExtensionID,
      ).publicKey
      : undefined;
  return {
    manifest_version: 3,
    minimum_chrome_version: "120",
    name: flavor === "development" ? "Curfew Browser (Development)" : "Curfew Browser",
    description: "Keeps Chrome destinations bound to the current Curfew task.",
    version: "0.1.0",
    ...(publicKey ? { key: publicKey } : {}),
    homepage_url: "https://curfew.hypertext.studio",
    icons: {
      16: "icons/icon-16.png",
      32: "icons/icon-32.png",
      48: "icons/icon-48.png",
      128: "icons/icon-128.png",
    },
    permissions: [
      "declarativeNetRequest",
      "storage",
      "tabs",
      "webNavigation",
      "nativeMessaging",
      "alarms",
    ],
    host_permissions: ["http://*/*", "https://*/*"],
    background: { service_worker: "background.js", type: "module" },
  };
}
