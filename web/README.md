# Curfew web

The web side of Curfew — a pnpm + Turborepo monorepo, kept in its own directory
so it can be extracted into a standalone repository.

- `worker/` — the license API (Hono + `@hono/zod-openapi` on Cloudflare Workers);
  serves the generated OpenAPI spec at `/openapi.json` and a Scalar reference at
  `/reference`.
- `landing/` — the marketing site (Cloudflare Pages). Its `functions/` Pages
  Function reverse-proxies `/docs` to the Mintlify-hosted guides.
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
