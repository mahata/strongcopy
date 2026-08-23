import CoreGraphics
import Foundation
import ImageIO
import StrongcopyBrand
import UniformTypeIdentifiers

enum IconSet {
    static let members: [(fileName: String, pixelSize: Int)] = [
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
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
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

func writeIconset(to directory: URL) {
    var renditions: [Int: CGImage] = [:]

    for member in IconSet.members {
        guard let image = renditions[member.pixelSize] ?? BrandArtwork.renderAppIcon(pixelSize: member.pixelSize) else {
            fail("Could not render the \(member.pixelSize)px icon")
        }

        renditions[member.pixelSize] = image
        writePNG(image, to: directory.appendingPathComponent(member.fileName))
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
    fail("Usage: swift run GenerateAppIcon <output-icns-path>", code: 64)
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

writeIconset(to: iconsetURL)

try? fileManager.removeItem(at: outputURL)
convertToICNS(iconset: iconsetURL, output: outputURL)
try? fileManager.removeItem(at: workDirectory)

print("Created \(outputURL.path)")
