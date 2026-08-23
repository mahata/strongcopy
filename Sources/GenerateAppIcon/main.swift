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

struct GenerationFailure: Error {
    let message: String
    let exitCode: Int32

    init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw GenerationFailure("Could not create \(url.path)")
    }

    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw GenerationFailure("Could not write \(url.path)")
    }
}

func writeIconset(to directory: URL) throws {
    var renditions: [Int: CGImage] = [:]

    for member in IconSet.members {
        let rendition = renditions[member.pixelSize] ?? BrandArtwork.renderAppIcon(pixelSize: member.pixelSize)

        guard let rendition else {
            throw GenerationFailure("Could not render the \(member.pixelSize)px icon")
        }

        renditions[member.pixelSize] = rendition
        try writePNG(rendition, to: directory.appendingPathComponent(member.fileName))
    }
}

func convertToICNS(iconset: URL, output: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["--convert", "icns", "--output", output.path, iconset.path]

    do {
        try process.run()
    } catch {
        throw GenerationFailure("Could not run iconutil: \(error.localizedDescription)")
    }

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw GenerationFailure("iconutil failed with status \(process.terminationStatus)")
    }
}

func createDirectory(at url: URL) throws {
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        throw GenerationFailure("Could not create \(url.path): \(error.localizedDescription)")
    }
}

func generateIcon(at outputPath: String) throws {
    let fileManager = FileManager.default
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    try createDirectory(at: outputURL.deletingLastPathComponent())

    let workDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("strongcopy-icon-\(UUID().uuidString)")
    let iconsetURL = workDirectory.appendingPathComponent("AppIcon.iconset")
    try createDirectory(at: iconsetURL)

    // Unwinding from a render, write, or iconutil failure has to take the scratch
    // iconset with it, so the temporary directory never outlives this call.
    defer { try? fileManager.removeItem(at: workDirectory) }

    try writeIconset(to: iconsetURL)
    try? fileManager.removeItem(at: outputURL)
    try convertToICNS(iconset: iconsetURL, output: outputURL)

    print("Created \(outputURL.path)")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())

    guard arguments.count == 1 else {
        throw GenerationFailure("Usage: swift run GenerateAppIcon <output-icns-path>", exitCode: 64)
    }

    try generateIcon(at: arguments[0])
} catch let failure as GenerationFailure {
    FileHandle.standardError.write(Data("\(failure.message)\n".utf8))
    exit(failure.exitCode)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
