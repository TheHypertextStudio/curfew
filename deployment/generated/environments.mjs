// Generated deployment endpoints.
export default {
  "production": {
    "siteOrigin": "https://thecurfew.app",
    "accountOrigin": "https://account.thecurfew.app",
    "syncOrigin": "https://sync.thecurfew.app",
    "licenseOrigin": "https://license.thecurfew.app",
    "passkeyRPID": "thecurfew.app",
    "recoveryEmailFrom": "accounts@thecurfew.app",
    "legacySiteOrigin": "https://curfew.hypertext.studio",
    "retiredServiceOrigins": [
      "https://curfew-account.hypertext.studio",
      "https://curfew-sync.hypertext.studio"
    ],
    "retiredLicenseOrigins": [
      "https://curfew-license.hypertext.studio"
    ],
    "accountPortal": "https://thecurfew.app/account",
    "mcpResource": "https://sync.thecurfew.app/mcp",
    "remoteCommandJWKS": "https://sync.thecurfew.app/.well-known/curfew-command-jwks.json",
    "nativeCallback": "https://account.thecurfew.app/oauth/callback/native/macos",
    "appcast": "https://thecurfew.app/appcast.xml",
    "pricing": "https://thecurfew.app/#plus"
  },
  "staging": {
    "siteOrigin": "https://curfew-staging.hypertext.studio",
    "accountOrigin": "https://curfew-account-staging.hypertext.studio",
    "syncOrigin": "https://curfew-sync-staging.hypertext.studio",
    "licenseOrigin": "https://curfew-license-staging.hypertext.studio",
    "passkeyRPID": "curfew-staging.hypertext.studio",
    "recoveryEmailFrom": "accounts@curfew.hypertext.studio",
    "accountPortal": "https://curfew-staging.hypertext.studio/account",
    "mcpResource": "https://curfew-sync-staging.hypertext.studio/mcp",
    "remoteCommandJWKS": "https://curfew-sync-staging.hypertext.studio/.well-known/curfew-command-jwks.json",
    "nativeCallback": "https://curfew-account-staging.hypertext.studio/oauth/callback/native/macos",
    "appcast": "https://curfew-staging.hypertext.studio/appcast.xml",
    "pricing": "https://curfew-staging.hypertext.studio/#plus"
  },
  "local": {
    "siteOrigin": "http://localhost:4321",
    "accountOrigin": "http://localhost:8787",
    "syncOrigin": "http://localhost:8787",
    "licenseOrigin": "http://localhost:8788",
    "passkeyRPID": "localhost",
    "recoveryEmailFrom": "accounts@thecurfew.app",
    "accountPortal": "http://localhost:4321/account",
    "mcpResource": "http://localhost:8787/mcp",
    "remoteCommandJWKS": "http://localhost:8787/.well-known/curfew-command-jwks.json",
    "nativeCallback": "http://localhost:8787/oauth/callback/native/macos",
    "appcast": "http://localhost:4321/appcast.xml",
    "pricing": "http://localhost:4321/#plus"
  }
};
