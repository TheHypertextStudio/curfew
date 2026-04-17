#!/usr/bin/env bash
# Generates an Ed25519 keypair for offline license key signing.
# Run once before shipping. Keep license_private.key secret.
#
# Output:
#   license_public.key   — base64url-encoded public key (paste into LicenseGate.swift)
#   license_private.key  — base64url-encoded private key (add to LEMON_LICENSE_PRIVATE_KEY secret)
set -euo pipefail

openssl genpkey -algorithm ed25519 -out /tmp/curfew_private.pem
openssl pkey -in /tmp/curfew_private.pem -pubout -out /tmp/curfew_public.pem

# Extract raw 32-byte keys and base64url-encode them
python3 - <<'PYEOF'
import base64, sys

def base64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()

with open('/tmp/curfew_private.pem', 'rb') as f:
    private_pem = f.read()
with open('/tmp/curfew_public.pem', 'rb') as f:
    public_pem = f.read()

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

with open('license_private.key', 'w') as f:
    f.write(base64url(raw_private))
with open('license_public.key', 'w') as f:
    f.write(base64url(raw_public))

print("license_public.key  →", base64url(raw_public))
print("license_private.key → (written, do not print)")
PYEOF

rm /tmp/curfew_private.pem /tmp/curfew_public.pem
echo ""
echo "Paste the public key into Curfew/Core/LicenseGate.swift as CURFEW_LICENSE_PUBLIC_KEY."
echo "Add license_private.key content to LEMON_LICENSE_PRIVATE_KEY GitHub secret."
echo "NEVER commit license_private.key."
