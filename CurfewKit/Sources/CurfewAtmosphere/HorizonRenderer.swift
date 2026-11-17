import CoreGraphics
import Foundation

/// The CPU reference renderer. It evaluates ``HorizonField`` at every pixel
/// centre, exactly as the fragment shader does, and is used where the shader
/// cannot run: unit tests, the headless snapshot harness, still frames, the
/// widget and exported images.
public enum HorizonRenderer {
    /// RGBA8 pixels, row 0 at the top, alpha always 255.
    public static func pixels(
        frame: HorizonFrame, bandPhase: Double, pixelWidth: Int, pixelHeight: Int,
        palette: HorizonPalette = .standard
    ) -> [UInt8]? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let width = Double(pixelWidth)
        let height = Double(pixelHeight)
        let aspect = width / height
        let canvas = HorizonField.Canvas(aspect: aspect, pixelHeight: height)

        // Brightness on a grid one larger than the image, so the screen-space
        // derivative (the shader's `fwidth`) is a forward difference.
        let gridWidth = pixelWidth + 1
        var levels = [Double](repeating: 0, count: gridWidth * (pixelHeight + 1))
        for row in 0 ... pixelHeight {
            let rowY = (Double(row) + 0.5) / height
            for column in 0 ... pixelWidth {
                let point = HorizonPoint(x: (Double(column) + 0.5) / width, y: rowY)
                levels[row * gridWidth + column] = HorizonField.brightness(
                    at: point, aspect: aspect, frame: frame
                )
            }
        }

        var bytes = [UInt8](repeating: 255, count: pixelWidth * pixelHeight * 4)
        for row in 0 ..< pixelHeight {
            // `row` counts up from the bottom, as `gl_FragCoord` does.
            let rowY = (Double(row) + 0.5) / height
            let outputRow = pixelHeight - 1 - row
            for column in 0 ..< pixelWidth {
                let index = row * gridWidth + column
                let level = levels[index]
                let change = abs(levels[index + 1] - level) + abs(levels[index + gridWidth] - level)
                let color = palette.fieldColor(
                    at: HorizonPoint(x: (Double(column) + 0.5) / width, y: rowY),
                    level: level, canvas: canvas, frame: frame,
                    bands: HorizonField.Bands(
                        phase: bandPhase,
                        edgeWidth: HorizonField.edgeWidth(levelChangePerPixel: change)
                    )
                )
                let channels = color.bytes
                let offset = (outputRow * pixelWidth + column) * 4
                bytes[offset] = channels[0]
                bytes[offset + 1] = channels[1]
                bytes[offset + 2] = channels[2]
            }
        }
        return bytes
    }

    /// An sRGB image of the scene at the requested pixel size, in `palette`.
    public static func image(
        frame: HorizonFrame, bandPhase: Double, pixelWidth: Int, pixelHeight: Int,
        palette: HorizonPalette = .standard
    ) -> CGImage? {
        guard let bytes = pixels(
                  frame: frame, bandPhase: bandPhase, pixelWidth: pixelWidth,
                  pixelHeight: pixelHeight, palette: palette
              ), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixelWidth * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
