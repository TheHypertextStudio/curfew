# Curfew website visual identity

The current Astro site uses `landing/src/layouts/Experience.astro` for the
landing, Download, Support, and legal pages. Reusable colors, typography,
controls, landscape treatment, and motion live in `landing/public/site-assets/design/`;
the page layout and responsive composition live in `landing/public/curfew.css`.
The legal text was moved intact into `landing/src/content/` so presentation can
change without silently rewriting policy.

The opening proposition is a chosen curfew that Curfew enforces so work leaves
room for the rest of life. The page shows enforcement first, then weekly
schedules and flexibility, followed by Sync/MCP, FAQ, and a closing landscape.
Curfew Plus cross-platform sync is explicitly coming soon. The former standalone
MCP fixture has been removed because it was not a real assistant conversation;
reintroduce an image only after an actual host interaction is captured.

The shared design is a public source package that can be consumed by the
account experience, but this change does not deploy or alter account backend
behavior. Account navigation still requires its hosted route to be verified.

Validation: `pnpm --dir landing site:check`, the website browser acceptance
suite, and mobile/desktop light/dark visual review. These checks cover source,
rendering, and layout; they do not prove hosted account sign-in or an MCP lock.
Rollback is the previous website commit and its verified static artifact.

The home page leads directly from navigation into the product introduction.
Policy dates, change notices, and version history belong on the policy pages;
footer links keep them accessible. Fragment links use native scrolling so late
webfont layout changes do not strand the requested section outside the viewport.
Browser acceptance covers the Plus deep link with delayed font responses and
home/footer keyboard navigation at desktop and narrow widths.

Purchase-page configuration lives in TypeScript under `landing/src/lib/` and
is checked by Astro and the shared TypeScript lint rules. Production activation
links open Curfew; staging and local links open the canonical Curfew Dev scheme.
The browser acceptance suite checks both deployment modes. Node test and
configuration files retain their existing module format.

The marketing and Support guide links now open the published Mintlify project
at `curfew.mintlify.site/docs`. This avoids dead first-party deep links while
the `/docs` proxy is still disabled; the old HTML guide remains at `/docs`
for existing bookmarks. Mintlify navigation includes installation, scheduling,
exceptions, accounts, and MCP setup. The account guide follows the live
email-first recovery flow and introduces recovery codes only after a user
selects that available method. Roll back this routing change with the previous
landing and docs commit. This does not change authentication or device
enforcement.
