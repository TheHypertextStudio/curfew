# Liquid Glass icon (macOS 26 / Tahoe)

The shipping app icon is the **Icon Composer document** at `Curfew/AppIcon.icon`
— a glass sun layer (`Assets/sun.png`) over a gradient background, masked to the
squircle and rendered with Liquid Glass specular by the system. The build picks
it up through the `Curfew` synchronized group, and `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
points at it; the old flat `.appiconset` is retired. `actool` compiles it into
the bundle's `Assets.car`.

## Light / dark by system appearance

The icon follows the system appearance automatically — no runtime code. This is
driven by the `fill-specializations` array in `icon.json`: the first entry (no
`appearance` key) is the default **light** sundown (purple `#4D3D6B` → orange
`#ED7538`), and the `"appearance": "dark"` entry repaints the sky a deep indigo
night with a faint ember horizon (`#0F0F24` → `#522A2B`). `actool` bakes both
into `Assets.car` as `NSAppearanceNameAqua` / `NSAppearanceNameDarkAqua`, and
the system swaps them with the user's Light/Dark setting. The tinted/clear
appearances are generated from the same layers. The sun glyph is shared across
both; only the background gradient specializes.

This replaced the old runtime time-of-day Dock swap (`DockIconController` +
`TimeOfDay`, both removed): appearance is a cleaner, system-driven signal than
wall-clock time, and the `.icon` mechanism covers the bundle icon everywhere
(Finder, Dock, Launchpad), not just the running Dock tile.

## Editing the icon

`icon.json` is plain, hand-authorable JSON — small tweaks like the gradient
stops above can be edited directly and validated with
`xcrun actool Curfew/AppIcon.icon --compile /tmp/out --app-icon AppIcon
--platform macosx --minimum-deployment-target 26.0 --output-partial-info-plist
/tmp/out/p.plist`. For structural changes (new layers, specular/blur/opacity
tuning), use **Icon Composer** (Xcode → Open Developer Tool → Icon Composer),
which renders the dynamic Liquid Glass lighting live. The recipe below records
how the layers were originally prepared to Apple's export rules.

## Why the layers, not the flat PNG

Per Apple ("Creating your app icon using Icon Composer"): design the icon as
**layers**, 1024×1024, back-to-front, and **strip blur, shadow, specular,
opacity, translucency, and background gradients** from the exported layers —
those are applied *in* Icon Composer, where Liquid Glass renders them
physically. So the flat composited PNG is the wrong input; clean layers are.

## Source

The layered artwork lives in the Figma file **"Curfew App Icon"**
(`figma.com/design/RLIsUOACEFclV4N8c6LV5Y`). Each variant frame is built from
discrete shapes (sky, sun base, sun core, horizon, reflection). For Icon
Composer, export only the **foreground glyphs** as SVG (vectors scale best;
convert any text to outlines), and set the background in Icon Composer.

Recommended layer stack for the dusk (signature) icon, back → front:

| Layer | What | Export |
| --- | --- | --- |
| Background | sundown sky gradient | set in Icon Composer's Background as a vertical gradient (stops below), *not* a layer |
| `1-sun` | the sun disc (flat, no glow) | SVG — Icon Composer adds the glass + specular |
| `2-horizon` | the thin horizon bar | SVG |

Dusk background gradient stops (top → bottom):
`#131526` → `#2A2342` → `#80493C` → `#E67A48`

(The water reflection and the sun's halo are *not* layers — let Icon Composer's
glass/specular create that depth.)

## Steps

1. Xcode → **Open Developer Tool → Icon Composer** (or download it from
   developer.apple.com/icon-composer).
2. Name the file **AppIcon** (matches the build setting later). Set the
   **Background** to the gradient above.
3. Drag the foreground SVGs into the sidebar; they become layers. Put them in a
   Group so Liquid Glass treats them together (Combined), or separately
   (Individual) if you want per-layer glass.
4. In the inspector, tune **specular**, **opacity**, and **blur** while
   previewing dynamic lighting. Annotate the dark / clear / tinted appearances.
5. **File → Save** as `AppIcon.icon`.
6. Add `AppIcon.icon` to the Xcode project (target → General → App Icons, or
   drag it in). **It replaces the asset-catalog AppIcon** — Xcode auto-generates
   the macOS-pre-26 fallback from it. Keep the `.appiconset` only if you want a
   different look on older releases.

## Historical: the time-of-day Dock variants

Earlier builds skinned the running Dock tile by the hour via `DockIconController`
setting `NSApp.applicationIconImage` from `DockIcon{Dawn,Day,Dusk,Night}` image
sets. That controller and its `TimeOfDay` model were removed in favour of the
appearance-driven `.icon` above. The four `curfew-icon-{dawn,day,dusk,night}.png`
renders (and `generate-app-icon.swift`) are kept only as design references for
the sundown palette; they are no longer wired into the app.
