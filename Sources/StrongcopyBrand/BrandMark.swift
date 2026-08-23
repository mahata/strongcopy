import CoreGraphics

public struct BrandMarkMetrics: Sendable {
    public let cardWidth: CGFloat
    public let cardHeight: CGFloat
    public let cardCornerRadius: CGFloat
    public let cardOffset: CGFloat
    public let markStrokeWidth: CGFloat
    public let drawsGloss: Bool
    public let drawsShadow: Bool

    /// Small renditions need heavier artwork and a tighter stack, otherwise the
    /// checkmark dissolves into the card at 16 and 32 pixels.
    public static func forPixelSize(_ pixelSize: Int) -> BrandMarkMetrics {
        switch pixelSize {
        case ..<32:
            return BrandMarkMetrics(
                cardWidth: 462,
                cardHeight: 556,
                cardCornerRadius: 88,
                cardOffset: 78,
                markStrokeWidth: 124,
                drawsGloss: false,
                drawsShadow: false
            )
        case ..<64:
            return BrandMarkMetrics(
                cardWidth: 372,
                cardHeight: 452,
                cardCornerRadius: 62,
                cardOffset: 96,
                markStrokeWidth: 92,
                drawsGloss: false,
                drawsShadow: true
            )
        case ..<128:
            return BrandMarkMetrics(
                cardWidth: 360,
                cardHeight: 444,
                cardCornerRadius: 60,
                cardOffset: 116,
                markStrokeWidth: 74,
                drawsGloss: true,
                drawsShadow: true
            )
        default:
            return BrandMarkMetrics(
                cardWidth: 366,
                cardHeight: 452,
                cardCornerRadius: 60,
                cardOffset: 132,
                markStrokeWidth: 60,
                drawsGloss: true,
                drawsShadow: true
            )
        }
    }

    /// The tiers are keyed on the whole canvas, so a renderer showing the mark alone
    /// converts its extent back to the canvas that mark would have been cropped from.
    public static func forMarkExtent(_ markExtent: CGFloat) -> BrandMarkMetrics {
        let reference = BrandMarkGeometry(metrics: forPixelSize(Int(BrandCanvas.extent)))
        let canvasExtent = markExtent * BrandCanvas.extent / reference.bounds.height

        return forPixelSize(Int(canvasExtent.rounded()))
    }
}

/// Two offset cards carrying a checkmark: copying, with confirmation.
public struct BrandMarkGeometry {
    public let trailingCard: CGRect
    public let leadingCard: CGRect
    public let checkmark: CGPath
    public let strokeWidth: CGFloat
    public let cornerRadius: CGFloat

    public var bounds: CGRect {
        trailingCard.union(leadingCard)
    }

    public init(metrics: BrandMarkMetrics, canvasExtent: CGFloat = BrandCanvas.extent) {
        let stackWidth = metrics.cardWidth + metrics.cardOffset
        let stackHeight = metrics.cardHeight + metrics.cardOffset
        let trailingCard = CGRect(
            x: (canvasExtent - stackWidth) / 2,
            y: (canvasExtent - stackHeight) / 2,
            width: metrics.cardWidth,
            height: metrics.cardHeight
        )
        let leadingCard = trailingCard.offsetBy(dx: metrics.cardOffset, dy: metrics.cardOffset)

        self.trailingCard = trailingCard
        self.leadingCard = leadingCard
        self.strokeWidth = metrics.markStrokeWidth
        self.cornerRadius = metrics.cardCornerRadius
        self.checkmark = Self.checkmarkPath(on: leadingCard)
    }

    public func cardPath(_ card: CGRect) -> CGPath {
        CGPath(
            roundedRect: card,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    private static func checkmarkPath(on card: CGRect) -> CGPath {
        let width = card.width * 0.53
        let center = CGPoint(x: card.midX, y: card.midY)
        let path = CGMutablePath()

        path.move(to: CGPoint(x: center.x - width * 0.5, y: center.y + width * 0.03))
        path.addLine(to: CGPoint(x: center.x - width * 0.13, y: center.y + width * 0.41))
        path.addLine(to: CGPoint(x: center.x + width * 0.5, y: center.y - width * 0.37))

        return path
    }
}
