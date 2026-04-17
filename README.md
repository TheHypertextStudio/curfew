# Curfew

Curfew is a macOS app that enforces a configurable daily lock window so work has a hard stop.

## What Curfew Does

- Lets you set a weekly lock/unlock schedule.
- Escalates from warnings to lockout as curfew approaches.
- Supports extension and override limits so exceptions stay intentional.
- Includes a standard app window plus menu bar quick access.

## Current Product Status

Curfew is in active MVP development. Core scheduling, warning, lockout, and setup flows are implemented, with additional integrations and polish in progress.

## Configuration UX

- Main app window: open Curfew and use the **Configuration** section.
- Settings window: available from app actions/menu bar quick actions.
- First launch: Curfew opens a getting-started flow to help set schedule and limits.

## Run

Open `Curfew.xcodeproj` in Xcode and run the `Curfew` scheme.

This repo supports using [`just`](https://github.com/casey/just) to run every common developer task from the command line without invoking `xcodebuild` directly. Install with `brew install just`, then run `just --list` to see all recipes — tests, lint, format, build, archive. The default recipe `just check` runs the full ship-gate (format check + strict lint + unit tests + Debug build) and is what CI invokes on every push.

Debug launch is safe by default:

- In `Debug`, enforcement does not auto-start unless `CURFEW_ENABLE_ENFORCEMENT=1`.
- In `Release`, enforcement auto-starts unless `CURFEW_SKIP_ENFORCEMENT=1`.
