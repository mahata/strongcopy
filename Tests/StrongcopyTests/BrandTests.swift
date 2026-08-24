import XCTest
import CoreGraphics
@testable import StrongcopyBrand

final class BrandMarkMetricsTests: XCTestCase {
    func testSmallRenditionsUseHeavierStrokeThanLargeOnes() {
        XCTAssertGreaterThan(
            BrandMarkMetrics.forPixelSize(16).markStrokeWidth,
            BrandMarkMetrics.forPixelSize(1024).markStrokeWidth
        )
    }

    func testStrokeWeightDecreasesAcrossEveryTier() {
        let strokeWidths = [16, 32, 64, 128].map { BrandMarkMetrics.forPixelSize($0).markStrokeWidth }

        XCTAssertEqual(strokeWidths, strokeWidths.sorted(by: >))
    }

    func testSmallestTierDropsGlossAndShadow() {
        let smallest = BrandMarkMetrics.forPixelSize(16)

        XCTAssertFalse(smallest.drawsGloss)
        XCTAssertFalse(smallest.drawsShadow)
    }

    func testGlossAppearsOnlyOnceTheCanvasIsLargeEnough() {
        XCTAssertFalse(BrandMarkMetrics.forPixelSize(32).drawsGloss)
        XCTAssertTrue(BrandMarkMetrics.forPixelSize(64).drawsGloss)
    }

    func testMarkExtentNeverLightensAsTheMarkShrinks() {
        let strokeWidths = [16, 36, 72, 144, 1024].map {
            BrandMarkMetrics.forMarkExtent(CGFloat($0)).markStrokeWidth
        }

        XCTAssertTrue(zip(strokeWidths, strokeWidths.dropFirst()).allSatisfy { $0 >= $1 })
        XCTAssertGreaterThan(strokeWidths.first ?? 0, strokeWidths.last ?? 0)
    }

    func testMarkExtentLooksUpTheTierAgainstTheCanvasItWasCroppedFrom() {
        // The mark covers only part of the canvas, so an extent matching the canvas
        // came from an even larger rendition and lands in the lightest tier.
        XCTAssertEqual(
            BrandMarkMetrics.forMarkExtent(BrandCanvas.extent).markStrokeWidth,
            BrandMarkMetrics.forPixelSize(1024).markStrokeWidth
        )
    }
}

final class BrandMarkGeometryTests: XCTestCase {
    private let metrics = BrandMarkMetrics.forPixelSize(1024)
    private let geometry = BrandMarkGeometry(metrics: .forPixelSize(1024))

    func testStackIsCenteredOnTheCanvas() {
        XCTAssertEqual(geometry.bounds.midX, BrandCanvas.extent / 2, accuracy: 0.001)
        XCTAssertEqual(geometry.bounds.midY, BrandCanvas.extent / 2, accuracy: 0.001)
    }

    func testCardsShareTheSizeFromTheMetrics() {
        XCTAssertEqual(geometry.leadingCard.size, geometry.trailingCard.size)
        XCTAssertEqual(geometry.leadingCard.width, metrics.cardWidth, accuracy: 0.001)
        XCTAssertEqual(geometry.leadingCard.height, metrics.cardHeight, accuracy: 0.001)
    }

    func testLeadingCardIsOffsetTowardTheBottomRight() {
        // Artwork space runs top-left origin, so a positive offset moves down.
        XCTAssertEqual(
            geometry.leadingCard.minX - geometry.trailingCard.minX,
            metrics.cardOffset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            geometry.leadingCard.minY - geometry.trailingCard.minY,
            metrics.cardOffset,
            accuracy: 0.001
        )
    }

    func testBoundsCoverBothCards() {
        XCTAssertTrue(geometry.bounds.contains(geometry.leadingCard))
        XCTAssertTrue(geometry.bounds.contains(geometry.trailingCard))
    }

    func testStrokedCheckmarkStaysWithinTheLeadingCard() {
        let stroked = geometry.checkmark.boundingBox.insetBy(
            dx: -geometry.strokeWidth / 2,
            dy: -geometry.strokeWidth / 2
        )

        XCTAssertTrue(geometry.leadingCard.contains(stroked))
    }

    func testCheckmarkRunsUphillFromItsVertex() {
        let corners = geometry.checkmark.points

        XCTAssertEqual(corners.count, 3)
        // The vertex is the lowest point, and the tip climbs highest.
        XCTAssertGreaterThan(corners[1].y, corners[0].y)
        XCTAssertLessThan(corners[2].y, corners[0].y)
        XCTAssertTrue(corners[0].x < corners[1].x && corners[1].x < corners[2].x)
    }
}

