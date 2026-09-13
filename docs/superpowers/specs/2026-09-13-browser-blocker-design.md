# Browser blocker visual design

This design is for the Curfew maintainer who owns the Chrome interruption page. The maintainer must
keep the page focused on one decision instead of explaining Curfew's enforcement system.

## Decision

The blocker will use a restrained, utilitarian layout that matches Curfew's macOS settings. It will
show the Curfew mark, the active task, the requested hostname, Athena's current question, one answer
field, one primary action, and a status message only when the state changes.

The page will remove the editorial masthead, the `Stop. Name the work.` slogan, classification and
task labels, the hostname badge, the offline footer, oversized serif display type, grid texture, hard
shadow, and repeated privacy narration. Those elements make the page describe itself and compete
with the answer the user must provide.

The task title will be the page heading. The hostname will sit directly under it as plain secondary
text. Athena's question will introduce the answer field. The button will say `Request access` for the
initial answer and `Submit answer` for the single challenge. Dynamic errors will state what happened
and what the user can do next. They will not mention native hosts, policy caches, or internal request
IDs.

The layout will use a warm neutral background, dark text, Curfew red for the primary action, the
extension icon as the only decorative element, and one narrow content column. At 390 by 844 pixels,
the action will span the column and the page will require no horizontal scrolling. Desktop widths
will keep the same column instead of expanding into an empty card.

## Rejected directions

A Chrome-style error page would hide Curfew's identity and make a deliberate work boundary look like
a browser failure. A new editorial treatment would preserve the same visual noise under different
colors. A bare unstyled form would remove the noise but would not match the installed app.

## Behavior and verification

The change will preserve the existing blocker protocol, normalization, challenge limit, grant flow,
and fail-closed behavior. Tests will reject the removed self-narrating copy, require the reduced
semantic structure and action labels, and continue to exercise every existing outcome. The release
operator will reload the unpacked extension and inspect the page at desktop and 390-pixel widths.
