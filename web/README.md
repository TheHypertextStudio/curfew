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
