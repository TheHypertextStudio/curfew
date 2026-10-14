import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

export function deploymentHostLiterals(source) {
  return [...source.matchAll(/https?:\/\/([A-Za-z0-9.-]+)/g)]
    .map((match) => match[1])
    .filter(
      (host) =>
        host === "thecurfew.app" ||
        host.endsWith(".thecurfew.app") ||
        /^curfew(?:-[a-z0-9-]+)?\.hypertext\.studio$/.test(host),
    );
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const files = execFileSync(
    "git",
    ["ls-files", "--cached", "--others", "--exclude-standard"],
    { encoding: "utf8" },
  )
    .trim()
    .split("\n");
  const sourceFiles = files.filter(
    (path) =>
      /^(?:Curfew\/|CurfewKit\/Sources\/|web\/extension\/scripts\/|landing\/src\/|scripts\/)/.test(
        path,
      ) &&
      /\.(swift|mjs|ts|astro)$/.test(path) &&
      !path.endsWith(".test.mjs") &&
      !path.endsWith(".generated.swift"),
  );
  const violations = [];
  for (const path of sourceFiles) {
    for (const host of deploymentHostLiterals(await readFile(path, "utf8")))
      violations.push(
        `${path}: ${host} must come from deployment configuration`,
      );
  }
  if (violations.length) throw new Error(violations.join("\n"));
  console.log("Application source uses configured deployment origins.");
}
