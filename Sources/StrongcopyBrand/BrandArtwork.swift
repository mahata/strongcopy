import CoreGraphics
import Foundation

public enum BrandArtwork {
    /// The full app icon: the mark in colour on the macOS squircle.
    public static func renderAppIcon(pixelSize: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let metrics = BrandMarkMetrics.forPixelSize(pixelSize)

        guard let background = gradient(from: BrandPalette.backgroundTop, to: BrandPalette.backgroundBottom),
              let gloss = fadingGradient(from: BrandPalette.gloss) else {
            return nil
        }

        context.setShouldAntialias(true)
        BrandCanvas.flipToArtworkSpace(context, pixelSize: pixelSize)

        drawBackground(in: context, gradient: background, castsShadow: metrics.drawsShadow)
        if metrics.drawsGloss {
            drawGloss(in: context, gradient: gloss)
        }
        drawColorMark(in: context, geometry: BrandMarkGeometry(metrics: metrics))

        return context.makeImage()
    }

    /// The mark alone, as a menu bar template: alpha carries the shape, so the
    /// checkmark is cut out of the front card rather than drawn on top of it.
    public static func drawStatusMark(in context: CGContext, extent: CGSize) {
        let geometry = BrandMarkGeometry(metrics: .forMarkExtent(min(extent.width, extent.height)))

        context.saveGState()
        context.setShouldAntialias(true)
        BrandCanvas.flipToArtworkSpace(context, fitting: geometry.bounds, into: extent)
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        context.addPath(geometry.cardPath(geometry.trailingCard))
        context.setFillColor(gray: 0, alpha: BrandPalette.trailingCardOpacity)
        context.fillPath()

        context.addPath(geometry.cardPath(geometry.leadingCard))
        context.setFillColor(gray: 0, alpha: 1)
        context.fillPath()

        context.setBlendMode(.clear)
        strokeCheckmark(in: context, geometry: geometry)
        context.setBlendMode(.normal)

        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func drawBackground(in context: CGContext, gradient: CGGradient, castsShadow: Bool) {
        let shape = BrandCanvas.squirclePath()

        if castsShadow {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 12), blur: 18, color: BrandPalette.shadow)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.addPath(shape)
            context.setFillColor(BrandPalette.backgroundTop)
            context.fillPath()
            context.endTransparencyLayer()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: BrandCanvas.extent / 2, y: BrandCanvas.squircleBounds.minY),
            end: CGPoint(x: BrandCanvas.extent / 2, y: BrandCanvas.squircleBounds.maxY),
            options: []
        )
        context.restoreGState()
    }

    private static func drawGloss(in context: CGContext, gradient: CGGradient) {
        context.saveGState()
        context.addPath(BrandCanvas.squirclePath())
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: BrandCanvas.extent / 2, y: BrandCanvas.squircleBounds.minY),
            end: CGPoint(x: BrandCanvas.extent / 2, y: BrandCanvas.extent * 0.54),
            options: []
        )
        context.restoreGState()
    }

    private static func drawColorMark(in context: CGContext, geometry: BrandMarkGeometry) {
        let cards = [
            (geometry.trailingCard, BrandPalette.trailingCard),
            (geometry.leadingCard, BrandPalette.card),
        ]

        for (card, color) in cards {
            context.addPath(geometry.cardPath(card))
            context.setFillColor(color)
            context.fillPath()
        }

        context.setStrokeColor(BrandPalette.mark)
        strokeCheckmark(in: context, geometry: geometry)
    }

    private static func strokeCheckmark(in context: CGContext, geometry: BrandMarkGeometry) {
        context.addPath(geometry.checkmark)
        context.setLineWidth(geometry.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    private static func gradient(from start: CGColor, to end: CGColor) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [start, end] as CFArray,
            locations: [0, 1]
        )
    }

    private static func fadingGradient(from start: CGColor) -> CGGradient? {
        guard let transparent = start.copy(alpha: 0) else {
            return nil
        }

        return gradient(from: start, to: transparent)
    }
}
