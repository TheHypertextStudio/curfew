# Curfew app identity

Curfew uses the Studio first-party app namespace for signed bundle identities:

| Build | App | Widget |
| --- | --- | --- |
| Production | `studio.hypertext.apps.curfew` | `studio.hypertext.apps.curfew.widget` |
| Development | `studio.hypertext.apps.curfew.dev` | `studio.hypertext.apps.curfew.dev.widget` |

Developer ID production profiles must match the production app and widget IDs
under the Studio team. Existing license-signing and Sparkle keys remain valid
and must not be rotated for the bundle rename.

## Retained data and interoperability

The installed identity is separate from persistent storage. `SharedPaths` keeps
the established `studio.hypertext.curfew` preferences domains, including their
isolated flavor suffixes. The app and helpers explicitly open the same
preferences domain. Production widget snapshots use the Studio-owned
`group.studio.hypertext.apps.curfew` App Group because the previous production
group is unavailable to the Studio team. Curfew Dev retains the
`group.studio.hypertext.curfew.studio.dev` storage group from existing internal
installations; that identifier does not define a third supported app. The former
personal-development store remains untouched. Both production profiles must authorize
the new snapshot group. On launch, the app regenerates widget settings from its
existing preferences; enforcement snapshots refresh as the app reconciles state.
Canonical activity and reflection databases stay in Application Support. The
one-time historical activity migration still reads the old production
`group.studio.hypertext.curfew` filesystem path, so moving widget snapshots does
not redirect the history migration source or require copying the old container.
Application Support directories, databases, lockout records, account enrollment,
and Keychain service names remain stable. Curfew Dev's helper registration is
`studio.hypertext.apps.curfew.dev.daemon`; follow the authenticated replacement
procedure in [development builds](development-builds.md) before replacing an old
helper. Each app flavor explicitly retains its same-team legacy default Keychain access
group as its first group. Production profiles must authorize that same-team group;
the release gate rejects profiles that would isolate existing credentials. Existing URL callback schemes also remain registered, preserving
pending integrations without changing their server-side redirect configuration.

Retained Keychain access applies to upgrades signed by the same team. A legacy
Personal Team build has a different access-group prefix; a Studio profile cannot
authorize those keys. Keep its old signed app and verify account recovery or an
explicit credential migration before changing teams or retiring its registration.
Do not treat a bundle rename as proof of migration between signing teams.

Both the old and new bundle IDs are recognized in existing enforcement-owner
records only for their matching flavor. Helper XPC client trust pins the new app
ID and the same signing team; it does not broaden access to other Studio apps.
When an unbundled process has no bundle metadata, new ownership records use the
canonical identity for its resolved flavor. Acquiring and releasing ownership
use the same fallback; retained preferences domains are not new app identities.

## Install and verify

An authenticated helper that trusts only the previous bundle ID cannot accept
the renamed app. Keep the old signed app installed until it has completed normal
authenticated maintenance. Turn Curfew off, pause account/assistant command
producers, and use the old app's **Remove Background Protection…** action. The
helper must admit that there is no active local, remote or shadow deadline and
that no shutdown has been issued; if admission fails, leave the old app and
helper in place until the deadline resolves. Verify that the old registration is
removed before quitting and replacing the app, then register the new helper and
verify an authenticated connection before resuming command producers. Never
erase an active deadline or account data to complete replacement. The pre-XPC
repair fallback does not support an authenticated old-ID helper. Exercise this
staged route on a dedicated test Mac before distributing the renamed app to an
affected tester; source checks do not prove signed upgrade acceptance.

Verify the signed candidate with the existing tester data: settings and consent,
remaining budgets, history, saved license, account sign-in and encrypted data,
helper status, regenerated widgets in the new production group, historical
activity migration and assistant callbacks. macOS may require renewed
Accessibility, Notifications, background-item or Keychain approval for the new
identity. Keep the previous app and a backup until these checks pass. The first
public signed release uses the new identity; existing internal installs require
an explicit replacement rather than an assumed compatible Sparkle update.

Source rollback restores the previous bundle IDs and helper client requirements
together. The retained storage and trust keys must stay intact in either direction.

## Retire superseded registrations

After the signed replacement has passed upgrade acceptance, remove superseded
Curfew app and widget registrations from the relevant Apple team. Retain the
App Groups, credential access groups, and signing keys used by the replacement.
Do not remove unrelated Docket or LogDate registrations. Check for installed
internal builds and profiles tied to each old ID before retiring it; remove
obsolete profiles after replacement profiles are available.
