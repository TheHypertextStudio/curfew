# Horizon launch design

Curfew helps someone stay accountable for finishing work by the end of the day
and being ready to start the next one. This document is the shared reference for
the launch redesign: the look, the words, the screens, the data, and how the
work is split into pull requests.

Two working prototypes are the normative reference for anything this document
does not spell out. Open them in a browser.

- `Documentation/design/horizon-prototype.html`: the sky, Today, the lockout,
  Sunrise, setup, icons. Its fragment shader is the definition of the sky.
- `Documentation/design/journal-prototype.html`: the Journal in week, month and
  year, the patterns, the day table and the year in review card.

## Principles

1. **Nothing on screen that the person does not act on.** No status pills, no
   schedule facts, no counts of the app doing its job.
2. **Every mark is something the person did.** A lockout happening is not an
   achievement. When they stopped, whether they did the one thing, and what
   extra time they took are.
3. **One hand for the sky.** Hard-edged steps of light. No water, bloom, grain,
   ticks, stars or gradients.
4. **Glass only on controls that float over the sky and can be pressed.**
5. **One type family.** San Francisco, rounded for numerals, headlines and
   buttons.
6. **Dry and firm.** Short, certain sentences. The playfulness is in the
   confidence.

## Words

One word per thing, everywhere, including Settings, intents, notifications and
the widget.

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

Rules: sentence case; no exclamation marks; no dashes used as punctuation; times
come from the locale formatter, never hard-coded 24-hour strings; a control says
what happens when pressed.

### Default voice

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

Voice lines live in one voice pack type so the theme editor can swap them. No
string for these moments is written inline in a view.

## The sky

The sun is the person's working day. It rises at the scheduled unlock, crosses
the sky, and meets the horizon at curfew, including any extension. Overnight
the moon crosses in the night's actual phase. The scene is never a picture of
the weather outside.

### Model (pure Swift, in `CurfewAtmosphere`, covered by `swift test`)

Inputs: now, the working day's start, the effective curfew, the next unlock.
Outputs, all unitless, in a frame where x runs 0 to 1 left to right and y runs
0 to 1 bottom to top:

- Horizon at `y = 0.26`.
- Sun path: quadratic from `(x0, 0.26)` through control `(mid, 1.6)` to
  `(x1, 0.26)`, with `x0 = 0.07`, `x1 = 0.93` on full-bleed surfaces. A surface
  with a sidebar passes its own span. Progress `p = (now - start) / (curfew -
  start)`. The moon uses the same path with progress across the night.
- Elevation `E`: `sin(pi * p)` by day; by night
  `-0.9 * min(1, minutesSinceCurfew / 70, minutesToUnlock / 35)`.
- Sun weight: 1 by day; fades out from 5 to 45 minutes after curfew while the
  sun continues below the line; fades in from 40 to 5 minutes before unlock.
- Moon weight: fades in from 5 to 50 minutes after curfew and out from 50 to 10
  minutes before unlock. Moon phase angle comes from the date.
- Band phase: advances 0.05 bands per second while the day is running, holds
  still while locked and under Reduce Motion.

### Field, steps and colour

The prototype shader is authoritative. In summary: brightness is the screen
blend of a falloff around the sun, a falloff around the moon and a falloff above
the horizon that strengthens when the sun is low. Brightness is quantised into
14 steps with anti-aliased edges. Each step takes its colour from a five-stop
ramp chosen by elevation, and higher bands shift toward night first so night
falls from the top. Sun disc radius is 0.05 of the height; moon 0.04 with a
terminator from the phase angle. Below the horizon is one flat ground colour.

Ramp stops, as sRGB fractions, from far sky (0) to nearest the light (4):

