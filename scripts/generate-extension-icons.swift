#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repositoryRoot.appendingPathComponent("web/extension/icons")
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("curfew-extension-icons-\(UUID().uuidString)")
let compiledDirectory = temporaryDirectory.appendingPathComponent("compiled")
let iconsetDirectory = temporaryDirectory.appendingPathComponent("AppIcon.iconset")

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: outputData, encoding: .utf8) ?? "Icon compiler failed"
        throw NSError(
            domain: "GenerateExtensionIcons",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

try fileManager.createDirectory(at: compiledDirectory, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryDirectory) }

try run("/usr/bin/xcrun", [
    "actool",
    repositoryRoot.appendingPathComponent("Curfew/AppIcon.icon").path,
    "--compile", compiledDirectory.path,
    "--app-icon", "AppIcon",
    "--platform", "macosx",
    "--minimum-deployment-target", "26.0",
    "--output-partial-info-plist", compiledDirectory.appendingPathComponent("partial.plist").path
])
try run("/usr/bin/iconutil", [
    "--convert", "iconset",
    "--output", iconsetDirectory.path,
    compiledDirectory.appendingPathComponent("AppIcon.icns").path
])

let sourceURL = iconsetDirectory.appendingPathComponent("icon_128x128@2x.png")
guard let sourceData = try? Data(contentsOf: sourceURL),
      let sourceBitmap = NSBitmapImageRep(data: sourceData)
else {
    throw NSError(
        domain: "GenerateExtensionIcons",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not load the compiled Curfew app icon"]
    )
}

let sourceImage = NSImage(
    size: NSSize(width: sourceBitmap.pixelsWide, height: sourceBitmap.pixelsHigh)
)
sourceImage.addRepresentation(sourceBitmap)

var minimumX = sourceBitmap.pixelsWide
var minimumY = sourceBitmap.pixelsHigh
var maximumX = -1
var maximumY = -1
for pixelY in 0 ..< sourceBitmap.pixelsHigh {
    for pixelX in 0 ..< sourceBitmap.pixelsWide
        where sourceBitmap.colorAt(x: pixelX, y: pixelY)?.alphaComponent ?? 0 > 0 {
        minimumX = min(minimumX, pixelX)
        minimumY = min(minimumY, pixelY)
        maximumX = max(maximumX, pixelX)
        maximumY = max(maximumY, pixelY)
    }
}

guard maximumX >= minimumX, maximumY >= minimumY else {
    throw NSError(
        domain: "GenerateExtensionIcons",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "The compiled Curfew app icon has no visible pixels"]
    )
}

let sourceArtwork = NSRect(
    x: minimumX,
    y: minimumY,
    width: maximumX - minimumX + 1,
    height: maximumY - minimumY + 1
)

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for size in [16, 32, 48, 128] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(
            domain: "GenerateExtensionIcons",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not create the \(size)-pixel icon canvas"]
        )
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)

    // Chrome reserves a 96-pixel artwork area inside the 128-pixel store icon.
    // The extra sampling pixel keeps the antialiased edge intact while the clip
    // holds every visible pixel inside Chrome's required 16-pixel margin.
    let isStoreIcon = size == 128
    let artworkSize = isStoreIcon ? CGFloat(98) : CGFloat(size) * 15 / 16
    let artworkOrigin = (CGFloat(size) - artworkSize) / 2
    if isStoreIcon {
        NSBezierPath(rect: NSRect(x: 16, y: 16, width: 96, height: 96)).addClip()
    }
    sourceImage.draw(
        in: NSRect(
            x: artworkOrigin,
            y: artworkOrigin,
            width: artworkSize,
            height: artworkSize
        ),
        from: isStoreIcon ? sourceArtwork : .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "GenerateExtensionIcons",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode the \(size)-pixel icon"]
        )
    }
    try png.write(to: outputDirectory.appendingPathComponent("icon-\(size).png"))
}
