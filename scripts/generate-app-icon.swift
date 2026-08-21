#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasExtent: CGFloat = 1024
let squircleInset: CGFloat = 100
let squircleExponent: CGFloat = 5
let squircleSampleCount = 512

let backgroundTopColor = CGColor(srgbRed: 0.369, green: 0.631, blue: 1.0, alpha: 1)
let backgroundBottomColor = CGColor(srgbRed: 0.173, green: 0.333, blue: 0.910, alpha: 1)
let markColor = CGColor(srgbRed: 0.173, green: 0.333, blue: 0.910, alpha: 1)
let cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let trailingCardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
let glossColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28)
let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18)

struct ArtworkMetrics {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardCornerRadius: CGFloat
    let cardOffset: CGFloat
    let markStrokeWidth: CGFloat
    let drawsGloss: Bool
    let drawsShadow: Bool

    /// Small renditions need heavier artwork and a tighter stack, otherwise the
    /// checkmark dissolves into the card at 16 and 32 pixels.
    static func forPixelSize(_ pixelSize: Int) -> ArtworkMetrics {
        switch pixelSize {
        case ..<32:
            return ArtworkMetrics(
                cardWidth: 462,
                cardHeight: 556,
                cardCornerRadius: 88,
                cardOffset: 78,
                markStrokeWidth: 124,
                drawsGloss: false,
                drawsShadow: false
            )
        case ..<64:
            return ArtworkMetrics(
                cardWidth: 372,
                cardHeight: 452,
                cardCornerRadius: 62,
                cardOffset: 96,
                markStrokeWidth: 92,
                drawsGloss: false,
                drawsShadow: true
            )
        case ..<128:
            return ArtworkMetrics(
                cardWidth: 360,
                cardHeight: 444,
                cardCornerRadius: 60,
                cardOffset: 116,
                markStrokeWidth: 74,
                drawsGloss: true,
                drawsShadow: true
            )
        default:
            return ArtworkMetrics(
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
}

let iconsetMembers: [(fileName: String, pixelSize: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

func squirclePath() -> CGPath {
    let center = canvasExtent / 2
    let halfExtent = (canvasExtent - squircleInset * 2) / 2
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

func drawBackground(in context: CGContext, metrics: ArtworkMetrics) {
    let shape = squirclePath()
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    if metrics.drawsShadow {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 12), blur: 18, color: shadowColor)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(shape)
        context.setFillColor(backgroundTopColor)
        context.fillPath()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [backgroundTopColor, backgroundBottomColor] as CFArray,
        locations: [0, 1]
    ) else {
        fail("Could not build the background gradient")
    }

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvasExtent / 2, y: squircleInset),
        end: CGPoint(x: canvasExtent / 2, y: canvasExtent - squircleInset),
        options: []
    )
    context.restoreGState()
}

func drawGloss(in context: CGContext) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [glossColor, glossColor.copy(alpha: 0)!] as CFArray,
        locations: [0, 1]
    ) else {
        fail("Could not build the gloss gradient")
    }

    context.saveGState()
    context.addPath(squirclePath())
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvasExtent / 2, y: squircleInset),
        end: CGPoint(x: canvasExtent / 2, y: canvasExtent * 0.54),
        options: []
    )
    context.restoreGState()
}

func drawCopyStack(in context: CGContext, metrics: ArtworkMetrics) {
    let stackWidth = metrics.cardWidth + metrics.cardOffset
    let stackHeight = metrics.cardHeight + metrics.cardOffset
    let originX = (canvasExtent - stackWidth) / 2
    let originY = (canvasExtent - stackHeight) / 2

    let trailingCard = CGRect(
        x: originX,
        y: originY,
        width: metrics.cardWidth,
        height: metrics.cardHeight
    )
    let leadingCard = trailingCard.offsetBy(dx: metrics.cardOffset, dy: metrics.cardOffset)

    for (rect, color) in [(trailingCard, trailingCardColor), (leadingCard, cardColor)] {
        context.addPath(
            CGPath(
                roundedRect: rect,
                cornerWidth: metrics.cardCornerRadius,
                cornerHeight: metrics.cardCornerRadius,
                transform: nil
            )
        )
        context.setFillColor(color)
        context.fillPath()
    }

    let markWidth = leadingCard.width * 0.53
    let markCenter = CGPoint(x: leadingCard.midX, y: leadingCard.midY)
    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: markCenter.x - markWidth * 0.5, y: markCenter.y + markWidth * 0.03))
    mark.addLine(to: CGPoint(x: markCenter.x - markWidth * 0.13, y: markCenter.y + markWidth * 0.41))
    mark.addLine(to: CGPoint(x: markCenter.x + markWidth * 0.5, y: markCenter.y - markWidth * 0.37))

    context.addPath(mark)
    context.setStrokeColor(markColor)
    context.setLineWidth(metrics.markStrokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

func renderIcon(pixelSize: Int) -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("Could not create a \(pixelSize)px drawing context")
    }

    let scale = CGFloat(pixelSize) / canvasExtent
    context.translateBy(x: 0, y: CGFloat(pixelSize))
    context.scaleBy(x: scale, y: -scale)
    context.setShouldAntialias(true)

    let metrics = ArtworkMetrics.forPixelSize(pixelSize)
    drawBackground(in: context, metrics: metrics)
    if metrics.drawsGloss {
        drawGloss(in: context)
    }
    drawCopyStack(in: context, metrics: metrics)

    guard let image = context.makeImage() else {
        fail("Could not render the \(pixelSize)px icon")
    }

    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fail("Could not create \(url.path)")
    }

    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else {
        fail("Could not write \(url.path)")
    }
}

func convertToICNS(iconset: URL, output: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["--convert", "icns", "--output", output.path, iconset.path]

    do {
        try process.run()
    } catch {
        fail("Could not run iconutil: \(error.localizedDescription)")
    }

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        fail("iconutil failed with status \(process.terminationStatus)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard arguments.count == 1 else {
    fail("Usage: swift scripts/generate-app-icon.swift <output-icns-path>", code: 64)
}

let outputURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
let fileManager = FileManager.default

do {
    try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
} catch {
    fail("Could not create \(outputURL.deletingLastPathComponent().path): \(error.localizedDescription)")
}

let workDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("strongcopy-icon-\(UUID().uuidString)")
let iconsetURL = workDirectory.appendingPathComponent("AppIcon.iconset")

do {
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
} catch {
    fail("Could not create \(iconsetURL.path): \(error.localizedDescription)")
}

defer { try? fileManager.removeItem(at: workDirectory) }

var renditions: [Int: CGImage] = [:]
for member in iconsetMembers {
    let image = renditions[member.pixelSize] ?? renderIcon(pixelSize: member.pixelSize)
    renditions[member.pixelSize] = image
    writePNG(image, to: iconsetURL.appendingPathComponent(member.fileName))
}

try? fileManager.removeItem(at: outputURL)
convertToICNS(iconset: iconsetURL, output: outputURL)
print("Created \(outputURL.path)")
