import CoreGraphics
import Foundation

/// The square the app icon is authored on. Artwork is laid out with a top-left
/// origin, so both renderers flip into this space before drawing.
public enum BrandCanvas {
    public static let extent: CGFloat = 1024

    private static let squircleInset: CGFloat = 100
    private static let squircleExponent: CGFloat = 5
    private static let squircleSampleCount = 512

    public static var squircleBounds: CGRect {
        CGRect(x: 0, y: 0, width: extent, height: extent).insetBy(dx: squircleInset, dy: squircleInset)
    }

    public static func squirclePath() -> CGPath {
        let center = extent / 2
        let halfExtent = squircleBounds.width / 2
        let path = CGMutablePath()

        for sample in 0..<squircleSampleCount {
            let angle = 2 * CGFloat.pi * CGFloat(sample) / CGFloat(squircleSampleCount)
            let horizontal = cos(angle)
            let vertical = sin(angle)
            let point = CGPoint(
                x: center + halfExtent * copysign(pow(abs(horizontal), 2 / squircleExponent), horizontal),
                y: center + halfExtent * copysign(pow(abs(vertical), 2 / squircleExponent), vertical)
            )

            if sample == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }

    /// Maps the whole canvas onto a square context of `pixelSize`, flipping so that
    /// artwork coordinates run downward.
    public static func flipToArtworkSpace(_ context: CGContext, pixelSize: Int) {
        let scale = CGFloat(pixelSize) / extent
        context.translateBy(x: 0, y: CGFloat(pixelSize))
        context.scaleBy(x: scale, y: -scale)
    }

    /// Fits `bounds` into `extent`, centred, flipping into artwork coordinates. Used
    /// when only part of the canvas is shown, as the menu bar mark does.
    public static func flipToArtworkSpace(_ context: CGContext, fitting bounds: CGRect, into extent: CGSize) {
        let scale = min(extent.width / bounds.width, extent.height / bounds.height)
        context.translateBy(x: extent.width / 2, y: extent.height / 2)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
    }
}

public enum BrandPalette {
    public static var backgroundTop: CGColor { CGColor(srgbRed: 0.369, green: 0.631, blue: 1.0, alpha: 1) }
    public static var backgroundBottom: CGColor { CGColor(srgbRed: 0.173, green: 0.333, blue: 0.910, alpha: 1) }
    public static var mark: CGColor { CGColor(srgbRed: 0.173, green: 0.333, blue: 0.910, alpha: 1) }
    public static var card: CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }
    public static var gloss: CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28) }
    public static var shadow: CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18) }

    /// How far the card behind the stack recedes. The colour renderings apply it as
    /// translucent white; the template mark applies it to alpha alone.
    public static let trailingCardOpacity: CGFloat = 0.55

    public static var trailingCard: CGColor {
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: trailingCardOpacity)
    }
}
