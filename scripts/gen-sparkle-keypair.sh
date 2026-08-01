#!/usr/bin/env bash
#
# Generate the EdDSA keypair Sparkle uses to sign release updates.
#
# The PUBLIC key is embedded in the app as the `SUPublicEDKey` build
# setting (via Info.plist). The PRIVATE key is stored in the GitHub
# repository secret `SPARKLE_PRIVATE_KEY` and used by the release
# workflow's `sign_update` step to sign each DMG. This script uploads the
# private seed directly to GitHub Actions and prints only the public key.
#
# Sparkle's own `generate_keys` tool writes to the macOS Keychain by
# default, which is inconvenient for CI setup. This script emits both
# keys to stdout in the exact formats we need and never touches the
# Keychain or filesystem.
#
# Usage:
#   bash scripts/gen-sparkle-keypair.sh [owner/repository]
#
# Output:
#   PUBLIC KEY (SUPublicEDKey): <base64-encoded 32-byte Ed25519 public key>
# The private seed is never printed. `gh secret set` reads it from stdin.

set -euo pipefail

if ! command -v openssl >/dev/null; then
  echo "openssl is required." >&2
  exit 1
fi

if ! command -v gh >/dev/null; then
  echo "gh is required to store SPARKLE_PRIVATE_KEY without printing it." >&2
  exit 1
fi

repository=${1:-TheHypertextStudio/curfew}
gh auth status >/dev/null

# Keep the PEM and raw seed in process memory only. OpenSSL wraps Ed25519 keys
# in DER; the final 32 bytes are the key material Sparkle expects.
private_pem=$(openssl genpkey -algorithm ED25519)
public_b64=$(printf '%s\n' "$private_pem" \
  | openssl pkey -pubout -outform DER \
  | tail -c 32 \
  | openssl base64 -A)
private_b64=$(printf '%s\n' "$private_pem" \
  | openssl pkey -outform DER \
  | tail -c 32 \
  | openssl base64 -A)

printf '%s' "$private_b64" | gh secret set SPARKLE_PRIVATE_KEY --repo "$repository"
unset private_b64 private_pem

cat <<EOF
Stored SPARKLE_PRIVATE_KEY in GitHub Actions for $repository.
The private key was not printed or written to disk.
SUPublicEDKey = $public_b64
EOF
