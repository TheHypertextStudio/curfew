import assert from "node:assert/strict";
import test from "node:test";
import { verifyCompanionArchitectures } from "./verify-companion-architectures.mjs";

function fixture({ wide = false, little = false } = {}) {
  const stride = wide ? 32 : 20;
  const tableEnd = 8 + stride * 2;
  const bytes = Buffer.alloc(tableEnd + 64);
  const put = (value, offset) => little
    ? bytes.writeUInt32LE(value, offset) : bytes.writeUInt32BE(value, offset);
  put(wide ? 0xcafebabf : 0xcafebabe, 0);
  put(2, 4);
  [0x0100000c, 0x01000007].forEach((cpu, index) => {
    const entry = 8 + index * stride;
    const offset = tableEnd + index * 32;
    put(cpu, entry);
    if (wide) {
      bytes[little ? "writeBigUInt64LE" : "writeBigUInt64BE"](BigInt(offset), entry + 8);
      bytes[little ? "writeBigUInt64LE" : "writeBigUInt64BE"](32n, entry + 16);
    } else {
      put(offset, entry + 8);
      put(32, entry + 12);
    }
    bytes.writeUInt32LE(0xfeedfacf, offset);
    bytes.writeUInt32LE(cpu, offset + 4);
  });
  return bytes;
}

for (const options of [{}, { wide: true }, { little: true }, { wide: true, little: true }]) {
  test(`verifies both real architecture headers: ${JSON.stringify(options)}`, () => {
    assert.deepEqual(verifyCompanionArchitectures(fixture(options)), ["arm64", "x86_64"]);
  });
}

test("a thin test-runner bundle cannot satisfy distribution acceptance", () => {
  const thin = Buffer.alloc(32);
  thin.writeUInt32LE(0xfeedfacf);
  thin.writeUInt32LE(0x0100000c, 4);
  assert.throws(() => verifyCompanionArchitectures(thin));
});

test("rejects truncated, forged, overlapping and unsupported architecture records", () => {
  const truncated = fixture().subarray(0, 30);
  const wrongSlice = fixture(); wrongSlice.writeUInt32LE(0x0100000c, 84);
  const outside = fixture(); outside.writeUInt32BE(0xfffffff0, 16);
  const overlap = fixture(); overlap.writeUInt32BE(48, 36);
  const duplicate = fixture(); duplicate.writeUInt32BE(0x0100000c, 28);
  const count = fixture(); count.writeUInt32BE(0xffffffff, 4);
  for (const bytes of [Buffer.alloc(0), truncated, wrongSlice, outside, overlap, duplicate, count]) {
    assert.throws(() => verifyCompanionArchitectures(bytes));
  }
});
