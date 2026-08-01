const signatureToleranceSeconds = 5 * 60;
const encoder = new TextEncoder();

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export async function verifyStripeSignature(
  body: string,
  header: string,
  secret: string
): Promise<boolean> {
  let timestamp = "";
  const signatures: string[] = [];
  for (const item of header.split(",")) {
    const [name, value] = item.split("=", 2).map(part => part.trim());
    if (name === "t") timestamp = value ?? "";
    if (name === "v1" && value) signatures.push(value);
  }
  if (!timestamp || signatures.length === 0) return false;
  const signedAt = Number(timestamp);
  if (!Number.isFinite(signedAt) || Math.abs(nowSeconds() - signedAt) > signatureToleranceSeconds) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const bytes = await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}.${body}`));
  const expected = [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, "0")).join("");
  return signatures.some(signature => constantTimeEqual(signature, expected));
}

export function subscriptionIDFromInvoice(invoice: any): string {
  return String(
    invoice.subscription ??
      invoice.parent?.subscription_details?.subscription ??
      invoice.lines?.data?.[0]?.subscription ??
      ""
  );
}

export function invoicePeriodEnd(invoice: any): number {
  const candidate = Number(invoice.lines?.data?.[0]?.period?.end ?? invoice.period_end ?? 0);
  return Number.isFinite(candidate) && candidate > 0 ? candidate : 0;
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}
