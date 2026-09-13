# Chrome Web Store listing

This file gives the Curfew release engineer the exact dashboard copy and declarations for the
unlisted internal release. The engineer must upload the keyless draft first, pin the assigned
public key and item ID in the production package, and submit that replacement with deferred
publishing.

## Listing

- Name: `Curfew Browser`
- Summary: `Blocks unapproved Chrome destinations while you work on a tracked Docket task.`
- Category: `Productivity`
- Language: `English (United States)`
- Homepage: `https://curfew.hypertext.studio`
- Privacy policy: `https://curfew.hypertext.studio/privacy`

Use this detailed description:

> Curfew Browser keeps top-level Chrome navigation tied to the task you are tracking in Docket.
> Curfew allows destinations already attached to the task or mapped by you. It blocks an unknown
> destination before the page loads and asks what you will do there, what you will produce, and
> why the destination helps. Docket and Athena can grant a bounded origin or path prefix, ask one
> follow-up question, or deny access. Grants expire after 30 minutes or when the work session ends.
> The extension fails closed from its cached policy when Curfew, Docket, or Athena is unavailable.

## Single purpose and permissions

Use this single-purpose statement:

> Enforce Curfew's task-scoped destination policy on top-level HTTP and HTTPS navigation.

Use these permission justifications:

- `declarativeNetRequest`: Curfew must block unknown top-level navigation before the destination
  page loads and install higher-priority allow rules for approved scopes.
- Host access for `http://*/*` and `https://*/*`: Curfew enforces the same top-level destination
  policy across the sites a user can visit. It does not block or inspect page subresources.
- `tabs` and `webNavigation`: Curfew must identify the blocked top-level tab, show the extension's
  local blocker page, and reopen the requested URL only after a grant is installed.
- `nativeMessaging`: The extension exchanges versioned policy, review, and heartbeat messages with
  the locally installed Curfew app.
- `storage`: The extension caches the last policy and pending one-question challenge so it remains
  fail closed across worker suspension, browser restart, or loss of the native host.
- `alarms`: Chrome can suspend the MV3 worker. Alarms refresh policy, expire grants and breaks, and
  restore the policy watcher after a native-host failure.

## Data declarations

Declare handling of website activity because the extension observes top-level destination URLs.
For an unknown destination, Curfew sends the normalized origin and path, current organization and
task identifiers, and the user's review answer to Docket and Athena. Normalization removes URL
credentials, query strings, fragments, and default ports. Known destinations stay local.

Declare that Curfew does not sell data, use it for advertising, use it for credit decisions, or
transfer it outside the task-enforcement purpose. Curfew does not inspect page content or
subresources. It does not persist completed justifications or challenge answers. The local audit
log stores only the hostname, decision, and scope kind.

## Distribution and review

Choose `Unlisted` distribution and deferred publishing. Supply the notarized Curfew app and a
temporary Docket reviewer account through the dashboard's private test-instructions fields. Do not
put credentials in this repository. Tell the reviewer to connect Curfew to Docket, start a test
task, enable task browser enforcement, visit an unknown destination, and submit a concrete answer
through the blocker page.
