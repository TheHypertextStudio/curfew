# Literal product copy

This note is for maintainers editing Curfew's visible text. Describe the observed state, available action, and consequence before shipping a copy change.

## Claims and wording

Curfew is set to enforce a schedule when enabled. Missing Accessibility access means keyboard shortcut blocking is unavailable. Other enforcement capabilities retain their own state; do not describe the whole app as stopped or fully protected based on Accessibility alone.

Presence reminders use an additional delay after idle detection, which starts at five minutes without input. The default three-minute delay therefore allows a first reminder after about eight minutes, provided the camera continues to detect a person. Lockout messages describe blocked access without assuming a scheduled cause; remote commands can lock access during work hours or on a day off.

Keyboard or pointer inactivity means no recent input. It does not establish that someone stopped working. The optional camera estimates whether a person is present; it cannot identify the person or determine whether they are working.

Protected applications skip Curfew's application termination step. A system shutdown still stops them. Protected work can delay termination and shutdown up to the configured limit. It does not unlock the screen or change the schedule.

Name the scheduled unlock time when available. Today describes countdowns and unlock times as scheduled events, including when enforcement is off. Do not assume every schedule ends at night or resumes in the morning. Use “delay shutdown” for deferrals and retain “hold” for physical confirmation gestures. Keep technical command names such as `break-glass`, then explain what they suspend.

Journal counts describe recorded lockouts. Use “days with lockout” and “Lockout recorded.” A day without a recorded lockout does not necessarily mean the user configured a day off. Ordinary warmth such as “Rest well” remains appropriate. As of October 20, 2026, overrides require a five-minute wait, a reason of at least 50 characters, and a three-second hold. This wait is separate from the schedule-change cooldown.

## October 4, 2026 audit

The copy audit corrected app controls, setup, notifications, presence, permission guidance, reflections, summaries, CLI and MCP descriptions, the extension description, landing pages, and current user documentation. Shared providers supply repeated schedule and health wording. Localization entries retain existing translations and interpolation placeholders.

Regression tests check Today controls, notification payloads, presence descriptions, health guidance, weekly-summary pluralization, shutdown messages, setup, consent, default prompts, connection status, MCP descriptions, and the extension manifest. Native captures and browser checks verify the changed screens and pages. The privacy storage table scrolls within its own region on narrow screens, so long file paths do not widen the page.

The audit changes no command names, wire fields, enforcement decisions, or stored user text. New and reset configurations use the revised default reflection prompts; saved prompts and answers retain their text. Historical design records and legal commitments remain intact. Copy can be reverted without a data migration, but reverting would restore the inaccurate claims. Unsigned tests and renders do not establish signed macOS permission behavior; see [system permission recovery](system-permissions.md).

## Deployment validation

The October 4 follow-up review found two incorrect claims: the reminder delay omitted the five-minute idle-detection threshold, and the default lockout message attributed remote locks to scheduled work hours. Both now describe the existing behavior. A day-off remote-lock regression and reminder-interval regression failed before the copy fixes. The landing contract also now checks macOS 26 support without requiring an unsupported Android release timeline.

The October 23 rebase passed the macOS unit suite, package tests, repository checks, strict lint, formatting, extension tests, and extension typechecking. The extension production-mode build uses a test identity and proves compilation only. Local website validation is blocked because the existing GitHub credential cannot read the private Studio packages. An offline install also failed. The current release pipeline must establish signed runtime and production deployment acceptance separately; older Pages credential results do not describe the current hosting configuration.
