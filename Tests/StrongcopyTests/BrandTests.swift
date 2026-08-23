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

    private func renderedAppIcon() throws -> PixelReader {
        try XCTUnwrap(PixelReader(image: XCTUnwrap(BrandArtwork.renderAppIcon(pixelSize: extent))))
    }
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
}
