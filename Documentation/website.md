# Curfew website operations

## Source and setup

The production and legacy marketing origins come from the generated deployment
configuration in `deployment/generated/environments.mjs`. Preserve the declared
legacy redirects. Astro source lives
in `landing/src/`; public assets, headers, redirects and the 404 page live in
`landing/public/`. Astro builds `landing/dist/`.

Workers Static Assets uses `404-page` missing-route handling so unknown URLs
retain the existing `public/404.html` design and a real HTTP 404 status. Keep
`runWorkerFirst` enabled so the Mintlify proxy still handles documentation
before the static fallback.

CI retains the static Astro output without a Pages runtime. The existing static
artifact seal rejects `_worker.js` and `_routes.json`; `.assetsignore` also
excludes those filenames from Workers Static Assets.

Follow the common [web-platform setup and documentation](https://github.com/TheHypertextStudio/web-platform#readme).
Select the repository's pinned Node and pnpm versions, then prepare a fresh
checkout through the existing setup owner:

```sh
./bootstrap worktree prepare
```

`landing/package.json` pins the frontend tools and shared private packages.
`landing/pnpm-lock.yaml` owns the frontend dependency graph; the backend `web/`
workspace retains its own lock. Keep worktree dependencies local and use the
native shared caches. Provider administration uses `cf` with the Hypertext
Studio account; package scripts and Actions use their pinned build tools.

From the repository root:

```sh
pnpm dev
pnpm build
pnpm preview:worker
pnpm site:typecheck
pnpm site:lint
pnpm site:format:check
pnpm check
```

Root scripts forward to the frontend package. `preview:worker` uses the staging
mode of `landing/hosting/cloudflare.config.ts` through native `cf dev` on port 4325. Build-only assets configuration lives in `hosting/wrangler.config.ts`;
preview and deployment share the same Worker identity and docs bindings.
To inspect the retained HTML guide,
select the local fixture mode explicitly:

```sh
pnpm --dir landing/hosting exec cf dev --mode local --port 4325
```

`just landing` builds Astro and previews the native staging Worker;
`just landing-static` builds Astro and serves only `landing/dist/`.

## Ordinary CI and test fixtures

`.github/workflows/website.yml` runs website and docs checks on main pushes and
pull requests. It installs the frozen registry lock using the ephemeral GitHub
job token with `packages: read`. The existing browser suite runs against the
HTML-guide fixture and retains its route, history, keyboard, legal, download,
error and 404 assertions. Worker unit tests cover both docs modes, including
upstream request handling and credential isolation.

Successful main runs retain `curfew-website-dist`, including public dotfiles,
after the existing three-browser checks. The complete Website and docs run
must succeed before staging publication. Local fixtures do not accept the real
Mintlify service or protected preview behavior.

## Mintlify

Product MDX, navigation and branding live in `web/docs/`. The existing Mintlify
Git connection publishes that directory from main. Shared `studio-docs` owns
configuration generation and launches the pinned native validator:

```sh
pnpm docs:config
pnpm docs:config:check
pnpm docs:dev
pnpm docs:check
```

`docs.site.json` owns product navigation and branding; generated `docs.json`
combines it with the shared base. Follow [website authoring](website-authoring.md)
when editing either.

Staging and production select `DOCS_MODE=mintlify` and the explicit upstream
`https://curfew.mintlify.site`. Production changes require release-owner
authorization. Local fixture mode retains `html-guide`; its HTML guide also
remains available as a static compatibility asset.

The Worker delegates `/docs`, `/docs/*`, `/_mintlify/*`, `/mintlify-assets/*`
and `/api/request`. Mintlify reserves `/mcp`, so the source guide is
`mcp-guide`; the exact `/docs/mcp` alias selects `/docs/mcp-guide` and retains
query strings. The guide metadata retains the public canonical
`https://thecurfew.app/docs/mcp`, matching the production site origin in the
shared configuration. Verify the published canonical and existing bookmarks.

The proxy removes frontend cookies, Authorization, Cloudflare Access headers
and `x-forwarded-for`/`cf-connecting-ip` before contacting the public docs provider.
Upstream errors remain errors. Accept actual HTML, navigation, anchors,
assets, search and discovery on protected staging before enabling production.
Mintlify-generated MCP discovery must not advertise the product guide alias
as a search server.

## Staging publication

`Deploy website staging` (`.github/workflows/deploy-staging.yml`) is manual-only
and restricted to main and the GitHub `staging` environment. It selects a
successful push/main Website and docs run for the exact commit, downloads its
validated `curfew-website-dist` artifact, and installs pinned deployment tools.
It checks main again immediately before deployment. Deployments are serialized.

The staging website uses `curfew-staging.hypertext.studio` for the modern site,
checkout confirmation, purchase restoration and account navigation. The existing
`curfew-site-staging` Worker runs in front of the account service through an exact
hostname route. Retain the account service's custom domain and passkey identity.
Its service binding targets only `curfew-account-platform-staging`; account
paths, callbacks, request bodies and response cookies stay with that service.
Website builds include design assets at `/site-assets/design/` for both Worker
and static hosting, keeping them separate from the account service's `/design/`
assets without a runtime alias. Both activation and restoration use the
same modern page shell as the website.

The former `curfew-site-staging.hypertext.studio` entry redirects public
navigations to the canonical staging host. Existing restore fragments remain
browser-side; checkout session queries are retained only on the confirmation
route. Redirect destinations retain the canonical host even for double-slash
paths. Authenticated requests and writes on the old host return 410.

Configure the protected staging deployment credential for the existing website
Worker and its exact hostname route. Verify staff Access protection on the
canonical host before accepting the cutover. The frontend has no license keys
or database bindings. Account authorization remains enforced by the backend.
Production routes and payment configuration do not change during consolidation.

Keep the staging account service's `PUBLIC_HOME_URL` equal to the staging
`siteOrigin` so account home, support and recovery navigation stay on the same
website. Preserve its authentication origin and native callback compatibility.
Disable obsolete branch publishers that deploy a pinned preview archive before
cutover; use the reviewed staging artifact and the main-only publication path.

Outside the staging account-service binding, `ACCOUNT_PORTAL` points plain
`/account` navigation to the existing account application. Production retains
the legacy portal until the separate service-domain cutover. The marketing
Worker accepts only these configured destinations and sends a noncached 302.
If a route accidentally gives the marketing Worker the portal's own host,
`/account` instead returns a noncached 503; redirecting to itself would trap
people in another sign-in loop. On the consolidated staging host, the service
binding handles account entry before this redirect path.
It does not redirect POST bodies, Authorization-bearing requests, account
subpaths or query-bearing auth callbacks. Account APIs, sessions and provider
registrations remain with their existing owner.

For rollback, remove the staging website's exact-hostname route first so the
existing account custom domain serves requests directly. Restore the preceding
purchase-portal configuration and website artifact together; retain both old
and new email links throughout verification. Do not change passkey registration,
account data, Stripe objects or license signing keys to roll back the website.

After the required checks and staging authorization:

```sh
gh workflow run deploy-staging.yml --repo TheHypertextStudio/curfew --ref main
```

The workflow consumes the validated artifact without rebuilding it, supplies
its deployment credential only to the deployment step, fixes the account, and
uses `--env-file /dev/null`. Inspect the resulting native version/deployment and
verify the actual preview before accepting it:

```sh
cf workers deployments list --worker curfew-site-staging --profile hypertext-studio
```

For an authorized local publication of reviewed source, the existing
`pnpm deploy:worker:staging` script explicitly builds Astro for staging, verifies
the checkout and restore pages against the staging issuer and app scheme, then
invokes the pinned tool. Both local deployment scripts reject mismatched purchase
pages before any provider command, override an inherited opposite build mode, and
package the verified `dist` directory even if a retained-artifact asset override
is inherited. Retained production publication keeps its separate asset path.
Keep prior native versions and route/domain baselines available for recovery.

Staging purchase confirmation and restoration use
`https://curfew-site-staging.hypertext.studio`, the protected frontend host.
The shared profile's `purchasePortalOrigin` selects this destination independently
of the account portal at `curfew-staging.hypertext.studio`. Keep that host's
Access protection enabled during acceptance; sign in normally to inspect the
purchase pages.

## Production and rollback

Production publication requires separate approval of the source, bindings,
canonical routing, TLS and reversal steps. Use the existing
`pnpm deploy:worker:production` script after that approval. The configuration
keeps production and staging Worker names separate and workers.dev/version
preview URLs disabled.

Managed Custom Domain administration uses Cloudflare's native API through approved
operator access, separately from Worker build/deploy credentials and configuration.
Follow [hostname ownership](website-domain-preparation.md) for association and DNS
readback. Preserve all more-specific account, coordinator and service routes.
Pages is not a frontend publication or recovery dependency.

Before cutover, accept the Mintlify proxy and documented website journeys,
including anonymous rejection and successful staff access on staging. Retain
the previous accepted native Worker version. Restore it through native Worker
deployment history when needed; reverse approved domain/DNS/route changes
separately. Retain the recorded route and DNS baseline for explicit routing reversal. No fixed
observation or recovery delay is required. Existing account/service hosts remain
with their current owners.

## Native releases and the signed appcast

The native release workflow builds and retains signed release candidates,
including the signed appcast. Publication is a separate release-owner action.
The existing `activate-production.yml` workflow verifies the approved candidate,
matching main website artifact, private owner acceptance, and prepared services.
It publishes the immutable release assets to GitHub, adds the exact signed
appcast bytes to a copy of the verified static output, and packages that copy
through native `cf build --mode production`. The supported `assetsDirectory`
input in `landing/hosting/wrangler.config.ts` reads
`CURFEW_WEBSITE_ASSETS_DIRECTORY` for production; ordinary builds use `../dist`.
Activation supplies the absolute prepared directory, runs a prebuilt dry-run with
provisioning disabled, and deploys the same output. It never rebuilds Astro over
the signed feed. Final verification compares the live feed hash to the candidate.

A first signed app release is not a prerequisite for frontend migration. Until a
genuine candidate is accepted, `/appcast.xml` remains absent. Do not fabricate a
feed or use whole-product setup to preview the frontend. Keep signing, backend,
Stripe and account setup with their existing owners. The legacy account portal
is an active dependency; removing marketing publication tooling does not retire
its host, sessions, licensing or sync resources.
