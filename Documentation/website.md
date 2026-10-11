# Curfew website operations

## Source and tools

The marketing origin remains `https://curfew.hypertext.studio`. Astro source is
`landing/src/`; public images, CSS, JavaScript, headers, sitemap and 404 are in
`landing/public/`. Astro's native static build writes `landing/dist/`. The
previous duplicate raw HTML source, asset copier, parity script, candidate
assembler and website lifecycle wrappers have been removed. Root bootstrap,
native application, license API and extension retain their existing owners.

The independent frontend package pins Node 24.20.0, pnpm 11.9.0, Astro 7.2.9,
Wrangler 4.148.0 and Mintlify 4.2.854. Shared private packages `web-config`,
`web-docs` and `web-tokens` remain at 0.0.1 with the adopted registry lock and
shared configuration. The backend `web/` workspace retains its own lockfile.

```sh
pnpm --dir landing install --frozen-lockfile
pnpm dev                       # Astro source preview
pnpm build                     # Astro static output
pnpm preview:worker            # Local Wrangler staging environment, port 4325
pnpm site:typecheck
pnpm site:lint
pnpm site:format:check
pnpm check                     # Existing behavior checks and docs validation
```

Root package scripts forward directly to the independent frontend package.
`just landing` retains the Pages Function preview through `web/landing` and
`just landing-static` builds Astro before serving only `landing/dist/`.
Neither preview requires provider publication.

## GitHub Actions

`.github/workflows/website.yml` runs normal website and docs checks for main
pushes and pull requests. It installs the canonical registry lock with the
native ephemeral GitHub job token and `packages: read`. The temporary lock
proposal job, branch-specific draft condition and manual lock-refresh input
are removed. Website checks use native Astro build and Wrangler local preview;
there is no automatic frontend deployment workflow.

The cleanup removes only obsolete release-identity and literal implementation
checks. Existing page, legal/account/download, route, keyboard, 404 and proxy
behavior checks remain. No new or manual tests are run for this source cleanup;
static lint, type/build and workflow checks are reported separately.

## Mintlify

Product MDX and navigation live in `web/docs/`. Shared `studio-docs` deliberately
remains the configuration generator and native validation launcher:

```sh
pnpm docs:config
pnpm docs:config:check
pnpm docs:dev
pnpm docs:check
```

`docs.site.json` owns product navigation and branding; generated `docs.json`
combines it with the published shared base. Follow the authoring guide when
editing either. Existing Git-connected Mintlify publishing remains unchanged.

The first four-page connected update succeeded. Public GET observations found
working overview/CLI/licensing content, but Mintlify reserves `/mcp` and returned
405 for the former guide path. This branch keeps the source page `mcp-guide`,
its canonical `https://curfew.hypertext.studio/docs/mcp`, and the exact Pages and
Worker alias `/docs/mcp` -> `/docs/mcp-guide`, preserving query strings. This
source is not yet integrated or published. No source SHA or vendor deployment
ID is inferred from content alone.

Both source proxies retain explicit `DOCS_MODE=mintlify` opt-in; HTML-guide mode
remains the source default until proxy acceptance. Pages proxies `/docs` and
its descendants. The Worker also handles `/_mintlify/*`, `/mintlify-assets/*`
and `/api/request`. Full browser/search/discovery parity is not established by
sampled GETs. Mintlify-generated MCP discovery must not advertise the product
guide alias as a search server. This cleanup does not enable a mode or change
provider variables, routes or domains.

## Manual Worker publication

The standard Wrangler config defines `staging` and `production` separately.
Both retain disabled workers.dev/previews and empty routes. Worker names and
account ID are source configuration, not proof of deployed resources. The
frontend has only its assets and docs settings, with no license API/database
bindings. The existing `curfew-staging.hypertext.studio` belongs to the backend;
do not reuse it as a marketing preview.

After the owner approves the exact source, environment and provider scope:

```sh
pnpm deploy:worker:staging
# Separately approved production publication:
pnpm deploy:worker:production
```

These scripts run native Astro build followed by `wrangler deploy --env staging`
or `--env production`. No candidate/promotion workflow, downloaded website
engine, custom immutable artifact tree, release-identity endpoint or activation
variable is used. Manual deployment requires explicit staging/production approval;
these commands have not been executed by the cleanup. Retain prior deployment
and route/domain configuration for recovery before any host cutover.

## Existing Pages/appcast publisher

The existing native release workflow signs and uploads the Sparkle appcast,
installs the frontend's frozen registry lock, copies the exact signed feed to
`landing/public/appcast.xml`, and calls `pnpm --dir landing deploy:pages`.
That native script builds Astro and uploads only `dist` using Wrangler Pages.
The existing served-byte comparison against the signed feed remains unchanged.
No appcast is fabricated when one has not been generated.

The `web/landing` compatibility scripts and existing setup's Pages phase use
the same native build/output. Backend/Stripe/key setup is unchanged; do not run
whole-product setup merely to preview the frontend. Pages Functions stay in
`landing/functions/` so Wrangler discovers them from the frontend project root.

Any future Git-connected Pages build must use the native Astro build and
`landing/dist/` output (or `dist/` with project root `landing`). Provider settings
still referencing the removed copier or `.pages-output` need an independently
reviewed update before their publisher resumes. Uploading mixed `landing/` or
output `.` is unsafe because it contains source, package metadata and tooling.
The 404 page remains public so absent files do not silently become the homepage.

## Evidence and remaining acceptance

Historical migration receipts in `verification/website/` describe their dated
source and custom build; they do not validate this cleanup or the current provider.
Local historical outputs remain ignored and are not current build inputs.
Current source cleanup still requires normal protected review/CI and real
provider/runtime acceptance before publication. No Pages, Worker, domain, secret,
credential, account, native release or backend operation occurred in this slice.
