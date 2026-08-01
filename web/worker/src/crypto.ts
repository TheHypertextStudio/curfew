/**
 * Internal Curfew license-envelope v2.
 *
 * Format: base64url(payload UTF-8 JSON) + "." + base64url(Ed25519 signature).
 * The signature covers the decoded JSON bytes, exactly as LicenseGate verifies.
 */
export const PRODUCT = "curfew-plus";

const encoder = new TextEncoder();
const pkcs8Ed25519Prefix = new Uint8Array([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
]);

export interface LicenseFields {
  email: string;
  plan: "lifetime" | "subscription";
  orderID: string;
  expiresAt?: string;
  refreshToken?: string;
}

export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64urlDecode(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  return Uint8Array.from(atob(padded), character => character.charCodeAt(0));
}

export function isoSeconds(epochMilliseconds: number): string {
  return new Date(epochMilliseconds).toISOString().replace(/\.\d{3}Z$/, "Z");
}

export async function signLicenseKey(
  fields: LicenseFields,
  privateKeyBase64url: string
): Promise<string> {
  const payload: Record<string, string> = {
    email: fields.email,
    product: PRODUCT,
    plan: fields.plan,
    order_id: fields.orderID,
    issued_at: isoSeconds(Date.now()),
  };
  if (fields.expiresAt) payload.expires_at = fields.expiresAt;
  if (fields.refreshToken) payload.refresh_token = fields.refreshToken;

  const payloadBytes = encoder.encode(JSON.stringify(payload));
  const rawKey = base64urlDecode(privateKeyBase64url);
  const keyMaterial = rawKey.length === 32 ? wrapPkcs8(rawKey) : rawKey;
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    keyMaterial.slice().buffer as ArrayBuffer,
    { name: "Ed25519" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("Ed25519", privateKey, payloadBytes);
  return `${base64url(payloadBytes)}.${base64url(new Uint8Array(signature))}`;
}

function wrapPkcs8(seed: Uint8Array): Uint8Array {
  const result = new Uint8Array(pkcs8Ed25519Prefix.length + seed.length);
  result.set(pkcs8Ed25519Prefix);
  result.set(seed, pkcs8Ed25519Prefix.length);
  return result;
}
