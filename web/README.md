# Curfew web

The web side of Curfew — a pnpm + Turborepo monorepo, kept in its own directory
so it can be extracted into a standalone repository.

- `worker/` — the license API (Hono + `@hono/zod-openapi` on Cloudflare Workers);
  serves the generated OpenAPI spec at `/openapi.json` and a Scalar reference at
  `/reference`.
- `../landing/` — pinned Astro frontend. Source is `src/`, public files and the
  assets are in `public/`, and Astro generates `dist/`. Native signed activation
  adds the exact approved appcast to a copy of that verified static output.
- `docs/` — Mintlify user help for setup, daily use, Plus, connections, and recovery.
  Public instructions use direct actions and product facts. License internals and
  deployment references belong in `Documentation/`.

## Commands (run from this directory)

```sh
pnpm install
pnpm dev          # turbo: every dev server
pnpm typecheck    # turbo, cached
pnpm deploy       # turbo: deploy
```

Install the frontend independently with `pnpm --dir ../landing install --frozen-lockfile`
before using the root frontend commands (`pnpm build`, `pnpm preview:worker`).

A single backend package: `pnpm --filter @curfew/license-worker dev`. Marketing
preview and deployment use the independent root package and `landing/hosting`
native Worker configuration.

The repo-root `justfile` wraps these (`just web`, `just landing`, `just deploy-landing`)
and the whole-product `just setup` retains license and Stripe setup ownership.

## Private remote cache

`pnpm typecheck` runs both TypeScript packages through Turbo. Their signed cache
uses `https://turbo-cache.hypertext.studio` and the isolated `curfew-web` namespace.
The cache Worker streams artifacts directly to private Cloudflare R2; it has no
Vercel storage or cache dependency. Deploy and development tasks stay uncached.

Trusted `main` website checks obtain a short-lived Google ID token through GitHub
workload identity. The pinned Studio `release-engineering/actions/turbo-cache`
action enables remote caching only after authentication succeeds. Pull requests
use local caching and receive no signing key. The repository variables are
`TURBO_API`, `TURBO_TEAM`, `GCP_TURBO_CACHE_WIF_PROVIDER` and
`GCP_TURBO_CACHE_SERVICE_ACCOUNT`; the signing key is the
`TURBO_REMOTE_CACHE_SIGNATURE_KEY` secret. Google authenticates the client;
artifact traffic stays on Cloudflare.

For local setup and repairs, invoke `$remote-cache-doctor` from the Hypertext
Studio plugin and select this repository's `web` workspace. It checks the
namespace, workload identity, signing key, private R2 storage, retention and live
cache access. Do not copy another product's identity or signing key. Anonymous
checks cannot prove an authenticated Turbo HIT.

The website workflow is the CI consumer; the independent Astro landing site,
Mintlify documentation and native Swift/Xcode builds do not use Turbo. Removing
the cache authentication step restores local-only checks; no app data,
authentication or publication configuration changes. R2 has zero egress charges;
its storage and operation allowances are shared across Studio.
