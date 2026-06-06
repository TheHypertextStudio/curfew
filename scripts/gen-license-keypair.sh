#!/usr/bin/env bash
# Generates an Ed25519 keypair for offline license key signing.
# Run once before shipping. Keep license_private.key secret.
#
# Output:
#   license_public.key   — standard base64 (with padding) public key.
#                          Paste into LicenseGate.swift `licensePublicKeyBase64`
#                          (it decodes with standard base64 via Data(base64Encoded:)).
#   license_private.key  — base64url-encoded raw private key. Set it as the
#                          Cloudflare Worker secret LICENSE_PRIVATE_KEY (the
#                          Worker decodes base64url):
#                            wrangler secret put LICENSE_PRIVATE_KEY
set -euo pipefail

openssl genpkey -algorithm ed25519 -out /tmp/curfew_private.pem
openssl pkey -in /tmp/curfew_private.pem -pubout -out /tmp/curfew_public.pem

# Extract raw 32-byte keys and encode them. The public key is emitted as
# STANDARD base64 (LicenseGate.swift decodes it with Data(base64Encoded:)),
# while the private key stays base64url (the Worker decodes base64url).
python3 - <<'PYEOF'
import base64

def base64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()

def base64std(b: bytes) -> str:
    return base64.b64encode(b).decode()

# DER-encoded keys: last 32 bytes are the raw key material
import subprocess
private_der = subprocess.check_output(
    ['openssl', 'pkey', '-in', '/tmp/curfew_private.pem', '-outform', 'DER']
)
public_der = subprocess.check_output(
    ['openssl', 'pkey', '-in', '/tmp/curfew_public.pem', '-pubin', '-outform', 'DER']
)

raw_private = private_der[-32:]
raw_public = public_der[-32:]

# Private key → base64url (Worker secret LICENSE_PRIVATE_KEY).
with open('license_private.key', 'w') as f:
    f.write(base64url(raw_private))
# Public key → standard base64 (LicenseGate.swift licensePublicKeyBase64).
with open('license_public.key', 'w') as f:
    f.write(base64std(raw_public))

print("license_public.key  (standard base64) →", base64std(raw_public))
print("license_private.key (base64url)       → (written, do not print)")
PYEOF

rm /tmp/curfew_private.pem /tmp/curfew_public.pem
echo ""
echo "Paste the standard-base64 public key above into"
echo "  Curfew/Core/Features/LicenseGate.swift  as  licensePublicKeyBase64."
echo "Set the base64url private key as the Cloudflare Worker secret:"
echo "  wrangler secret put LICENSE_PRIVATE_KEY   (paste license_private.key contents)"
echo "NEVER commit license_private.key or license_public.key."
