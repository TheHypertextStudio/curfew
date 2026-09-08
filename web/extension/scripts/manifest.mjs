export const DEVELOPMENT_EXTENSION_ID = "loammdknmfbkjnckaeeagnmakinknbck";
export const DEVELOPMENT_PUBLIC_KEY = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnkryYyqIa7WjKAl8AMW9WssGLFlpm7HD7ThzyVexN7/Udrqdra5KpUPzXodE78gPCHMb9wPpguwgF/vD1impEdDEsDkzpIxN4aDWGxZxTDkxxWtmOntOS2YKWwGnbpz5myGO7gC/SSkc9zWOwSH8q6HbzWys0gaSJFNparL6kk+2COd/MUXwG88FYfqDgehlPn61LLvBOtNHjI8k8f2OxZL0P9VjF4DospQpDTLzq40kSRQAlV6iEnQEYWeKtaR0XgWtfDYM8x6phmprONuAE1xhbWAtZ+xZYB2HwOsE2zTwKBMUqOgcZRBoq1ShYvYLWv9rAF6MjjSsk8TOwVVnrwIDAQAB";

/**
 * @param {"development" | "production"} flavor
 */
export function buildManifest(flavor) {
  return {
    manifest_version: 3,
    name: flavor === "development" ? "Curfew Browser (Development)" : "Curfew Browser",
    description: "Keeps Chrome destinations bound to the current Curfew task.",
    version: "0.1.0",
    key: DEVELOPMENT_PUBLIC_KEY,
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
