# DMG installer assets

Branded art that `scripts/build-dmg.sh` layers into the disk image. Both files
are **optional** — the script falls back to plain Finder chrome when they're
absent, so CI never breaks if they're missing.

| File | Size | Purpose |
| --- | --- | --- |
| `background.png` | **1160×800** (@2x of the 580×400 install window) | The install-window backdrop: sundown sky, "Curfew" wordmark, and a drag arrow into the Applications drop-ring. |
| `volume.icns` | — | Optional custom mounted-volume icon. Not committed yet; drop one here to use it. |

## Layout contract

The background is designed against the fixed icon positions in
`build-dmg.sh` (window points → @2x pixels):

- App icon — window `(140, 180)` → pixel `(280, 360)` (left)
- Applications drop-link — window `(440, 180)` → pixel `(880, 360)` (the dashed ring)

If you move the icons in `build-dmg.sh`, regenerate the art against the new
positions.

## Regenerating `background.png`

The source is a Figma file (Hypertext Studio team): **Curfew DMG Installer
Background** — sundown gradient from the app's `LockoutBackgroundView`. Export
the `DMG Background` frame as PNG @1× (it's authored at 1160×800). Preview the
result in a real disk image with `just dmg`.
