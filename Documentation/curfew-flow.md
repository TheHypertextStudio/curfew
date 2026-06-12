# The Curfew Flow

This document is the canonical definition of **the Curfew Flow** — the
immersive, full-screen arc Curfew runs the user through across the boundaries
of a working day. The term has been implicit in the product; this is where it
is pinned down so design and engineering share one vocabulary.

## Definition

The **Curfew Flow** is the full-screen, attention-commanding experience that
spans a day from its first session to its shutdown. It is not a single screen —
it is the ordered sequence of surfaces Curfew presents as the day opens,
runs down, and closes:

```
SUNRISE            DAY                 DUSK                 SUNDOWN             NIGHT
morning intent  →  working window  →   warnings (T-30 …  →  lockout overlay  →  optional
(full-screen       (normal use)        T-1, escalating      + evening           shutdown
 reflection)                           dim + timer)         reflection
```

The visual language is **sundown**: the working day ends as the light fades,
the lockout is a dusk/night sky, and — new with reflection gates — the day
*opens* at **sunrise**. The two ends of the day are deliberately symmetric.

## Phases

### 1. Sunrise — morning intent (reflection gate)

At the day's first session (the transition into the `.working` phase, i.e. the
daily unlock), Curfew raises a full-screen **Daybreak** overlay on every
display. It commands the screen with the same presence as the lockout — the day
genuinely starts here — but it is **leniently skippable**: a visible *Skip*
hands the Mac back instantly and the gate never re-prompts that day. The user
answers a short, configurable set of prompts (a focus question, a mood
check-in by default). It is *not* enforcement: there is no key interception, no
respawn, no shutdown coupling.

Surface: `DaybreakReflectionView` + `DaybreakBackgroundView`, presented via
`OverlayCoordinator.syncDaybreakOverlay(presented:model:)`.

### 2. Day — the working window

Normal use. The enforcement engine ticks once per second, tracking time (and,
in hours-based mode, active minutes) toward the day's lock.

### 3. Dusk — escalating warnings

From T-30 down to T-0, Curfew escalates: a deepening dim overlay, a floating
countdown timer in the last minutes, and system notifications. The user may
spend an **extension** (hold-to-confirm) to push the lock back.

Surfaces: `OverlayCoordinator` warning + timer windows, `WarningStage`.

### 4. Sundown — lockout + evening reflection (reflection gate)

At T-0 the **lockout overlay** takes over every display at `.screenSaver`
level, capturing input (⌘⇥ / ⌘Q / ⌘⌥Esc are intercepted). It shows the time,
an encouragement message, the unlock time, and the **"Convince Me" override**
flow.

When the evening reflection gate is enabled and unresolved for the day, the
**evening reflection** is presented *inside* this lockout screen as the
optional shutdown ritual — the chosen placement (vs. a pre-lockout gate). It is
**non-blocking**: saving or skipping it never delays or weakens enforcement;
the clock and override flow remain below it.

Surfaces: `LockoutScreenView` + `EveningReflectionCard`, `LockoutBackgroundView`,
`LockoutKeyInterceptor`.

### 5. Night — optional shutdown

If auto-shutdown is enabled, after a configurable delay Curfew gracefully
terminates apps and shuts the Mac down. The privileged daemon keeps the
deadline armed across force-kill / reboot.

## Reflection gates

The two reflection gates bracket the working day and are the user-facing
"reflect when you start, reflect when you stop" loop (à la Sunsama):

| Gate            | When                        | Surface                       | Placement decision                |
| --------------- | --------------------------- | ----------------------------- | --------------------------------- |
| Morning intent  | day's first session (unlock) | full-screen Daybreak overlay  | immersive, leniently skippable    |
| Evening retro   | lockout begins (sundown)     | inside the lockout screen     | optional shutdown ritual          |

Each gate prompts **at most once per day** — a saved or skipped gate is marked
resolved (`reflectionGatesResolvedToday`, reset on day rollover and seeded at
launch from the store so a relaunch doesn't re-nag).

### Data

- Prompts are **user-editable with defaults** (`ReflectionConfiguration`,
  seeded from `ReflectionDefaults`; edited in Settings → Reflection). Answers
  are **mixed**: free text, a 1–5 rating, or a five-point mood pick
  (`ReflectionValue` is a sum type — no struct-of-optionals).
- Reflections are stored in a dedicated SQLite store (`ReflectionStore`,
  mirroring `ActivityStore`) at `SharedPaths.reflectionDatabase`. A lightweight
  `ActivityEventKind.reflectionRecorded` marker is also written to the activity
  log (carrying the gate in `gateKind`) so timelines note *that* a reflection
  happened without duplicating content.
- The **Journal** charts reflections below the week's sundown chart
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
  reflection moment between sunrise and sundown.