final class BrandArtworkTests: XCTestCase {
    private let extent = 128

    func testAppIconRendersAtTheRequestedPixelSize() throws {
        let image = try XCTUnwrap(BrandArtwork.renderAppIcon(pixelSize: extent))

        XCTAssertEqual(image.width, extent)
        XCTAssertEqual(image.height, extent)
    }

    func testAppIconLeavesTheCornersOutsideTheSquircleTransparent() throws {
        let pixels = try renderedAppIcon()

        XCTAssertEqual(pixels.alpha(atX: 1, y: 1), 0, accuracy: 0.02)
        XCTAssertEqual(pixels.alpha(atX: 64, y: 64), 1, accuracy: 0.02)
    }

    func testStatusMarkFillsTheLeadingCard() throws {
        let pixels = try renderedStatusMark()
        let card = statusMarkGeometry.leadingCard
        let belowTheCheckmark = CGPoint(x: card.midX, y: card.maxY - card.height * 0.1)

        XCTAssertEqual(pixels.alpha(at: project(belowTheCheckmark)), 1, accuracy: 0.02)
    }

    func testStatusMarkKnocksTheCheckmarkOutOfTheCard() throws {
        let pixels = try renderedStatusMark()
        let vertex = statusMarkGeometry.checkmark.points[1]

        XCTAssertEqual(pixels.alpha(at: project(vertex)), 0, accuracy: 0.02)
    }

    func testStatusMarkDimsTheTrailingCard() throws {
        let pixels = try renderedStatusMark()
        let card = statusMarkGeometry.trailingCard
        let aboveTheLeadingCard = CGPoint(x: card.midX, y: card.minY + card.height * 0.1)
        let dimmed = pixels.alpha(at: project(aboveTheLeadingCard))

        XCTAssertGreaterThan(dimmed, 0.1)
        XCTAssertLessThan(dimmed, 0.9)
    }

    func testStatusMarkDropsTheSquircleBackground() throws {
        let pixels = try renderedStatusMark()

        XCTAssertEqual(pixels.alpha(atX: 1, y: extent - 2), 0, accuracy: 0.02)
    }

    private var statusMarkGeometry: BrandMarkGeometry {
        BrandMarkGeometry(metrics: .forMarkExtent(CGFloat(extent)))
    }

    private func renderedAppIcon() throws -> PixelReader {
        try XCTUnwrap(PixelReader(image: XCTUnwrap(BrandArtwork.renderAppIcon(pixelSize: extent))))
    }

    private func renderedStatusMark() throws -> PixelReader {
        let context = try XCTUnwrap(makeContext(pixelSize: extent))
        BrandArtwork.drawStatusMark(in: context, extent: CGSize(width: extent, height: extent))

        return try XCTUnwrap(PixelReader(image: XCTUnwrap(context.makeImage())))
    }

    /// Maps a point in artwork space onto the pixel the status mark renders it at.
    private func project(_ point: CGPoint) -> CGPoint {
        let bounds = statusMarkGeometry.bounds
        let side = CGFloat(extent)
        let scale = min(side / bounds.width, side / bounds.height)

        return CGPoint(
            x: side / 2 + (point.x - bounds.midX) * scale,
            y: side / 2 + (point.y - bounds.midY) * scale
        )
    }
}

private func makeContext(pixelSize: Int) -> CGContext? {
    CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

private extension CGPath {
    /// The corner points of an open polyline, in the order they were added.
    var points: [CGPoint] {
        var corners: [CGPoint] = []
        applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                corners.append(element.pointee.points[0])
            default:
                break
            }
        }
        return corners
    }
}

/// Reads alpha out of a rendered bitmap using the top-left origin the artwork is
/// authored in, which is also the order CoreGraphics lays the rows out in memory.
private struct PixelReader {
    private let backing: CFData
    private let bytes: UnsafePointer<UInt8>
    private let bytesPerRow: Int
    private let bytesPerPixel: Int

    init?(image: CGImage) {
        guard let backing = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(backing) else {
            return nil
        }

        self.backing = backing
        self.bytes = bytes
        self.bytesPerRow = image.bytesPerRow
        self.bytesPerPixel = image.bitsPerPixel / 8
    }

    func alpha(atX x: Int, y: Int) -> CGFloat {
        CGFloat(bytes[y * bytesPerRow + x * bytesPerPixel + bytesPerPixel - 1]) / 255
    }

    func alpha(at point: CGPoint) -> CGFloat {
        alpha(atX: Int(point.x.rounded()), y: Int(point.y.rounded()))
    }
}
