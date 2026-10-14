# First-run schedule safety

Curfew stores a weekly schedule separately from local consent to enforce it. A fresh install proposes weekday 22:00–06:00 with weekends off, but onboarding does not apply automatic lockouts merely because someone opens or edits Schedule. The user reviews all seven saved rules and chooses either that weekly schedule or no automatic schedule before finishing setup. Edits take effect immediately while automatic scheduling is off; once the weekly schedule is active, weaker edits retain the anti-bypass cooldown.

The weekly review choice is committed as one onboarding state transition. Its
selected confirmation must appear before Next becomes available; opening the
schedule editor alone never selects or enables automatic lockouts. The capture
matrix checks the weekly selection and advances without finishing setup, so it
cannot arm a time-dependent lockout. This change does not alter installed
schedules or deadlines.

For an already-completed Studio Dev install with no recorded consent, automatic scheduling is off on upgrade. Its saved weekly rules are retained and all seven are shown in Schedule before opt-in. The model checks again at the arming instant; if the effective rule would lock now or within the next minute, a separate explicit immediate-lock confirmation shows all seven effective rules even when the first view rendered before the boundary. A legacy pending change blocks enabling until it settles, so a proposed rule cannot obscure the rule that would actually apply. Existing production installs continue using their saved schedule. Consent is local-only so it does not alter the encrypted settings wire format or migrate another device's preferences.

Remote-only does not mean enforcement is disarmed: the full runtime still handles separately authorized fixed-duration remote commands, and active durable remote or scheduled deadlines remain authoritative until they expire or are released by the existing policy. Turning off *new* weekly scheduling does not cancel a lockout that has already begun. The effective all-days-off automatic schedule is reflected in the device status digest. App Intents, local MCP, and the CLI read a fresh app-settled observation, never a schedule-only guess that could falsely describe an active remote lock as a day off; an unavailable observation is reported as unknown. The local MCP schedule tool labels saved rules inactive while consent is off and reports work-hours triggers. The saved weekly rules remain editable for later opt-in.

## Release and rollback

Do not install a candidate over the user's active Studio Dev app until hosted native tests and review pass. Before an interactive launch, read both the user and root-owned Studio Dev deadline stores without changing them. If either contains an unexpired scheduled deadline, defer launch until natural expiry; consent-off cannot override the privileged helper's already-established lockout. Test both an old completed Studio Dev settings store and a fresh store; verify the saved schedule remains intact, the UI explains remote-only mode, and a command deadline remains enforceable. A code rollback to the previous build could re-enable an old unconfirmed Studio Dev schedule, so rollback of this policy requires an equivalent consent guard or a deliberate user-approved schedule change first. No installation or preference migration is performed by this source change.
