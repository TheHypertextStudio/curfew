# Curfew web

The web side of Curfew — a pnpm + Turborepo monorepo, kept in its own directory
so it can be extracted into a standalone repository.

- `worker/` — the license API (Hono + `@hono/zod-openapi` on Cloudflare Workers);
  serves the generated OpenAPI spec at `/openapi.json` and a Scalar reference at
  `/reference`.
- `landing/` — compatibility tooling for the physical `../landing/` Pages source.
  Dev/deploy first stage an allowlisted `.pages-output` directory, including the
  current appcast when present. Source, package metadata, locks, dependencies and
  prior builds never enter that output. The Pages docs proxy stays inactive until
  the existing Mintlify project and delivery have passed acceptance.
- `../landing/` — independent pinned Astro/shared website lifecycle and current
  raw Pages files. The canonical assets feed both outputs deterministically.
- `docs/` — Mintlify developer guides.

## Commands (run from this directory)

```sh
pnpm install
pnpm dev          # turbo: every dev server
pnpm typecheck    # turbo, cached
pnpm deploy       # turbo: deploy
```

A single package: `pnpm --filter @curfew/worker dev`, `pnpm --filter @curfew/landing dev`.

The repo-root `justfile` wraps these (`just web`, `just landing`, `just deploy-landing`)
and the whole-product `just setup` provisions Cloudflare + Stripe.
