# Complete the Curfew rest experience

## Spec

The approved product specification is [rest experience features](../rest-experience-features.md). The app and optional native screensaver share local appearance and absolute-time scene inputs. Sunrise is optional and follows scheduled unlock; presentation never grants restriction release or bypasses authentication.

## Global constraints

Preserve enforcement, current native window retention, reflection drafts, normal Debug workspace presentation and the actual global accessibility audit. Keep these features isolated from the existing release candidate. No remote schema or account-sync expansion. Production activation and public installer publication remain held. Actual local native, screensaver-host and physical power execution require the allocated isolated Mac; hosted validation is intermediate evidence only. No polling automation or new runner system. Use failing-first tests, mandatory docs, formatting and strict lint for each substantive increment. Keep source and physical acceptance distinct.

## Task 1: Local appearance persistence contracts

Add tests before implementation for `RestAppearancePreferences` and a separate `RestAppearancePreferencesStore`; do not add fields to synced `CurfewSettings`. Defaults preserve Sundown animated atmosphere, rounded system clock, centered ambient clock, no message and automatic wake disabled. Cover partial/default decoding, invalid choices and values, 140-character Unicode message normalization, focal-point bounds, owned image reference validation, 5–60 minute Sunrise lead with 30 default, battery opt-in and separate saver message opt-in. Verify store recreation and sync-payload isolation. Establish actual behavioral failing-first evidence before implementing persistence. Missing symbols or compile errors are not behavioral RED.

## Task 2: Shared deterministic scene contract

Introduce `RestSceneSnapshot` with version, expiry, appearance and optional occurrence lock/unlock timestamps only. Resolve all-day, night, Sunrise and morning using absolute time; missing/expired occurrence data is neutral. Verify identical resolution for app and companion inputs, midnight, unlock and lead boundaries, clock changes and malformed/oversized export. It contains no enforcement authority, drafts, journal, account or recovery data. Establish failure before implementation. Keep visual rendering outside Foundation-only CurfewKit.

## Task 3: Customization and image ownership

Build a shared internal visual module from the existing sky/clock composition. Add an authored Rest Screen settings destination, live preview and all approved controls. Import JPEG/PNG/HEIC using a system picker; copy optimized bytes to owned storage, crop aspect-fill using adjustable focal point, validate dimensions and cap the exported rendition at 3840 pixels and 2 MiB. Always protect text contrast. Images survive original removal and fail safely on corruption; do not expose file paths in exported scene data. Cover persistence, removal and accessibility; review all presets and motion/transparency variants.

## Task 4: Native screensaver and presentation exchange

Add `Curfew.saver` at macOS 26 with supported host architectures and shared renderer. Implement preview/fullscreen start/stop, bounded decoding, all-day and schedule-aware composition. Use module-specific ScreenSaverDefaults, not assumed App Group access. Prove app-to-actual-host readback before further integration. Publish image only when appearance changes; never export private content. Package independently versioned companion, explicit installation/settings/update/removal and mismatch handling. Do not sign or publish held artifacts.

## Task 5: Bidirectional handoff

Add presentation-only handoff coordinator: 60 seconds idle after reflection is resolved, cancellation on input, no handoff during editing/confirmation/recovery, explicit Rest now. Settle controls and clock before requesting the publicly resolved system screensaver through NSWorkspace. Preserve drafts/native hosts and restore only after fresh authority/time resolution. Handle unavailable launch, wrong saver and authentication interruption with useful setup action. Do not modify saver selection or simulate input. Verify repeated transitions, focus and workspace restoration on an allocated Mac.

## Task 6: Sunrise local plan and helper scheduling

Introduce helper-local `SunriseWakePlan`, authenticated replace/cancel operations, fixed kIOPMAutoWake, owned identity and durable reconciliation. Validate occurrence, bounds, caller and power policy; cancel only owned events. No power-on-from-shutdown. Reconcile schedule/timezone/DST/settings/power and teardown. Cover replacement/dedup/rejection/crash recovery/scoped cancellation before behavior changes. Keep wire-format schemas unchanged.

## Task 7: Sunrise display delivery

Use IOPMAssertionDeclareUserActivity for display asleep/Mac running and a bounded display-sleep assertion until unlock plus five minutes. Reconcile system wake without duplicate delivery; recheck AC/battery before display activation. Disable/dismiss/uninstall releases assertions/cancels owned wakes. Separate scheduled/helper unavailable/request rejected/battery excluded UI states. Visual tint/luminance only, no hardware brightness/gamma changes. API success does not prove monitor illumination.

## Task 8: Integrated native and artifact acceptance

Resolve existing actual accessibility acceptance gaps without filtering/suppression and remove temporary diagnostics. Validate combined native source, standard Debug/Release builds and all tests/format/lint. On allocated isolated Mac verify actual saver preview/fullscreen readback, transitions/authentication, VoiceOver/keyboard/workspace restoration, two displays, physical display/Mac sleep on AC/battery, black resume and overnight-on. Record API, machine, monitor and visible-render results separately. Verify independently versioned app/companion packaging without production activation or public installer publication. Preserve reversible history and existing release source ownership.
