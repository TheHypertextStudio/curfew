# First-run schedule safety

Curfew stores a weekly schedule separately from local consent to enforce it. A fresh install proposes weekday 22:00–06:00 with weekends off, but onboarding does not apply automatic lockouts merely because someone opens or edits Schedule. The user chooses either that weekly schedule or no automatic schedule before finishing setup. Edits take effect immediately while automatic scheduling is off; once the weekly schedule is active, weaker edits retain the anti-bypass cooldown.

For an already-completed Studio Dev install with no recorded consent, automatic scheduling is off on upgrade. Its saved weekly rules are retained and shown in Schedule, where enabling them requires a confirmation that calls out an immediate lock if the current time falls in a lockout window. A legacy pending change blocks enabling until it settles, so a proposed rule cannot obscure the rule that would actually apply. Existing production installs continue using their saved schedule. Consent is local-only so it does not alter the encrypted settings wire format or migrate another device's preferences.

Remote-only does not mean enforcement is disarmed: the full runtime still handles separately authorized fixed-duration remote commands, and active durable remote or scheduled deadlines remain authoritative until they expire or are released by the existing policy. The effective all-days-off automatic schedule is reflected in the device status digest; the saved weekly rules remain editable for later opt-in.

## Release and rollback

Do not install a candidate over the user's active Studio Dev app until hosted native tests and review pass. Test both an old completed Studio Dev settings store and a fresh store; verify the saved schedule remains intact, the UI explains remote-only mode, and a command deadline remains enforceable. A code rollback to the previous build could re-enable an old unconfirmed Studio Dev schedule, so rollback of this policy requires an equivalent consent guard or a deliberate user-approved schedule change first. No installation or preference migration is performed by this source change.
