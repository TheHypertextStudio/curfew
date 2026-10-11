import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

export function selectProfile(listing) {
  const first = listing.split(/\nPersistent screen id:/)[0];
  const id = first.match(/Persistent screen id:\s*(\S+)/)?.[1];
  if (!id) throw new Error("No CI display was found.");
  const modes = [...first.matchAll(/mode (\d+): res:(\d+)x(\d+)([^\n]*)/g)]
    .filter(([, , width, height, extra]) => Number(width) >= 1280 && Number(height) >= 900 && !extra.includes("scaling:on"))
    .sort((a, b) => Number(a[2]) * Number(a[3]) - Number(b[2]) * Number(b[3]));
  if (!modes.length) throw new Error("No advertised CI display mode can fit default app windows.");
  return `id:${id} mode:${modes[0][1]} origin:(0,0) degree:0`;
}

function displayplacer(args) {
  const result = spawnSync("displayplacer", args, { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || String(result.error));
  return result.stdout;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.env.GITHUB_ACTIONS !== "true") {
    throw new Error("Display configuration is restricted to isolated GitHub runners.");
  }
  const before = displayplacer(["list"]);
  console.log(before);
  displayplacer([selectProfile(before)]);
  const after = displayplacer(["list"]);
  console.log(after);
  const dimensions = after.match(/Resolution:\s*(\d+)x(\d+)/);
  if (!dimensions || Number(dimensions[1]) < 1280 || Number(dimensions[2]) < 900) {
    throw new Error("CI display did not apply a size that fits default windows.");
  }
}
