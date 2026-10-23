# The Curfew Flow

This document is for Curfew maintainers changing the sequence of full-screen
surfaces. Preserve the distinction between optional reflections and lockout
enforcement.

## Definition

The **Curfew Flow** is the ordered sequence of start reflection, work session,
warnings, lockout with an optional end reflection, and optional shutdown.
Reflections can be skipped. The lockout schedule applies whether or not a
reflection is answered.

```
START REFLECTION   WORK SESSION       WARNINGS              LOCKOUT              SHUTDOWN
optional        →  normal use      →  T-30 through T-1   →  full-screen       →   optional
full-screen                           notifications,       overlay with         application
reflection                            dimming, timer       optional end         termination and
                                                           reflection           shutdown
```

The backgrounds use sunrise and dusk sky visuals. Those visuals do not imply
that a work session starts in the morning or that lockout begins at night.

## Phases

### 1. Start reflection (reflection gate)

At the day's first session (the transition into the `.working` phase, i.e. the
daily unlock), Curfew raises a full-screen **Daybreak** overlay on every
display. The overlay covers every display. A visible *Skip* dismisses it, and the gate
does not prompt again that day. The user
answers a short, configurable set of prompts (a focus question, a mood
check-in by default). It is *not* enforcement: there is no key interception, no
respawn, no shutdown coupling.

Surface: `DaybreakReflectionView` + `DaybreakBackgroundView`, presented via
`OverlayCoordinator.syncDaybreakOverlay(presented:model:)`.

### 2. Work session

The user can use the Mac normally. The enforcement engine ticks once per
second and tracks elapsed time or active minutes toward lockout.

### 3. Warnings

From T-30 down to T-0, Curfew escalates: a deepening dim overlay, a floating
countdown timer in the last minutes, and system notifications. The user may
use an **extension** (hold-to-confirm) to delay lockout.

Surfaces: `OverlayCoordinator` warning + timer windows, `WarningStage`.

### 4. Lockout and end reflection (reflection gate)

At T-0 the **lockout overlay** takes over every display at `.screenSaver`
level, covering the desktop. Curfew blocks ⌘⇥ / ⌘Q / ⌘⌥Esc when Accessibility
access is granted. It shows the time,
a lockout message, the unlock time, and the **override** flow.

When the evening reflection gate is enabled and unresolved for the day, the
**evening reflection** is presented *inside* this lockout screen as the
optional end reflection, rather than before lockout. It is
**non-blocking**: saving or skipping it never delays or weakens enforcement;
the clock and override flow remain below it.

Surfaces: `LockoutScreenView` + `EveningReflectionCard`, `LockoutBackgroundView`,
`LockoutKeyInterceptor`.

### 5. Optional shutdown

If auto-shutdown is enabled, Curfew requests application termination and
shutdown after a configurable delay. Protected apps skip Curfew's termination
step but still stop at shutdown. Active work claims or detected work can delay
these actions within the configured limit. The privileged daemon keeps the
deadline armed across force-kill / reboot.

## Reflection gates

The two reflection gates prompt at the start of a session and when lockout
begins:

| Gate            | When                        | Surface                       | Placement decision                |
| --------------- | --------------------------- | ----------------------------- | --------------------------------- |
| Start reflection | day's first session (unlock) | full-screen Daybreak overlay | can be skipped |
| End reflection | lockout begins | inside the lockout screen | optional; does not delay lockout |

Each gate prompts **at most once per day** — a saved or skipped gate is marked
resolved (`reflectionGatesResolvedToday`, reset on day rollover and seeded at
launch from the store so a relaunch does not prompt again).

### Data

- Prompts are **user-editable with defaults** (`ReflectionConfiguration`,
  seeded from `ReflectionDefaults`; edited in Journal → Prompts). Answers
  are **mixed**: free text, a 1–5 rating, or a five-point mood pick
  (`ReflectionValue` is a sum type — no struct-of-optionals).
- Reflections are stored in a dedicated SQLite store (`ReflectionStore`,
  mirroring `ActivityStore`) at `SharedPaths.reflectionDatabase`. A lightweight
  `ActivityEventKind.reflectionRecorded` marker is also written to the activity
  log (carrying the gate in `gateKind`) so timelines note *that* a reflection
  happened without duplicating content.
- The **Journal** charts reflections below the week's lockout chart
  (`JournalReflectionsView`), with mood/rating chips for trend-spotting.

### Agent access (read-only)

Reflections are exposed read-only so assistants can use "how did the user say
the day went?" as context — never written by agents (reflections are
human-authored):

- MCP: `curfew_get_reflections` (period `today`/`week`, optional `gate`).
- CLI: `curfew-ctl reflections [--days N] [--gate morning|evening] [--json]`.

## Roadmap

- **On-device AI-generated prompts.** The prompt set is already user-editable;
  a future iteration generates/rotates prompts from the day's context (calendar,
  recent activity) using a local LLM. Surfaced as a disabled affordance in the
  Reflection settings panel today.
- **Midday check-in.** `GateKind` and the gate model already anticipate a third
  reflection moment between session start and lockout.
