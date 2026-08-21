import AppKit
import CryptoKit
import Foundation
import Security

enum UpdateInstallError: Error, Equatable {
    case unsignedHost
    case notWritable(String)
    case downloadFailed(Int)
    case malformedChecksum
    case checksumMismatch
    case mountFailed
    case missingBundle
    case untrustedBundle
    case versionMismatch(expected: String)
    case stagingFailed
    case replaceFailed(String)
}

extension UpdateInstallError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsignedHost:
            return "Strongcopy could not read its own signature, so the update was not trusted."
        case .notWritable(let path):
            return "Strongcopy cannot write to \(path). Move it somewhere you can write to, then try again."
        case .downloadFailed(let statusCode):
            return "Downloading the update failed with status \(statusCode)."
        case .malformedChecksum:
            return "The published checksum for the update could not be read."
        case .checksumMismatch:
            return "The downloaded update did not match its published checksum."
        case .mountFailed:
            return "The downloaded disk image could not be opened."
        case .missingBundle:
            return "The downloaded disk image does not contain Strongcopy."
        case .untrustedBundle:
            return "The downloaded copy of Strongcopy is not signed by the identity that signed this one."
        case .versionMismatch(let expected):
            return "The downloaded copy of Strongcopy is not version \(expected)."
        case .stagingFailed:
            return "The update could not be copied out of the disk image."
        case .replaceFailed(let reason):
            return "Strongcopy could not be replaced: \(reason)"
        }
    }
}

struct CodeSignatureIdentity: Equatable, Sendable {
    let bundleIdentifier: String
    let teamIdentifier: String

    /// Both values come from a signature rather than from user input, but the
    /// requirement is a parsed language, so anything that could terminate a
    /// quoted string is refused instead of escaped into one.
    init?(bundleIdentifier: String, teamIdentifier: String) {
        guard Self.isRequirementSafe(bundleIdentifier), Self.isRequirementSafe(teamIdentifier) else {
            return nil
        }

        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
    }

    var requirementText: String {
        "anchor apple generic"
            + " and identifier \"\(bundleIdentifier)\""
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    private static func isRequirementSafe(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-")
        }
    }
}

enum CodeSignatureInspector {
    static func runningIdentity() -> CodeSignatureIdentity? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        return identity(of: staticCode)
    }

    static func validate(bundleAt url: URL, matching requirementText: String) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw UpdateInstallError.untrustedBundle
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else {
            throw UpdateInstallError.untrustedBundle
        }

        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
        )
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateInstallError.untrustedBundle
        }
    }

    private static func identity(of staticCode: SecStaticCode) -> CodeSignatureIdentity? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let dictionary = information as? [String: Any],
            let bundleIdentifier = dictionary[kSecCodeInfoIdentifier as String] as? String,
            let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        else {
            return nil
        }

        return CodeSignatureIdentity(bundleIdentifier: bundleIdentifier, teamIdentifier: teamIdentifier)
    }
}

enum ChecksumFile {
    static func digest(from text: String, forFileNamed name: String) throws -> String {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else {
                continue
            }

            // `shasum` marks binary-mode entries with a leading asterisk.
            guard fields[1].drop(while: { $0 == "*" }) == name else {
                continue
            }

            let digest = fields[0]
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else {
                throw UpdateInstallError.malformedChecksum
            }

            return digest.lowercased()
        }

        throw UpdateInstallError.malformedChecksum
    }
}

enum FileDigest {
    private static let chunkSize = 1 << 20

    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum BundleVersionReader {
    static func version(atBundleURL url: URL) -> AppVersion? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String
        else {
            return nil
        }

        return AppVersion(version)
    }
}