| Stop   | Day           | Last hour     | Dusk          | Night            |
| ------ | ------------- | ------------- | ------------- | ---------------- |
| 0      | .10 .27 .66   | .15 .17 .46   | .07 .08 .24   | .027 .031 .094   |
| 1      | .22 .44 .82   | .38 .27 .60   | .20 .15 .42   | .047 .059 .165   |
| 2      | .44 .64 .91   | .74 .38 .55   | .50 .22 .45   | .10 .12 .31      |
| 3      | .70 .82 .95   | .95 .56 .27   | .83 .34 .30   | .135 .155 .37    |
| 4      | .94 .96 .98   | 1.0 .84 .52   | .96 .62 .30   | .19 .21 .46      |
| Ground | .07 .11 .29   | .11 .085 .25  | .065 .05 .18  | .018 .02 .055    |

The palette near the sun in the last hour reads slightly muddy in the
prototype. Tuning the last-hour stops 2 and 3 is in scope for the foundation
work, judged on rendered output.

### Rendering

- On screen: a Metal shader driven through SwiftUI's shader support, fed by the
  model. The `.metal` source belongs to the app and screen saver targets, not to
  the Swift package, so `swift build` and `swift test` stay independent of the
  Metal toolchain.
- A CPU reference renderer in `CurfewAtmosphere` evaluates the same field to a
  `CGImage`. It backs unit tests (fixed points must match the table above), the
  headless snapshot harness if shaders do not render there, the widget, the
  year in review export, and the still frame used under Reduce Motion.
- The screen saver renders the same scene from the same model.

## Type, shape, glass, icons, motion

- **Type.** System font. Rounded design for numerals, headlines and buttons;
  default design for body. No serif and no spaced capitals. Sizes scale with the
  system text size. Tabular figures only where numbers align in columns.
- **Shape.** Three radii as tokens: 8 for controls, 20 for panels, capsule for
  floating buttons. Spacing steps 4, 8, 12, 16, 24, 40, 64. Other values are
  replaced.
- **Glass.** System Liquid Glass only: the two Today actions, the Sunrise
  button, the warning notice, and the system sidebar and toolbar. Grouped
  controls share one glass container so they morph together. The imitation
  glass helpers and the extra material under the sidebar are removed. Reduce
  Transparency gives solid panels; Increase Contrast adds an outline.
- **Content pages.** Schedule, Journal and Settings follow the system
  appearance on the existing paper and ink tokens with ember as the only accent.
  The sky is used on Today, the lock, Sunrise, setup and the year in review.
- **Icons.** SF Symbols at the text weight, leading every control and status
  line: sunset for curfew, sunrise for Sunrise, lock for locked, open lock for
  override, a clock-with-plus symbol for more time, circle and checked circle
  for the one thing, moon for last night's note, sun for Today, calendar for
  Schedule, book for Journal. Confirm each symbol exists before using it. The
  menu bar icon is drawn: a sun over a line that sits lower as curfew nears,
  rests on the line in the last half hour, and is absent while locked.
- **Motion.** Curfew arriving is one move of about two seconds: the sun meets
  the line, colour cascades down the bands, the actions sink below the horizon,
  the clock stays centred and grows. Morning runs it backwards and fades to the
  desktop instead of cutting. Numerals roll when they change. Holding a button
  fills it. Reduce Motion replaces the move with a short fade and freezes the
  bands.

## Screens

### Today

Sky above the horizon: the countdown, then "until curfew at (time)" with the
sunset symbol, then two glass buttons. Ground below: the one thing with a
circle to tick, or "What is today for?" as a field when there is none.

- **15 more minutes** is hold to confirm. The remaining count shows only while
  holding. It moves curfew, so the sun steps back.
- **Call it a day** is hold to confirm. It opens the evening close-out and then
  locks. It records that the person ended the day themselves.
- Removed: the status line, the streak chip, the scheduled unlock line, and any
  duplicate statement that Curfew is off.
- Off: still sky, "Curfew is off.", one button to turn it on.

The menu bar popover carries the same countdown, the one thing and the same two
actions.

### Warnings

A glass notice with the stage line and the countdown. Notification titles and
bodies use the voice table. No snooze labelled in implementation terms.

### Locked

The same scene after dark: the clock, "That's the day.", "Unlocks at (time)"
with the lock symbol, and one quiet text button, "Need to get back in?". The
override composer asks "What can't wait?", shows progress toward the minimum
length, and its hold to confirm has a keyboard and VoiceOver path.

