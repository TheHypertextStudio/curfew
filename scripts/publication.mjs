import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile, cp, lstat, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inspectActivation } from './release-candidate.mjs';
import { resolveEnvironment } from './deployment-config.mjs';
import { verifyWebsite, sealWebsite } from './website-artifact.mjs';
import {
  verifyLocalEvidence,
  verifyLocalRepositories,
  verifyLocalDistribution,
} from './local-release.mjs';

const pendingDownload =
  /<p>\s*The public Mac download is coming soon\.\s+The installer will be available here when it is ready\.\s*<\/p>/;
const pendingInstallation = '<h2>When the download is available</h2>';

function installerURL(candidate) {
  assert.match(candidate.version, /^0\.0\.(0|[1-9]\d*)$/);
  return `https://github.com/TheHypertextStudio/curfew/releases/download/v${candidate.version}/Curfew-v${candidate.version}.dmg`;
}

function replaceOnce(html, expected, replacement) {
  assert.equal(html.split(expected).length, 2, 'Unknown or ambiguous download availability');
  return html.replace(expected, replacement);
}

/** A derived publication page; the sealed website input remains untouched. */
export function renderPublishedDownload(html, candidate) {
  html = replaceOnce(
    html,
    pendingDownload,
    `<p><a class="button primary" href="${installerURL(candidate)}">Download Curfew ${candidate.version}</a></p>`,
  );
  html = replaceOnce(html, pendingInstallation, '<h2>Install Curfew</h2>');
  return replaceOnce(
    html,
    /<p id="release-notes">\s*<a href="\/releases">Release notes<\/a>\s*<\/p>/,
    `<p id="release-notes"><a href="/releases/${candidate.version}">Release notes for Curfew ${candidate.version}</a></p>`,
  );
}

export function renderPublishedHome(html) {
  for (const [expected, replacement] of [
    ['Coming soon · Free &amp; open source · macOS 26+', 'Free &amp; open source · macOS 26+'],
    ['The public Mac download is coming soon. Check the', 'Download Curfew from the'],
    ['for availability and installation', 'for installation'],
  ])
    html = replaceOnce(html, expected, replacement);
  return html;
}

/** Reuse the sealed site's typography, navigation and assets for update notes. */
export function renderPublishedReleaseNotes(
  html,
  candidate,
  siteOrigin,
  content,
  { older, newer } = {},
) {
  const heading = `<h1>Curfew ${candidate.version}</h1>`;
  const trail = `<nav class="release-trail" aria-label="Breadcrumb"><ol><li><a href="/">Curfew</a></li><li><a href="/releases">Release notes</a></li><li aria-current="page">${candidate.version}</li></ol></nav>`;
  const links = [
    older && `<a href="/releases/${older}">Previous release (${older})</a>`,
    newer && `<a href="/releases/${newer}">Next release (${newer})</a>`,
    !content?.includes('href="/download"') && '<a href="/download">Download Curfew</a>',
  ].filter(Boolean);
  const navigation = links.length
    ? `<nav class="release-navigation" aria-label="Release navigation">${links.join(' ')}</nav>`
    : '';
  assert.ok(
    typeof content === 'string' && content.includes(heading),
    'Release notes must match the candidate version',
  );
  const replaceUnique = (pattern, replacement) => {
    const matches = html.match(pattern);
    assert.equal(matches?.length, 1, 'Unknown or ambiguous release-notes shell');
    html = html.replace(pattern, () => replacement);
  };
  replaceUnique(/<title>[^<]*<\/title>/g, `<title>Curfew ${candidate.version} — Curfew</title>`);
  replaceUnique(
    /<meta name="description"[^>]*>/g,
    `<meta name="description" content="What’s new in Curfew ${candidate.version}, and how to update.">`,
  );
  replaceUnique(
    /<meta property="og:title"[^>]*>/g,
    `<meta property="og:title" content="Curfew ${candidate.version} — Curfew">`,
  );
  replaceUnique(
    /<link rel="canonical"[^>]*>/g,
    `<link rel="canonical" href="${new URL(`/releases/${candidate.version}`, siteOrigin).href}">`,
  );
  replaceUnique(
    /<main id="main" class="reading wrap">[\s\S]*?<\/main>/g,
    `<main id="main" class="reading wrap">${trail}${content}${navigation}</main>`,
  );
  return html;
}

