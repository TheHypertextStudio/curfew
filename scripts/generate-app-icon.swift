#!/usr/bin/env swift
//
// Generates the four full-bleed Curfew app-icon variants (dawn, day, dusk,
// night) as 1024×1024 opaque PNGs. CoreGraphics, no external tools — so the
// art fills the canvas edge-to-edge with zero transparency or stray plate
// colour (the bug that came from cropping margined Figma exports). macOS 26
// applies its own squircle mask, so we provide a square, opaque, full-bleed
// image and let the system round it.
//
// Usage: swift scripts/generate-app-icon.swift <out-dir>
//        → writes curfew-icon-{dawn,day,dusk,night}.png

import AppKit
import CoreGraphics
import Foundation

let S: CGFloat = 1024
let HZ: CGFloat = 672 // horizon, from the top

struct Stop { let p: CGFloat; let c: (CGFloat, CGFloat, CGFloat) }
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// Flat & crisp: the upper sky is a flat field; the gradient only warms the band
// near the horizon (a glow), then a solid sea and a flat sun. No halos, no
// radial fills, no soft reflections.
struct Variant {
    let name: String
    let sky: [Stop]       // top flat → horizon glow
    let sea: (CGFloat, CGFloat, CGFloat)
    let bodyY: CGFloat
    let bodyR: CGFloat
    let body: (CGFloat, CGFloat, CGFloat)
    let night: Bool
}

let variants: [Variant] = [
    Variant(name: "dawn",
            sky: [Stop(p: 0, c: (0.17, 0.16, 0.31)), Stop(p: 0.52, c: (0.17, 0.16, 0.31)),
                  Stop(p: 1, c: (0.85, 0.54, 0.40))],
            sea: (0.13, 0.09, 0.14), bodyY: 566, bodyR: 144, body: (0.95, 0.66, 0.40), night: false),
    Variant(name: "day",
            sky: [Stop(p: 0, c: (0.24, 0.50, 0.74)), Stop(p: 0.55, c: (0.24, 0.50, 0.74)),
                  Stop(p: 1, c: (0.73, 0.85, 0.93))],
            sea: (0.43, 0.63, 0.78), bodyY: 360, bodyR: 146, body: (1.0, 0.84, 0.42), night: false),
    Variant(name: "dusk",
            sky: [Stop(p: 0, c: (0.09, 0.10, 0.19)), Stop(p: 0.5, c: (0.09, 0.10, 0.19)),
                  Stop(p: 1, c: (0.78, 0.35, 0.21))],
            sea: (0.11, 0.07, 0.10), bodyY: 672, bodyR: 162, body: (0.91, 0.45, 0.21), night: false),
    Variant(name: "night",
            sky: [Stop(p: 0, c: (0.05, 0.06, 0.13)), Stop(p: 0.62, c: (0.05, 0.06, 0.13)),
                  Stop(p: 1, c: (0.11, 0.12, 0.23))],
            sea: (0.06, 0.07, 0.14), bodyY: 372, bodyR: 126, body: (0.91, 0.93, 0.98), night: true),
]

func gradient(_ stops: [Stop]) -> CGGradient {
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = stops.map { rgb($0.c.0, $0.c.1, $0.c.2) } as CFArray
    let locs = stops.map { $0.p }
    return CGGradient(colorsSpace: space, colors: colors, locations: locs)!
}

func render(_ v: Variant) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    // Opaque context (noneSkipLast) — there is NO alpha channel, so corners
    // can never be transparent or a stray plate colour.
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Work top-down (match the design coordinates).
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

    // Sky — fills the entire canvas.
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: S, height: S)); ctx.clip()
    ctx.drawLinearGradient(gradient(v.sky), start: CGPoint(x: 0, y: 0),
                           end: CGPoint(x: 0, y: S), options: [])
    ctx.restoreGState()

    let cx = S / 2

    if v.night {
        // Flat crescent: pale disc carved by a sky-coloured offset disc.
        ctx.setFillColor(rgb(v.body.0, v.body.1, v.body.2))
        ctx.fillEllipse(in: CGRect(x: cx - v.bodyR, y: v.bodyY - v.bodyR, width: v.bodyR * 2, height: v.bodyR * 2))
        ctx.setFillColor(rgb(v.sky[0].c.0, v.sky[0].c.1, v.sky[0].c.2))
        let off = v.bodyR * 0.44
        let cr = v.bodyR * 0.94
        ctx.fillEllipse(in: CGRect(x: cx - cr + off, y: v.bodyY - cr - off * 0.45, width: cr * 2, height: cr * 2))
        // A few crisp stars.
        ctx.setFillColor(rgb(0.90, 0.92, 0.98, 0.9))
        for (sx, sy, sr) in [(305.0, 250.0, 6.0), (372.0, 165.0, 4.0), (700.0, 300.0, 5.0), (372.0, 690.0, 4.0)] {
            ctx.fillEllipse(in: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2))
        }
    } else {
        // Flat sun disc.
        ctx.setFillColor(rgb(v.body.0, v.body.1, v.body.2))
        ctx.fillEllipse(in: CGRect(x: cx - v.bodyR, y: v.bodyY - v.bodyR, width: v.bodyR * 2, height: v.bodyR * 2))
    }

    // Solid sea — a flat band that also occludes the lower half of a setting sun.
    ctx.setFillColor(rgb(v.sea.0, v.sea.1, v.sea.2))
    ctx.fill(CGRect(x: 0, y: HZ, width: S, height: S - HZ))

    // Crisp horizon line.
    ctx.setFillColor(rgb(1, 0.95, 0.9, v.night ? 0.14 : 0.3))
    ctx.fill(CGRect(x: 0, y: HZ - 1.5, width: S, height: 3))

    return ctx.makeImage()!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for v in variants {
    let img = render(v)
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("curfew-icon-\(v.name).png")
    try! data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(img.width)x\(img.height))")
}
