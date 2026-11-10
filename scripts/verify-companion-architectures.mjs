import { lstat, readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

/** Inspect bytes only: never load or execute the companion. */
export function verifyCompanionArchitectures(bytes) {
  const fail = () => { throw new Error("Companion must contain valid arm64 and x86_64 slices"); };
  if (!Buffer.isBuffer(bytes) || bytes.length < 8) fail();
  const magic = bytes.readUInt32BE(0);
  const little = magic === 0xbebafeca || magic === 0xbfbafeca;
  const wide = magic === 0xcafebabf || magic === 0xbfbafeca;
  if (![0xcafebabe, 0xcafebabf, 0xbebafeca, 0xbfbafeca].includes(magic)) fail();
  const word = (offset) => little ? bytes.readUInt32LE(offset) : bytes.readUInt32BE(offset);
  const long = (offset) => little ? bytes.readBigUInt64LE(offset) : bytes.readBigUInt64BE(offset);
  const count = word(4);
  const stride = wide ? 32 : 20;
  const tableEnd = 8 + count * stride;
  if (count !== 2 || bytes.length < tableEnd) fail();
  const cpus = new Set();
  const ranges = [];
  for (let index = 0; index < count; index++) {
    const entry = 8 + index * stride;
    const cpu = word(entry);
    const offset = wide ? Number(long(entry + 8)) : word(entry + 8);
    const length = wide ? Number(long(entry + 16)) : word(entry + 12);
    if (![0x0100000c, 0x01000007].includes(cpu) || cpus.has(cpu)
      || !Number.isSafeInteger(offset) || !Number.isSafeInteger(length)
      || offset < tableEnd || length < 32 || offset + length > bytes.length) fail();
    const sliceMagic = bytes.readUInt32BE(offset);
    const sliceCPU = sliceMagic === 0xcffaedfe ? bytes.readUInt32LE(offset + 4)
      : sliceMagic === 0xfeedfacf ? bytes.readUInt32BE(offset + 4) : null;
    if (sliceCPU !== cpu) fail();
    cpus.add(cpu);
    ranges.push([offset, offset + length]);
  }
  ranges.sort((a, b) => a[0] - b[0]);
  if (ranges[0][1] > ranges[1][0]) fail();
  return ["arm64", "x86_64"];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const filename = process.argv[2];
  if (!filename) throw new Error("Usage: verify-companion-architectures.mjs <companion executable>");
  const metadata = await lstat(filename);
  if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size > 128 * 1024 * 1024) {
    throw new Error("Companion executable is not a bounded regular file");
  }
  verifyCompanionArchitectures(await readFile(filename));
  console.log("Companion contains verified arm64 and x86_64 executable slices");
}
