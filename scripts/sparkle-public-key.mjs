import { createPrivateKey, createPublicKey } from "node:crypto";

// Match the 32-byte seed stored by gen-sparkle-keypair.sh. Keep private
// material in process memory; stdout contains only the public key.
const encodedSeed = process.env.SPARKLE_PRIVATE_KEY ?? "";
const seed = Buffer.from(encodedSeed, "base64");
if (seed.length !== 32 || seed.toString("base64") !== encodedSeed) {
  console.error("SPARKLE_PRIVATE_KEY must be a base64-encoded 32-byte Ed25519 seed.");
  process.exit(1);
}

const key = createPrivateKey({
  key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
  format: "der",
  type: "pkcs8",
});
const publicKey = createPublicKey(key).export({ format: "der", type: "spki" }).subarray(-32);
console.log(publicKey.toString("base64"));
