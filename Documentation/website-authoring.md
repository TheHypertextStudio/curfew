# Product documentation authoring

Write for the person completing a task. Start with what they can do, state the prerequisites, give the steps in order, and show how to recognize success. Use the product's approved names for objects, actions, and settings.

## Choose the page

| Page | Include |
| --- | --- |
| Overview | Purpose, capabilities, limits, and links to the next useful task |
| Quickstart | Minimum prerequisites, one complete path to a useful result, and confirmation |
| Guide | One task, prerequisites, ordered steps, expected result, recovery, and related reference |
| Reference | Exact interface, inputs, outputs, authorization, errors, and working examples |
| Changelog | Date/version, observable changes, compatibility, and any required user action |

Use the existing product navigation groups. Add a page's extensionless path to `docs.site.json`, then run `pnpm docs:config`. Keep established URLs and heading anchors stable. When a page moves, add a product redirect and update local links in the same change.

## MDX conventions

Start public pages with a meaningful frontmatter title and description. Use sentence case for headings. Link to local pages with their existing extensionless paths, such as `/guides/create-your-workspace`. Use descriptive link text and image alternative text.

Use Mintlify's native `Steps` and `Step` for ordered procedures, `Note` or `Warning` for information needed at that point, and `Tabs`/`Tab` or `CodeGroup` for real alternatives. Keep ordinary explanation in Markdown. Do not build a second component or search system. Preserve existing product components that pass the native validator.

Code examples name their language and show the complete command or request a person needs. Use explicit example values, identify values the reader must replace, and explain the expected output. Never include real credentials, personal data, or instructions that mutate production just to preview documentation.

## Review and publish

1. Edit product MDX, images, and `docs.site.json` as needed.
2. Regenerate configuration with `pnpm docs:config`.
3. Run `pnpm docs:check`, including the product's additional coverage checks.
4. Inspect the changed pages with `pnpm docs:dev` or the existing hosted preview. Check narrow layouts, keyboard use, code samples, links, and image descriptions.
5. Review generated config changes with content changes. Merge only after required checks pass.
6. Record the reviewed source SHA and resulting Mintlify deployment. Verify public paths, anchors, search, assets, redirects, and canonical URLs through the existing docs prefix.

Publishing uses the existing Mintlify Git integration. A passing local check does not prove that Mintlify published the reviewed source.
