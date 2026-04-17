#!/usr/bin/env bash
#
# Generate the EdDSA keypair Sparkle uses to sign release updates.
#
# The PUBLIC key is embedded in the app as the `SUPublicEDKey` build
# setting (via Info.plist). The PRIVATE key is stored in the GitHub
# repository secret `SPARKLE_PRIVATE_KEY` and used by the release
# workflow's `sign_update` step to sign each DMG.
#
# Sparkle's own `generate_keys` tool writes to the macOS Keychain by
# default, which is inconvenient for CI setup. This script emits both
# keys to stdout in the exact formats we need and never touches the
# Keychain.
#
# Usage:
#   bash scripts/gen-sparkle-keypair.sh
#
# Output:
#   PUBLIC KEY (SUPublicEDKey): <base64-encoded 32-byte Ed25519 public key>
#   PRIVATE KEY (SPARKLE_PRIVATE_KEY secret): <base64-encoded 32-byte seed>
#
# Guard the private key like a signing cert — anyone holding it can push
# malicious updates to every installed Curfew.

set -euo pipefail

if ! command -v openssl >/dev/null; then
  echo "openssl is required." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# -algorithm ED25519 emits a PEM file wrapping the raw key.
openssl genpkey -algorithm ED25519 -out "$tmp/private.pem"
openssl pkey -in "$tmp/private.pem" -pubout -out "$tmp/public.pem"

# Extract the raw 32-byte values from the PEM. OpenSSL wraps Ed25519 keys in
# a DER prefix; the last 32 bytes are the actual key material Sparkle wants.
public_b64=$(openssl pkey -in "$tmp/public.pem" -pubin -outform DER \
  | tail -c 32 \
  | openssl base64 -A)
private_b64=$(openssl pkey -in "$tmp/private.pem" -outform DER \
  | tail -c 32 \
  | openssl base64 -A)

cat <<EOF
Sparkle EdDSA keypair generated.

Save the private key IMMEDIATELY to a password manager or
\`gh secret set SPARKLE_PRIVATE_KEY\` — it is not written to disk.

──── PUBLIC KEY ────
SUPublicEDKey = $public_b64

Add to the Curfew target's build settings (or Info.plist) as:
  INFOPLIST_KEY_SUPublicEDKey = $public_b64

──── PRIVATE KEY ────
SPARKLE_PRIVATE_KEY secret (GitHub Actions):
$private_b64

Set via:
  gh secret set SPARKLE_PRIVATE_KEY --body "$private_b64"
EOF
