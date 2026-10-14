import deployment from '../../deployment/generated/environments.mjs';
import { legacyDomainResponse } from '../domain-routing.mjs';
// Cloudflare Pages Function — reverse-proxy /docs to Mintlify.
//
// The existing project dashboard identified `curfew.mintlify.site`. It has
// published its first connected update, but complete proxy acceptance remains open.
// The physical HTML guide remains the default until explicit opt-in.
// Only explicit DOCS_MODE=mintlify activates this existing proxy.
//
// This runs as Pages middleware on EVERY request to the landing project: it
// proxies `/docs` and `/docs/*` to Mintlify and passes everything else through
// to the static landing site via `next()`. Using a Pages Function (rather than a
// standalone Worker on the same hostname) avoids the infinite-loop / route
// conflict you get when a Worker's pass-through re-fetches its own route.
//
// Mintlify side: in the Mintlify dashboard, configure the project to be served
// from the `/docs` subpath of `curfew.hypertext.studio` (Settings → Custom
// domain / subpath). Mintlify must know it lives under `/docs`. Only the exact
// public `/docs/mcp` alias maps to the nonreserved upstream `/docs/mcp-guide`.

const DOCS_HOST = "curfew.mintlify.site";
const CUSTOM_HOST = new URL(deployment.production.siteOrigin).host;

export async function onRequest(context) {
  const { request, next } = context;
  const legacy = legacyDomainResponse(request, deployment.production);
  if (legacy) return legacy;
  const url = new URL(request.url);

  const isDocs = url.pathname === "/docs" || url.pathname.startsWith("/docs/");
  if (!isDocs || context.env?.DOCS_MODE !== "mintlify") {
    // Retain the HTML guide until the existing Mintlify project and proxy pass acceptance.
    return next();
  }

  // Proxy to Mintlify, preserving the path/query and forwarding the original host.
  url.hostname = DOCS_HOST;
  url.protocol = "https:";
  url.port = "";
  // Mintlify owns /mcp for its search server, not product documentation.
  if (url.pathname === "/docs/mcp") url.pathname = "/docs/mcp-guide";

  const proxied = new Request(url, request);
  proxied.headers.set("Host", DOCS_HOST);
  proxied.headers.set("X-Forwarded-Host", CUSTOM_HOST);
  proxied.headers.set("X-Forwarded-Proto", "https");

  return fetch(proxied);
}