The evening close-out asks its questions on this scene and adds one: whether
the one thing was done, as a yes or no.

Idle behaviour: by default Curfew hands off to its own bundled screen saver,
which shows this same scene, and only once that saver has proven it renders.
Handing off to the Mac's selected screen saver is an option, offered only when
System Settings has one selected. Curfew never launches a foreign screen saver
unless that option is on.

### Sunrise

1. **Lead-in.** From the configured lead before unlock the sky warms and the
   screen says "Nearly morning." and "Unlocks in N minutes".
2. **Gate.** At unlock: "Morning.", last night's "left for next time" answer,
   the question "What is today for?", and "Start the day". Answering releases
   the Mac.
3. **Release.** The scene fades to the desktop.

- The gate is an ordered list of steps the person can choose and reorder:
  last night's note, the one thing, readiness, and their own questions. Each
  step is required or skippable. The default is note, then the one thing
  (required), then readiness (skippable).
- The gate also appears on the first use of the day after a cold start, when
  the morning is still unanswered.
- After the gate, Curfew can run one Shortcut the person picked, passing the
  one thing as input. App Intents expose today's one thing and "when Sunrise
  completes" and "when curfew starts" for automations.
- Self-wake is an option inside Sunrise settings, off by default, labelled with
  what it needs: the Curfew helper, power, and an open lid.
- Sunrise settings are their own pane, not a section of rest screen appearance.

### Setup

Three steps, about four clicks, one drag, one authentication.

1. **When should this Mac close for the night?** Two time pickers and day
   chips, prefilled. A small link keeps the explicit "no schedule yet" choice.
2. **Let Curfew hold the lock.** Opens the Accessibility pane with a floating
   panel beside it holding the app icon to drag into the list. Setup advances
   the moment access is granted. Notifications and the helper are requested on
   this screen, each with one line saying why.
3. **You're set. Curfew locks tonight at (time).** A button previews the lock.

Then one optional closing step: sync across devices with Sign in with Apple,
Google or a passkey, and the lifetime licence. Skip is as prominent as
continue.

Health warnings stay hidden until setup completes. A fresh install that
finished setup shows no warning. The helper is not required for a healthy
state; without it the app says once, plainly, what is weaker.

### Journal

Charts first, as in the prototype. A range control (week, month, year) scopes
everything below it.

- One sentence: how many days ended before curfew, how many the lock ended, how
  many ran over.
- Four tiles: stopped before curfew, did the one thing, extra time taken, felt
  ready in the morning. Each compares with the previous period and carries a
  trend line.
- Main chart: one column per day around the curfew line. Up is early, down is
  over, a small neutral mark means the lock ended the day. Two rows under it
  show the one thing and readiness. In year range it becomes a grid of every
  working day.
- Patterns: at most three sentences, each with a small chart and the number of
  days behind it. A weekday pattern needs four of that weekday and a ten minute
  gap. The readiness pattern needs five mornings of each kind and a twelve
  point gap. Otherwise the card says there is nothing to report yet.
- Extra time, in your words: each override with the reason typed.
- Every day: a table that is also the accessible twin of the charts. A row
  opens that evening's timeline and what was written.
- Year in review: the year's marks on the line over the sky, with four totals,
  saved or shared as an image.

Chart colours, validated for colour-blind separation on the app's surfaces:

| Role             | Light     | Dark      |
| ---------------- | --------- | --------- |
| Before curfew    | `#2f62c8` | `#5f8fe8` |
| Over             | `#c9521d` | `#dd6c3a` |
| At curfew        | `#9a958e` | `#7d766f` |
| Early, 3 steps   | `#8aabe7` `#5a84d8` `#2f62c8` | `#41609f` `#5078cc` `#5f8fe8` |
| Over, 3 steps    | `#e79f78` `#da7644` `#c9521d` | `#8a4326` `#b85a32` `#dd6c3a` |

Text never takes a data colour. Early is always up and over is always down, so
nothing depends on colour alone.

### Settings, copy and the rest

