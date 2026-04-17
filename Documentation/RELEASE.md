# Release runbook

Steps required from a developer machine with Apple credentials to ship a signed, notarized DMG.

## Prerequisites (one-time setup)

1. **Apple credentials**
   - Team ID in `APPLE_TEAM_ID` GitHub secret.
   - Developer ID Application certificate in Keychain; export as `.p12` → `APPLE_CERTIFICATE` + `APPLE_CERTIFICATE_PASSWORD` secrets.
   - App Store Connect API key (for notarization) → `APPLE_API_ISSUER` + `APPLE_API_KEY_ID` + `APPLE_API_PRIVATE_KEY` secrets.

2. **Lemonsqueezy** (Pro license issuance)
   - Create store, product, and enable license keys.
   - Store ID + API key → `LEMON_STORE_ID` + `LEMON_API_KEY` secrets.
   - Deploy `scripts/issue-license.ts` as a Cloudflare Worker at your webhook endpoint.
   - Set the webhook URL in Lemonsqueezy → Webhooks.

3. **License keypair**
   ```bash
   ./scripts/gen-license-keypair.sh
   # Outputs: license_public.key (paste into LicenseGate.swift), license_private.key
   ```
   - Replace the placeholder `CURFEW_LICENSE_PUBLIC_KEY` constant in `Curfew/Core/LicenseGate.swift` with the public key.
   - Add `license_private.key` content to `LEMON_LICENSE_PRIVATE_KEY` GitHub secret.
   - **Never commit the private key.**

4. **CloudKit** (Pro, optional for v0.1)
   - Provision the `iCloud.studio.hypertext.curfew` container in App Store Connect.
   - Push schema: one record type `Settings` with fields `payload (Bytes)` and `modifiedAt (Date/Time)`.
   - Set `cloudSyncEnabled: true` in `FeatureFlags.default` once the schema is confirmed stable.

## Shipping a release

1. **Bump version**: update `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `Curfew.xcodeproj`.
2. **Tag**: `git tag v0.1.0 && git push origin v0.1.0`
3. **CI release workflow** (`.github/workflows/release.yml`) runs automatically on tag push:
   - Runs `just check` (tests + lint + format gate)
   - `xcodebuild archive` with Developer ID signing
   - Notarize with `notarytool`
   - Package DMG via `scripts/build-dmg.sh`
   - Upload DMG as a GitHub Release asset

4. **Smoke test the DMG**:
   - Install from DMG. Verify app launches, schedule saves, lockout triggers.
   - Set curfew 5 minutes ahead, wait for lockout. Confirm overlay covers all displays.
   - Use "Convince me" override flow. Confirm event appears in This Week.
   - Open Settings → Integrations. Click "Copy Claude Desktop Config". Paste into Claude Desktop.
   - Run `curfew.status` from Claude. Confirm tool responds.
   - Run `curfew-ctl status` in Terminal. Confirm output matches UI.
   - (Pro) Paste a test license key. Confirm Pro badge and features unlock.

5. **Publish**: attach release notes to the GitHub release. Update landing page if needed.

## Rollback

- Yank the GitHub release asset and replace with the previous DMG.
- There is no server-side update mechanism in v0.1 (no Sparkle). Users download manually.
