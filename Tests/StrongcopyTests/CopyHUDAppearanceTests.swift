import AppKit
import SwiftUI
import XCTest
@testable import Strongcopy

@MainActor
final class CopyHUDAppearanceTests: XCTestCase {
    private let renderScale: CGFloat = 2
    private let appearances: [ColorScheme] = [.light, .dark]

    func testBackgroundIsHalfOpaqueInBothAppearances() throws {
        for appearance in appearances {
            let bitmap = try renderBadge(appearance: appearance)

            for point in [NSPoint(x: 10, y: 26), NSPoint(x: 122, y: 26), NSPoint(x: 66, y: 6)] {
                XCTAssertEqual(
                    try color(at: point, in: bitmap).alphaComponent,
                    0.5,
                    accuracy: 0.01,
                    "\(appearance) background at \(point)"
                )
            }
        }
    }

    func testTextAndCheckmarkRemainOpaqueInBothAppearances() throws {
        for appearance in appearances {
            let bitmap = try renderBadge(appearance: appearance)
            let checkmarkRegion = NSRect(x: 16, y: 13, width: 31, height: 26)
            let textRegion = NSRect(x: 48, y: 13, width: 68, height: 26)

            XCTAssertEqual(try maximumAlpha(in: checkmarkRegion, bitmap: bitmap), 1, accuracy: 0.01)
            XCTAssertEqual(try maximumAlpha(in: textRegion, bitmap: bitmap), 1, accuracy: 0.01)
        }
    }

    func testRoundedCornersRemainTransparentInBothAppearances() throws {
        for appearance in appearances {
            let bitmap = try renderBadge(appearance: appearance)

            for point in [
                NSPoint(x: 0, y: 0),
                NSPoint(x: 131, y: 0),
                NSPoint(x: 0, y: 51),
                NSPoint(x: 131, y: 51),
            ] {
                XCTAssertEqual(try color(at: point, in: bitmap).alphaComponent, 0, accuracy: 0.01)
            }
        }
    }

    func testBackgroundColorAdaptsToAppearance() throws {
        let point = NSPoint(x: 10, y: 26)
        let light = try XCTUnwrap(
            color(at: point, in: renderBadge(appearance: .light)).usingColorSpace(.deviceRGB)
        )
        let dark = try XCTUnwrap(
            color(at: point, in: renderBadge(appearance: .dark)).usingColorSpace(.deviceRGB)
        )

        XCTAssertGreaterThan(light.redComponent, dark.redComponent)
        XCTAssertGreaterThan(light.greenComponent, dark.greenComponent)
        XCTAssertGreaterThan(light.blueComponent, dark.blueComponent)
    }

    private func renderBadge(appearance: ColorScheme) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(
            content: CopyHUDView()
                .frame(width: 132, height: 52)
                .environment(\.colorScheme, appearance)
        )
        renderer.scale = renderScale

        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func color(at point: NSPoint, in bitmap: NSBitmapImageRep) throws -> NSColor {
        try XCTUnwrap(
            bitmap.colorAt(x: Int(point.x * renderScale), y: Int(point.y * renderScale))
        )
    }

    private func maximumAlpha(in region: NSRect, bitmap: NSBitmapImageRep) throws -> CGFloat {
        var maximum: CGFloat = 0

        for y in Int(region.minY * renderScale)..<Int(region.maxY * renderScale) {
            for x in Int(region.minX * renderScale)..<Int(region.maxX * renderScale) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
                maximum = max(maximum, color.alphaComponent)
            }
        }

        return maximum
    }
}

final class WebsiteHUDAppearanceTests: XCTestCase {
    func testBothThemeBackgroundsAreHalfOpaque() throws {
        let alphas = try captures(
            matching: #"--hud-surface:\s*rgba\([^,]+,[^,]+,[^,]+,\s*([0-9.]+)\s*\)"#,
            in: stylesheet()
        )

        XCTAssertEqual(alphas.count, 2)
        for alpha in alphas {
            XCTAssertEqual(try XCTUnwrap(Double(alpha)), 0.5)
        }
    }

    func testHUDKeepsForegroundOpaqueAndDoesNotBlurBackdrop() throws {
        let rules = try captures(matching: #"(?m)^\s*\.hud\s*\{([^}]*)\}"#, in: stylesheet())

        XCTAssertFalse(rules.isEmpty)
        for rule in rules {
            let filters = try captures(
                matching: #"(?:^|;)\s*(?:-webkit-)?backdrop-filter\s*:\s*([^;]+)"#,
                in: rule
            )
            let opacities = try captures(matching: #"(?:^|;)\s*opacity\s*:\s*([^;]+)"#, in: rule)

            for filter in filters {
                XCTAssertEqual(filter.trimmingCharacters(in: .whitespacesAndNewlines), "none")
            }
            for opacity in opacities {
                XCTAssertEqual(
                    try XCTUnwrap(Double(opacity.trimmingCharacters(in: .whitespacesAndNewlines))),
                    1
                )
            }
        }
    }

    private func stylesheet() throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: packageRoot.appendingPathComponent("web/styles.css"),
            encoding: .utf8
        )
    }

    private func captures(matching pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)

        return try expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            let range = try XCTUnwrap(Range($0.range(at: 1), in: text))
            return String(text[range])
        }
    }
}