enum ShellQuoting {
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum RelaunchCommand {
    /// LaunchServices reactivates the copy that is still running instead of
    /// starting the replacement, so the new instance may only open once this
    /// process is gone.
    static func script(processIdentifier: Int32, bundlePath: String) -> String {
        "while /bin/kill -0 \(processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done;"
            + " /usr/bin/open \(ShellQuoting.singleQuoted(bundlePath))"
    }
}

@MainActor
protocol AppRelaunching: AnyObject {
    func relaunch(bundleURL: URL)
}

@MainActor
final class ProcessRelauncher: AppRelaunching {
    func relaunch(bundleURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            RelaunchCommand.script(
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                bundlePath: bundleURL.path
            ),
        ]
        try? process.run()

        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class DiskImageUpdateInstaller: UpdateInstalling {
    private let installedBundleURL: URL
    private let session: URLSession
    private let relauncher: any AppRelaunching

    init(
        bundle: Bundle = .main,
        session: URLSession = .shared,
        relauncher: (any AppRelaunching)? = nil
    ) {
        self.installedBundleURL = bundle.bundleURL
        self.session = session
        self.relauncher = relauncher ?? ProcessRelauncher()
    }

    func install(_ update: AvailableUpdate) async throws {
        guard let identity = CodeSignatureInspector.runningIdentity() else {
            throw UpdateInstallError.unsignedHost
        }

        let installedBundleURL = self.installedBundleURL
        try await Self.replaceInstalledBundle(
            with: update,
            matching: identity,
            at: installedBundleURL,
            session: session
        )
        relauncher.relaunch(bundleURL: installedBundleURL)
    }

    private nonisolated static func replaceInstalledBundle(
        with update: AvailableUpdate,
        matching identity: CodeSignatureIdentity,
        at installedBundleURL: URL,
        session: URLSession
    ) async throws {
        let parentDirectory = installedBundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            throw UpdateInstallError.notWritable(parentDirectory.path)
        }

        // An item replacement directory is guaranteed to share a volume with the
        // installed bundle, which is what lets the final swap be a rename.
        let workspace = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: installedBundleURL,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let diskImageURL = workspace.appendingPathComponent(update.diskImageName)
        try await download(update.diskImageURL, to: diskImageURL, timeout: 300, session: session)

        let checksumURL = workspace.appendingPathComponent(update.diskImageName + ".sha256")
        try await download(update.checksumURL, to: checksumURL, timeout: 30, session: session)

        let publishedDigest = try ChecksumFile.digest(
            from: String(decoding: try Data(contentsOf: checksumURL), as: UTF8.self),
            forFileNamed: update.diskImageName
        )
        guard try FileDigest.sha256Hex(ofFileAt: diskImageURL) == publishedDigest else {
            throw UpdateInstallError.checksumMismatch
        }

        let mount = try DiskImageMount(
            imageURL: diskImageURL,
            mountPoint: workspace.appendingPathComponent("volume")
        )
        defer { mount.detach() }

        let candidateURL = mount.mountPoint.appendingPathComponent("\(ReleaseAssetNaming.appName).app")
        guard FileManager.default.fileExists(atPath: candidateURL.path) else {
            throw UpdateInstallError.missingBundle
        }

        // Copying out of a mounted image leaves no quarantine attribute, so
        // Gatekeeper will not re-examine the replacement at its next launch. The
        // checksum only proves the download arrived intact; this is the check
        // that proves it came from us.
        try CodeSignatureInspector.validate(bundleAt: candidateURL, matching: identity.requirementText)

        guard BundleVersionReader.version(atBundleURL: candidateURL) == update.version else {
            throw UpdateInstallError.versionMismatch(expected: update.version.description)
        }

        let stagedURL = workspace.appendingPathComponent(installedBundleURL.lastPathComponent)
        guard try Command.run("/usr/bin/ditto", [candidateURL.path, stagedURL.path]) == 0 else {
            throw UpdateInstallError.stagingFailed
        }

        mount.detach()

        do {
            _ = try FileManager.default.replaceItemAt(installedBundleURL, withItemAt: stagedURL)
        } catch {
            throw UpdateInstallError.replaceFailed(error.localizedDescription)
        }
    }

    private nonisolated static func download(
        _ url: URL,
        to destination: URL,
        timeout: TimeInterval,
        session: URLSession
    ) async throws {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout

        let (temporaryURL, response) = try await session.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw UpdateInstallError.downloadFailed(httpResponse.statusCode)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }
}

private final class DiskImageMount {
    let mountPoint: URL
    private var isAttached = false

    init(imageURL: URL, mountPoint: URL) throws {
        self.mountPoint = mountPoint
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let status = try Command.run("/usr/bin/hdiutil", [
            "attach", imageURL.path,
            "-nobrowse",
            "-readonly",
            "-noautoopen",
            "-mountpoint", mountPoint.path,
            "-quiet",
        ])
        guard status == 0 else {
            throw UpdateInstallError.mountFailed
        }

        isAttached = true
    }

    func detach() {
        guard isAttached else {
            return
        }
        isAttached = false

        for _ in 0..<3 {
            if (try? Command.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])) == 0 {
                return
            }
            Thread.sleep(forTimeInterval: 1)
        }

        _ = try? Command.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
    }
}

private enum Command {
    static func run(_ executablePath: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