- Rest screen and Sunrise appear in the Settings sidebar.
- The three background rows collapse into one "Curfew helper" row with one
  action and plain status.
- Developer detail (ports, selector ids, poll times) is not shown in the
  production flavour.
- Asking for Automation access happens when auto-shutdown is switched on, not
  during the first shutdown.
- The widget shows the countdown and the line. It has no streak.
- Unused views and the "design proposal" comments are deleted.

### Theme and voice

A theme is a sky palette, a clock style and a voice pack. The editor previews
the rest screen at full size and changes each in place.

## Data

Two facts are new. Both are local; neither changes a wire format.

- **How the day ended.** One record per working day: the time the person
  stopped and whether they called it a day, the lock ended it, or they took
  extra time (extension or override, with minutes). "Stopped" is the earliest
  of calling it a day and the lock.
- **Whether the one thing was done.** A yes or no answered in the evening
  close-out, stored against that day's one thing.

The Journal reads a per-day record (curfew, stop time and how, extra minutes,
override reason, the one thing and whether it was done, readiness, evening
answers) and period summaries built from it. The lockout-count rollup and the
streak are removed once nothing reads them.

## Accessibility

- Every control that is hold to confirm has a keyboard and VoiceOver action.
- The lock announces itself and moves focus to the clock.
- Icon-only controls have labels. Charts have labels and the table twin.
- Reduce Motion, Reduce Transparency and Increase Contrast each have a defined
  alternative, listed above.
- Text scales with the system size on every surface, including the lock.

## Pull requests

Each is its own branch and worktree. Files listed are owned by that pull
request; another pull request does not edit them.

| #   | Outcome                                             | Owns                                                                                                                                      | Needs      |
| --- | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| A   | Sky model, shader, tokens, glass styles, icons      | new `Horizon*` in `CurfewAtmosphere` and `Curfew/UI/Horizon`, `CurfewTheme.swift`, `Curfew/UI/Sundown/*`, `SundownType.swift`, snapshot harness | none       |
| F   | Record how the day ended and the one thing; summaries | `ActivityEvent*`, `ActivityRollups.swift`, new Journal domain types in `CurfewKit`, model wiring without UI                               | none       |
| B   | Today, menu bar, Call it a day                      | `TodayView.swift`, `TodaySundownView.swift`, `ContentView.swift`, menu bar label, `+Presentation`, `+Actions`                              | A, F       |
| C   | Lock, warnings, transitions, screen saver handoff   | `LockoutScreenView.swift`, `RestScreenView.swift`, `LockoutArrivalView.swift`, `OverlayCoordinator*`, warning notice and notifications, rest handoff, `CurfewScreenSaver/*`, the message catalog | A, lockout hardening |
| D   | Sunrise gate, steps, hooks, settings pane           | `DaybreakReflectionView.swift` and its replacement, `+Reflection`, `+Sunrise`, reflection defaults, Sunrise settings, new intents          | A          |
| E   | Three-step setup, drag helper, health seeding       | `GettingStarted*`, `SystemSurfaceModels.swift`, health seeding, the drag panel, helper required-ness, licence and account step             | A          |
| G   | Journal and year in review                          | `Curfew/UI/Destinations/Journal*`, `RatingTrend.swift`, `ThisWeekView.swift`, new Journal views                                            | A, F       |
| H   | Copy, Settings, widget, accessibility sweep         | `SettingsView*`, `ScheduleView.swift`, `DayRuleRow.swift`, `ReflectionPromptsView.swift`, intents copy, `CurfewWidget/*`, `copy-guidelines.md` | A          |
| I   | Theme and voice editor                              | `RestScreenSettingsView.swift`, `RestAppearance*`, voice packs                                                                             | C          |

## Verification

- Unit tests for the model, the CPU renderer, the day record and every pattern
  threshold.
- `just snapshot` for every changed surface in light and dark, looked at, not
  only produced.
- What unit tests cannot show is listed in each pull request: real lockout
  focus and kiosk behaviour, the drag into System Settings on a signed build,
  self-wake on hardware, and the screen saver handoff.
