# Literal product copy

This note is for maintainers editing Curfew's visible text. Describe the observed state, available action, and consequence before shipping a copy change.

## Voice

Curfew is dry and firm: short, certain sentences, with the playfulness in the confidence. Nothing on screen reports the app doing its job. A control says what happens when pressed, and every state that needs attention offers a way forward.

Use one word per thing, everywhere, including Settings, intents, notifications and the widget.

| Thing                                | Say                         | Never say                                           |
| ------------------------------------ | --------------------------- | --------------------------------------------------- |
| The time work ends and the Mac locks | curfew                      | lockout time, scheduled lockout, work ends          |
| The state after curfew               | locked, the lock            | lockout active, enforcement, blocking access        |
| The morning sequence                 | Sunrise                     | daybreak, start of work, morning reflection         |
| The answer to "What is today for?"   | the one thing               | intention, focus, goal                              |
| Ending the day early on purpose      | Call it a day               | rest now, wrap up                                   |
| More minutes before the lock         | more time, "15 more minutes" | extension request, snooze, grace                    |
| Getting back in after the lock       | override                    | convince me, break glass                            |
| The machine                          | this Mac                    | computer, device                                    |
| The background piece                 | the Curfew helper           | daemon, supervisor, background protection, recovery |

Write in sentence case, including buttons, sidebar titles and intent titles. Use no exclamation marks and no dashes as punctuation. Take times from the locale formatter, never a hard-coded 24-hour string, and write countdowns as hours and minutes (“2:30”). Use American spelling. Keep implementation words (daemon, supervisor, enforcement, policy, warning stage tokens, request identifiers) out of anything a person reads; ports, poll times and raw identifiers appear only with developer detail.

Place help text by what it explains. Text about one control sits in that control's row, under its label, in secondary text. Text about a whole group is one footer under the group's box. Help text is never a row of its own, and live status belongs under the label of the control it describes. A warning that needs an action is one row holding the message and its button.

These are the default lines for the moments people see most.

| Moment                    | Line                                                                   |
| ------------------------- | ---------------------------------------------------------------------- |
| Today, under the countdown | until curfew at 6:00 PM                                               |
| 30 minutes left           | Decide what gets finished and what waits.                              |
| 15 minutes left           | Finish what you're in. Don't start anything.                           |
| 5 minutes left            | Save everything.                                                       |
| 1 minute left             | Last call.                                                             |
| Notification titles       | 30 minutes to curfew (and 15, 5, 1)                                    |
| Locked, headline          | That's the day.                                                        |
| Locked, line              | Unlocks at 7:00 AM                                                     |
| Override entry            | Need to get back in?                                                   |
| Override question         | What can't wait?                                                       |
| Sunrise lead-in           | Nearly morning. / Unlocks in 12 minutes                                |
| Sunrise gate              | Morning. / What is today for? / Start the day                          |
| Last night's note         | Last night you left: (their words)                                     |
| Buttons on Today          | 15 more minutes / Call it a day                                        |
| While holding             | Keep holding. 2 left this week / Added / No extensions left            |
| Curfew off                | Curfew is off. / Nothing locks until you turn it back on.              |
| Uninstall while locked    | Uninstall is available once curfew lifts.                              |

## Claims and wording

Curfew is set to enforce a schedule when enabled. Missing Accessibility access means keyboard shortcut blocking is unavailable. Other enforcement capabilities retain their own state; do not describe the whole app as stopped or fully protected based on Accessibility alone.

Presence reminders use an additional delay after idle detection, which starts at five minutes without input. The default three-minute delay therefore allows a first reminder after about eight minutes, provided the camera continues to detect a person. Lockout messages describe blocked access without assuming a scheduled cause; remote commands can lock access during work hours or on a day off.

Keyboard or pointer inactivity means no recent input. It does not establish that someone stopped working. The optional camera estimates whether a person is present; it cannot identify the person or determine whether they are working.

Protected applications skip Curfew's application termination step. A system shutdown still stops them. Protected work can delay termination and shutdown up to the configured limit. It does not unlock the screen or change the schedule.

Name the unlock time when available, as “Unlocks at 7:00 AM.” Use “delay shutdown” for deferrals and retain “hold” for physical confirmation gestures. Keep technical command names such as `break-glass`, then explain what they suspend.

A lock happening is not an achievement, so the Journal records what the person did: when they stopped, whether they did the one thing, and what extra time they took. Ordinary warmth such as “Rest well” remains appropriate. As of October 20, 2026, overrides require a five-minute wait, a reason of at least 50 characters, and a three-second hold. This wait is separate from the schedule-change cooldown.

## October 4, 2026 audit

The copy audit corrected app controls, setup, notifications, presence, permission guidance, reflections, summaries, CLI and MCP descriptions, the extension description, landing pages, and current user documentation. Shared providers supply repeated schedule and health wording. Localization entries retain existing translations and interpolation placeholders.

Regression tests check Today controls, notification payloads, presence descriptions, health guidance, weekly-summary pluralization, shutdown messages, setup, consent, default prompts, connection status, MCP descriptions, and the extension manifest. Native captures and browser checks verify the changed screens and pages. The privacy storage table scrolls within its own region on narrow screens, so long file paths do not widen the page.

The audit changes no command names, wire fields, enforcement decisions, or stored user text. New and reset configurations use the revised default reflection prompts; saved prompts and answers retain their text. Historical design records and legal commitments remain intact. Copy can be reverted without a data migration, but reverting would restore the inaccurate claims. Unsigned tests and renders do not establish signed macOS permission behavior; see [system permission recovery](system-permissions.md).

## Deployment validation

The October 4 follow-up review found two incorrect claims: the reminder delay omitted the five-minute idle-detection threshold, and the default lockout message attributed remote locks to scheduled work hours. Both now describe the existing behavior. A day-off remote-lock regression and reminder-interval regression failed before the copy fixes. The landing contract also now checks macOS 26 support without requiring an unsupported Android release timeline.

The October 23 rebase passed the macOS unit suite, package tests, repository checks, strict lint, formatting, extension tests, and extension typechecking. The extension production-mode build uses a test identity and proves compilation only. Local website validation is blocked because the existing GitHub credential cannot read the private Studio packages. An offline install also failed. The current release pipeline must establish signed runtime and production deployment acceptance separately; older Pages credential results do not describe the current hosting configuration.
