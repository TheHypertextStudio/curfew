import { createHash } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export function updateCask(source, release, bytes) {
  const version = /^v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))$/.exec(
    release.tagName,
  )?.[1];
  if (!version || release.isPrerelease !== false || release.isDraft !== false) {
    throw new Error('Select a published stable Curfew release.');
  }
  const name = `Curfew-v${version}.dmg`;
  const assets = release.assets?.filter((asset) => asset.name === name) ?? [];
  const asset = assets[0];
  const url = `https://github.com/TheHypertextStudio/curfew/releases/download/v${version}/${name}`;
  if (
    assets.length !== 1 ||
    asset.url !== url ||
    !/^sha256:[a-f0-9]{64}$/.test(asset.digest ?? '')
  ) {
    throw new Error('The release needs one canonical DMG with a SHA-256 digest.');
  }
  const digest = createHash('sha256').update(bytes).digest('hex');
  if (asset.digest !== `sha256:${digest}`)
    throw new Error('The DMG checksum differs from the published asset.');
  if (!/^  version "[^"]+"$/m.test(source) || !/^  sha256 "[^"]+"$/m.test(source)) {
    throw new Error('The cask has no unambiguous version and checksum.');
  }
  return source
    .replace(/^  version "[^"]+"$/m, `  version "${version}"`)
    .replace(/^  sha256 "[^"]+"$/m, `  sha256 "${digest}"`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let temporary;
  try {
    let [metadata, dmg, flag, ...extra] = process.argv.slice(2);
    if (metadata === '--latest' && (!dmg || dmg === '--apply') && !flag) {
      flag = dmg;
      const release = JSON.parse(
        execFileSync(
          'gh',
          [
            'release',
            'view',
            '--repo',
            'TheHypertextStudio/curfew',
            '--json',
            'tagName,isDraft,isPrerelease,assets',
          ],
          { encoding: 'utf8' },
        ),
      );
      if (!/^v[0-9]+\.[0-9]+\.[0-9]+$/.test(release.tagName))
        throw new Error('Select a published stable Curfew release.');
      temporary = await mkdtemp(join(tmpdir(), 'curfew-cask-release-'));
      metadata = join(temporary, 'release.json');
      await writeFile(metadata, JSON.stringify(release), { mode: 0o600 });
      const name = `Curfew-${release.tagName}.dmg`;
      execFileSync(
        'gh',
        [
          'release',
          'download',
          release.tagName,
          '--repo',
          'TheHypertextStudio/curfew',
          '--pattern',
          name,
          '--dir',
          temporary,
        ],
        { stdio: ['ignore', 'ignore', 'inherit'] },
      );
      dmg = join(temporary, name);
    }
    if (!metadata || !dmg || (flag && flag !== '--apply') || extra.length) {
      throw new Error(
        'Use node scripts/update-homebrew-cask.mjs release.json Curfew.dmg [--apply].',
      );
    }
    const path = new URL('../Casks/curfew.rb', import.meta.url);
    const source = await readFile(path, 'utf8');
    const result = updateCask(
      source,
      JSON.parse(await readFile(metadata, 'utf8')),
      await readFile(dmg),
    );
    if (result === source) console.log('The Homebrew cask already matches the verified release.');
    else if (flag === '--apply') {
      await writeFile(path, result);
      console.log('Updated the Homebrew cask to the verified release.');
    } else
      console.log(
        'The Homebrew cask will use the verified release version and SHA-256. Add --apply to update it.',
      );
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exitCode = 1;
  } finally {
    if (temporary) await rm(temporary, { recursive: true, force: true });
  }
}