export function publishedReleaseVersions(releases, currentVersion) {
  const patch = (version) => BigInt(version.split('.')[2]);
  const versions = releases
    .filter(
      ({ draft, prerelease, published_at, tag_name }) =>
        draft === false &&
        prerelease === false &&
        Number.isFinite(Date.parse(published_at)) &&
        /^v0\.0\.(0|[1-9]\d*)$/.test(tag_name),
    )
    .map(({ tag_name }) => tag_name.slice(1))
    .filter((version) => patch(version) < patch(currentVersion));
  return [...new Set(versions)].sort((left, right) => (patch(left) > patch(right) ? -1 : 1));
}

async function loadPublishedReleaseHistory(currentVersion) {
  const releases = JSON.parse(
    execFileSync('gh', ['api', `repos/${repository}/releases`, '--paginate', '--slurp'], {
      encoding: 'utf8',
    }),
  ).flat();
  const history = [];
  for (const version of publishedReleaseVersions(releases, currentVersion)) {
    try {
      const content = await readFile(
        new URL(`../landing/releases/${version}.html`, import.meta.url),
        'utf8',
      );
      history.push({ version, content });
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return history;
}

function renderReleaseArchive(html, releases) {
  const marker = /(<div id="release-history">)[\s\S]*?(<\/div>)/g;
  assert.equal(html.match(marker)?.length, 1, 'Unknown or ambiguous release archive');
  const entries = releases.map(
    ({ version }, index) =>
      `<li><a href="/releases/${version}">Curfew ${version}</a>${index === 0 ? '<span>Latest release</span>' : ''}</li>`,
  );
  return html.replace(
    marker,
    (_, open, close) => `${open}<ol class="release-list">${entries.join('')}</ol>${close}`,
  );
}

async function verifyLocalPublication(input) {
  const candidate = input.native.candidate;
  verifyLocalRepositories(
    input.local.repository,
    input.local.nativeRepository,
    candidate.sourceCommit,
    input.local.publicationCommit,
  );
  await verifyLocalEvidence(input.local.evidenceDirectory, candidate, input.now);
  await verifyLocalDistribution(
    input.local.candidateDirectory,
    candidate,
    input.local.nativeRepository,
  );
}

async function admit(input, localVerifier = verifyLocalPublication) {
  const { candidate } = inspectActivation(input.native, input.receipt);
  const previousVersion = input.receipt.previousVersion;
  if (previousVersion !== undefined) {
    assert.ok(!input.local, 'Routine updates require a hosted candidate');
    assert.match(previousVersion, /^0\.0\.(0|[1-9]\d*)$/);
  }
  const observed = Date.parse(input.receipt.observedAt);
  const now = input.now ?? Date.now();
  assert.ok(observed <= now && now - observed <= 3_600_000, 'Fresh owner acceptance is required');
  const local = candidate.provenance?.kind === 'local';
  const runs = [[input.websiteRun, '.github/workflows/website.yml', 'main']];
  if (local) {
    assert.equal(input.candidateRun, undefined, 'A local candidate cannot claim a hosted run');
    assert.match(input.local?.publicationCommit ?? '', /^[a-f0-9]{40}$/);
    assert.equal(
      input.currentMainCommit,
      input.local.publicationCommit,
      'Publication source changed after local validation',
    );
    assert.equal(
      input.receipt.gates?.stagingAcceptance?.outcome,
      'pass',
      'Actual staging acceptance is required',
    );
    assert.ok(
      input.receipt.gates.stagingAcceptance.evidence?.trim(),
      'Staging evidence is required',
    );
    await localVerifier(input);
  } else {
    assert.equal(
      input.currentMainCommit,
      candidate.sourceCommit,
      'Main changed after candidate validation',
    );
    runs.unshift([input.candidateRun, '.github/workflows/release.yml', `v${candidate.version}`]);
  }
  for (const [run, path, branch] of runs) {
    assert.equal(run.repository?.full_name, 'TheHypertextStudio/curfew');
    assert.equal(run.status, 'completed');
    assert.equal(run.conclusion, 'success');
    assert.equal(run.event, 'push');
    assert.equal(run.path, path);
    assert.equal(run.head_branch, branch);
    assert.equal(run.head_sha, candidate.sourceCommit);
  }
  if (!local) assert.equal(String(input.candidateRun.id), candidate.runID);
  await verifyWebsite(
    input.website.directory,
    input.website.stamp,
    input.website.deployment,
    candidate.configurationSHA256,
    candidate.sourceCommit,
  );
  return candidate;
}

export async function preparePublication(input, localVerifier = verifyLocalPublication) {
  const candidate = await admit(input, localVerifier);
  const downloadShell = await readFile(join(input.website.directory, 'download.html'), 'utf8');
  const download = renderPublishedDownload(downloadShell, candidate);
  const releases = [
    { version: candidate.version, content: input.releaseNotes },
    ...(input.releaseHistory ?? []),
  ];
  const siteOrigin = input.website.deployment.manifest.environments.production.siteOrigin;
  for (const { version } of releases) assert.match(version, /^0\.0\.(0|[1-9]\d*)$/);
  const releasePages = releases.map(({ version, content }, index) => ({
    version,
    html: renderPublishedReleaseNotes(downloadShell, { version }, siteOrigin, content, {
      older: releases[index + 1]?.version,
      newer: releases[index - 1]?.version,
    }),
  }));
  const releaseArchive = renderReleaseArchive(
    await readFile(join(input.website.directory, 'releases.html'), 'utf8'),
    releases,
  );
  const home = renderPublishedHome(
    await readFile(join(input.website.directory, 'index.html'), 'utf8'),
  );
  await assert.rejects(
    () => lstat(input.destination),
    { code: 'ENOENT' },
    'Publication output must be a fresh directory',
  );
  await cp(input.website.directory, input.destination, {
    recursive: true,
    force: false,
    errorOnExist: true,
  });
  await writeFile(join(input.destination, 'appcast.xml'), input.native.appcast);
  await writeFile(join(input.destination, 'download.html'), download);
  await writeFile(join(input.destination, 'index.html'), home);
  await mkdir(join(input.destination, 'releases'), { recursive: true });
  await writeFile(join(input.destination, 'releases.html'), releaseArchive);
  for (const { version, html } of releasePages)
    await writeFile(join(input.destination, 'releases', `${version}.html`), html);
  return {
    candidate,
    ...(candidate.provenance?.kind === 'local'
      ? { publicationCommit: input.local.publicationCommit }
      : {}),
    siteStamp: await sealWebsite(input.destination, input.website.deployment),
  };
}

const requestOptions = (timeout = 15_000) => ({
  redirect: 'manual',
  cache: 'no-store',
  signal: AbortSignal.timeout(timeout),
});
export function verifyUpdateBaseline({ candidate, previousVersion, release, bytes, tagCommit }) {
  assert.match(previousVersion, /^0\.0\.(0|[1-9]\d*)$/);
  assert.ok(
    BigInt(previousVersion.split('.')[2]) < BigInt(candidate.version.split('.')[2]),
    'The approved public predecessor must be older than the candidate',
  );
  assert.equal(release.tagName, `v${previousVersion}`);
  assert.equal(release.isDraft, false);
  assert.equal(release.isPrerelease, false);
  const baseline = JSON.parse(bytes);
  assert.equal(baseline.version, previousVersion);
  assert.match(baseline.sourceCommit, /^[a-f0-9]{40}$/);
  assert.equal(baseline.sourceCommit, tagCommit);
  assert.equal(baseline.configurationSHA256, candidate.configurationSHA256);
  assert.equal(baseline.team, candidate.team);
  assert.equal(baseline.sparkleKey, candidate.sparkleKey);
  for (const [name, digest] of [
    ['candidate.json', createHash('sha256').update(bytes).digest('hex')],
    ['appcast.xml', baseline.appcastSHA256],
    [`Curfew-v${previousVersion}.dmg`, baseline.dmgSHA256],
  ]) {
    assert.match(digest, /^[a-f0-9]{64}$/);
    const assets = release.assets.filter((asset) => asset.name === name);
    assert.equal(assets.length, 1);
    assert.equal(assets[0].digest, `sha256:${digest}`);
  }
  return baseline;
}

export async function loadUpdateBaseline(config, candidate, previousVersion) {
  const tag = `v${previousVersion}`;
  const release = JSON.parse(
    execFileSync(
      'gh',
      [
        'release',
        'view',
        tag,
        '--repo',
        repository,
        '--json',
        'tagName,isDraft,isPrerelease,assets',
      ],
      { encoding: 'utf8' },
    ),
  );
  const manifest = await fetch(
    `https://github.com/${repository}/releases/download/${tag}/candidate.json`,
    { ...requestOptions(), redirect: 'follow' },
  );
  assert.equal(manifest.status, 200, 'Published predecessor manifest is unavailable');
  const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim();
  const tagCommit = git('rev-parse', `refs/tags/${tag}^{commit}`);
  const baseline = verifyUpdateBaseline({
    candidate,
    previousVersion,
    release,
    bytes: Buffer.from(await manifest.arrayBuffer()),
    tagCommit,
  });

  const issuer = await fetch(`${config.licenseOrigin}/health`, requestOptions());
  assert.equal(issuer.status, 200, 'Issuer health must be available');
  const issuerSourceCommit = issuer.headers.get('x-curfew-configuration-commit') ?? '';
  assert.match(issuerSourceCommit, /^[a-f0-9]{40}$/);
  for (const commit of [baseline.sourceCommit, issuerSourceCommit]) {
    git('merge-base', '--is-ancestor', commit, candidate.sourceCommit);
    git(
      'diff',
      '--quiet',
      commit,
      candidate.sourceCommit,
      '--',
      'web/worker',
      'web/package.json',
      'web/pnpm-lock.yaml',
      'web/pnpm-workspace.yaml',
      'deployment',
      'scripts/deployment-config.mjs',
      'scripts/release-configuration.mjs',
      'landing/hosting',
    );
  }
  return { baseline, candidate, issuerSourceCommit };
}

export async function checkPublicationReadiness(config, fetcher = fetch, update) {
  assert.equal(
    (await fetcher(config.siteOrigin, { ...requestOptions(), method: 'HEAD' })).status,
    200,
    'New website TLS and routing must be ready',
  );
  for (const origin of [config.accountOrigin, config.syncOrigin, config.licenseOrigin]) {
    const response = await fetcher(`${origin}/health`, requestOptions());
    assert.equal(response.status, 200, 'Service health must be available');
    assert.equal(
      response.headers.get('x-curfew-configuration'),
      config.sha256,
      'Service configuration mismatch',
    );
    if (origin === config.licenseOrigin)
      assert.equal(
        response.headers.get('x-curfew-configuration-commit'),
        update ? update.issuerSourceCommit : config.sourceCommit,
        'Issuer must match the reviewed source',
      );
    else
      assert.equal(
        response.headers.get('x-curfew-maintenance'),
        update ? 'false' : 'true',
        update
          ? 'Account authority must be out of maintenance for a routine update'
          : 'Account authority must remain in maintenance during publication',
      );
  }
  if (update) {
    const feed = await fetcher(`${config.siteOrigin}/appcast.xml`, requestOptions());
    assert.equal(feed.status, 200, 'The production update feed must exist');
    const digest = createHash('sha256')
      .update(Buffer.from(await feed.arrayBuffer()))
      .digest('hex');
    assert.ok(
      [update.baseline.appcastSHA256, update.candidate.appcastSHA256].includes(digest),
      'Live feed does not match the approved predecessor or the exact candidate',
    );
  }
}

export async function verifyLivePublication(config, candidate, fetcher = fetch) {
  const homepage = await fetcher(config.siteOrigin, requestOptions());
  assert.equal(homepage.status, 200);
  const homeHTML = await homepage.text();
  assert.ok(homeHTML.includes('href="/releases"'), 'Homepage does not link the release archive');
  assert.ok(homeHTML.includes('href="/download"'), 'Homepage does not link the download page');
  for (const stale of ['Coming soon · Free', 'The public Mac download is coming soon.'])
    assert.ok(!homeHTML.includes(stale), 'Homepage still reports the installer unavailable');
  const url = installerURL(candidate);
  const page = await fetcher(`${config.siteOrigin}/download`, requestOptions());
  assert.equal(page.status, 200, 'Customer download page is unavailable');
  const html = await page.text();
  assert.ok(
    html.includes(`href="${url}"`),
    'Customer download page does not link the accepted installer',
  );
  assert.ok(
    !html.includes('The public Mac download is coming soon.'),
    'Customer download page still reports unavailable',
  );
  const notesPath = `/releases/${candidate.version}`;
  assert.ok(
    html.includes(`href="${notesPath}"`),
    'Download page does not link the current release notes',
  );
  const archive = await fetcher(`${config.siteOrigin}/releases`, requestOptions());
  assert.equal(archive.status, 200, 'Release archive is unavailable');
  assert.ok(
    (await archive.text()).includes(`href="${notesPath}"`),
    'Release archive does not list the current release',
  );
  const notesURL = `${config.siteOrigin}/releases/${candidate.version}.html`;
  let notes = await fetcher(notesURL, requestOptions());
  if (notes.status === 307) {
    const location = notes.headers.get('location');
    assert.ok(location, 'Updater release notes redirect is missing its destination');
    const destination = new URL(location, notesURL).href;
    assert.equal(
      destination,
      `${config.siteOrigin}/releases/${candidate.version}`,
      'Unexpected updater release notes redirect',
    );
    notes = await fetcher(destination, requestOptions());
  }
  assert.equal(notes.status, 200, 'Updater release notes are unavailable');
  const notesHTML = await notes.text();
  assert.ok(
    notesHTML.includes(`<h1>Curfew ${candidate.version}</h1>`),
    'Updater release notes do not match the candidate',
  );
  assert.ok(
    notesHTML.includes('aria-label="Breadcrumb"') &&
      notesHTML.includes('href="/releases"') &&
      notesHTML.includes('href="/download"'),
    'Release notes do not link back to the archive and download',
  );
  const installer = await fetcher(url, {
    ...requestOptions(120_000),
    redirect: 'follow',
  });
  assert.equal(installer.status, 200, 'Customer installer download is unavailable');
  assert.equal(
    createHash('sha256')
      .update(Buffer.from(await installer.arrayBuffer()))
      .digest('hex'),
    candidate.dmgSHA256,
    'Customer installer differs from the signed candidate',
  );
  const feed = await fetcher(`${config.siteOrigin}/appcast.xml`, requestOptions());
  assert.equal(feed.status, 200);
  assert.equal(
    createHash('sha256')
      .update(Buffer.from(await feed.arrayBuffer()))
      .digest('hex'),
    candidate.appcastSHA256,
    'Live update feed differs from the signed candidate',
  );
  const redirect = await fetcher(
    `${config.legacySiteOrigin}/download?curfew_migration_check=1`,
    requestOptions(),
  );
  assert.equal(redirect.status, 308);
  assert.equal(
    redirect.headers.get('location'),
    `${config.siteOrigin}/download?curfew_migration_check=1`,
  );
  const retired = await fetcher(
    `${config.legacySiteOrigin}/api/auth/callback/google?code=retirement-check`,
    requestOptions(),
  );
  assert.equal(retired.status, 410);
  assert.equal(retired.headers.get('location'), null);
}

const repository = 'TheHypertextStudio/curfew';
export function publishGithubRelease(
  invoke,
  candidate,
  expectedAssets,
  directory,
  publicationCommit = candidate.sourceCommit,
) {
  assert.match(candidate.version, /^0\.0\.(0|[1-9]\d*)$/);
  const tag = `v${candidate.version}`;
  assert.match(publicationCommit, /^[a-f0-9]{40}$/);
  if (candidate.provenance?.kind !== 'local')
    assert.equal(
      publicationCommit,
      candidate.sourceCommit,
      'A hosted candidate must retain its exact source head',
    );
  assert.deepEqual(
    Object.keys(expectedAssets).sort(),
    [`Curfew-${tag}.dmg`, 'appcast.xml', 'candidate.json'].sort(),
  );
  for (const digest of Object.values(expectedAssets)) assert.match(digest, /^[a-f0-9]{64}$/);
  const head = invoke(['api', `repos/${repository}/git/ref/heads/main`]);
  assert.equal(head.object?.sha, publicationCommit, 'Main changed before publication');
  let reference = invoke(['api', `repos/${repository}/git/ref/tags/${tag}`]).object;
  if (reference?.type === 'tag') {
    assert.match(reference.sha, /^[a-f0-9]{40}$/);
    reference = invoke(['api', `repos/${repository}/git/tags/${reference.sha}`]).object;
  }
  assert.equal(reference?.type, 'commit');
  assert.equal(reference.sha, candidate.sourceCommit, 'Release tag changed before publication');
  const get = () => {
    const published = invoke(['api', `repos/${repository}/releases/tags/${tag}`]);
    if (published) return published;
    // The tag endpoint excludes pending drafts. The authenticated list includes
    // them, and pagination keeps retries independent of release-list ordering.
    const matches = invoke(['api', `repos/${repository}/releases`, '--paginate', '--slurp'])
      .flat()
      .filter((value) => value.tag_name === tag);
    assert.ok(matches.length <= 1, 'Multiple releases claim the candidate tag');
    return matches[0] ?? null;
  };
  let release = get();
  if (!release) {
    invoke([
      'release',
      'create',
      tag,
      '--repo',
      repository,
      '--verify-tag',
      '--draft',
      '--title',
      `Curfew ${candidate.version}`,
      '--notes-file',
      join(directory, 'public-release-notes.md'),
    ]);
    release = get();
  }
  assert.ok(release, 'Created release could not be read back');
  assert.equal(release.tag_name, tag);
  for (const [name, digest] of Object.entries(expectedAssets)) {
    const asset = release.assets.find((value) => value.name === name);
    if (asset) assert.equal(asset.digest, `sha256:${digest}`, `Published asset mismatch: ${name}`);
    else {
      assert.ok(release.draft, `Public release is missing asset: ${name}`);
      invoke(['release', 'upload', tag, join(directory, name), '--repo', repository]);
    }
  }
  if (!release.draft) return 'reused';
  assert.ok(Number.isSafeInteger(release.id) && release.id > 0, 'Invalid draft release ID');
  release = invoke(['api', `repos/${repository}/releases/${release.id}`]);
  assert.equal(release.tag_name, tag);
  assert.equal(release.draft, true, 'Draft changed during asset upload');
  for (const [name, digest] of Object.entries(expectedAssets))
    assert.equal(
      release.assets.find((value) => value.name === name)?.digest,
      `sha256:${digest}`,
      `Uploaded asset mismatch: ${name}`,
    );
  invoke([
    'release',
    'edit',
    tag,
    '--repo',
    repository,
    '--draft=false',
    '--prerelease=false',
    '--latest',
  ]);
  return 'published';
}

async function load(base) {
  const json = async (path) => JSON.parse(await readFile(join(base, path), 'utf8'));
  const candidate = await json('candidate/candidate.json');
  assert.match(candidate.version, /^0\.0\.(0|[1-9]\d*)$/);
  const local = candidate.provenance?.kind === 'local';
  const authority = local ? await json('local-authority.json') : undefined;
  return {
    releaseNotes: await readFile(
      new URL(`../landing/releases/${candidate.version}.html`, import.meta.url),
      'utf8',
    ),
    native: {
      candidate,
      configuration: await json('candidate/release-configuration.json'),
      dmg: await readFile(join(base, `candidate/Curfew-v${candidate.version}.dmg`)),
      appcast: await readFile(join(base, 'candidate/appcast.xml')),
    },
    website: {
      directory: join(base, 'website'),
      stamp: await json('website-build/website-build.json'),
      deployment: await json('identity/environment-artifact.json'),
    },
    candidateRun: local ? undefined : await json('candidate-run.json'),
    websiteRun: await json('website-run.json'),
    currentMainCommit:
      process.env.GITHUB_SHA ??
      (local
        ? execFileSync('git', ['rev-parse', 'HEAD'], {
            encoding: 'utf8',
          }).trim()
        : undefined),
    ...(local
      ? {
          local: {
            publicationCommit: authority.publicationCommit,
            nativeRepository: resolve(authority.nativeRepository),
            repository: fileURLToPath(new URL('../', import.meta.url)),
            evidenceDirectory: join(base, 'local-evidence'),
            candidateDirectory: join(base, 'candidate'),
          },
        }
      : {}),
    receipt: await json('owner-receipt.json'),
    destination: join(base, 'site-ready'),
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, basePath] = process.argv.slice(2);
  const base = resolve(basePath);
  const input = await load(base);
  const config = {
    ...resolveEnvironment(input.website.deployment.manifest.environments.production, 'production'),
    sha256: input.website.deployment.sha256,
    sourceCommit: input.website.deployment.sourceCommit,
  };
  const checkReadiness = async (candidate) => {
    const previousVersion = input.receipt.previousVersion;
    const update =
      previousVersion === undefined
        ? undefined
        : await loadUpdateBaseline(config, candidate, previousVersion);
    await checkPublicationReadiness(config, fetch, update);
  };
  if (command === 'prepare') {
    input.releaseHistory = await loadPublishedReleaseHistory(input.native.candidate.version);
    const prepared = await preparePublication(input);
    await writeFile(join(base, 'prepared.json'), JSON.stringify(prepared, null, 2) + '\n', {
      flag: 'wx',
    });
    console.log('Retained candidate and website are ready for owner-approved activation');
  } else if (command === 'ready') {
    const candidate = await admit(input);
    await checkReadiness(candidate);
    console.log('Website TLS and production services are ready');
  } else if (command === 'verify') {
    const candidate = await admit(input);
    if (input.receipt.previousVersion !== undefined) await checkReadiness(candidate);
    await verifyLivePublication(config, candidate);
    console.log('Live site, exact update feed, public redirect, and callback retirement verified');
  } else if (command === 'publish') {
    const candidate = await admit(input);
    if (input.receipt.previousVersion !== undefined) await checkReadiness(candidate);
    const prepared = JSON.parse(await readFile(join(base, 'prepared.json'), 'utf8'));
    assert.deepEqual(prepared.candidate, candidate);
    if (candidate.provenance?.kind === 'local')
      assert.equal(
        prepared.publicationCommit,
        input.local.publicationCommit,
        'Prepared publication source changed',
      );
    assert.deepEqual(
      prepared.siteStamp,
      await sealWebsite(input.destination, input.website.deployment),
    );
    const directory = join(base, 'candidate');
    const expected = {};
    for (const name of [`Curfew-v${candidate.version}.dmg`, 'appcast.xml', 'candidate.json'])
      expected[name] = createHash('sha256')
        .update(await readFile(join(directory, name)))
        .digest('hex');
    const origin = input.website.deployment.manifest.environments.production.siteOrigin;
    await writeFile(
      join(directory, 'public-release-notes.md'),
      `Read the [Curfew ${candidate.version} release notes](${origin}/releases/${candidate.version}) for changes and installation guidance.\n`,
    );
    const invoke = (args) => {
      try {
        const output = execFileSync('gh', args, {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        return args[0] === 'api' ? JSON.parse(output) : output;
      } catch (error) {
        if (
          args[0] === 'api' &&
          args[1].includes('/releases/tags/') &&
          /HTTP 404/.test(String(error.stderr))
        )
          return null;
        throw error;
      }
    };
    console.log(
      `Release ${publishGithubRelease(invoke, candidate, expected, directory, input.local?.publicationCommit)}`,
    );
  } else
    throw new Error(
      'Use prepare, ready, publish, or verify with the retained publication directory',
    );
}
