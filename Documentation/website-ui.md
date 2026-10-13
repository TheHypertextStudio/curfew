# Curfew website visual identity

The current Astro site uses `landing/src/layouts/Experience.astro` for the
landing, Download, Support, and legal pages. Reusable colors, typography,
controls, landscape treatment, and motion live in `landing/public/design/`;
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
