import Foundation

struct AppVersion: Equatable, Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts both the `vMAJOR.MINOR.PATCH` release tags published by CI and the
    /// bare `MAJOR.MINOR.PATCH` string stored in `CFBundleShortVersionString`.
    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") {
            trimmed.removeFirst()
        }

        let components = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            return nil
        }

        var numbers: [Int] = []
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy(\.isASCIIDigit),
                  let number = Int(component)
            else {
                return nil
            }
            numbers.append(number)
        }

        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

/// The release workflow publishes assets under these names. Installed copies
/// resolve updates by name, so renaming them breaks clients already in the wild.
enum ReleaseAssetNaming {
    static let appName = "Strongcopy"

    static func diskImageName(for version: AppVersion) -> String {
        "\(appName)-\(version).dmg"
    }

    static func checksumName(for version: AppVersion) -> String {
        "\(diskImageName(for: version)).sha256"
    }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: AppVersion
    let diskImageURL: URL
    let checksumURL: URL
    let releaseNotes: String

    var diskImageName: String {
        ReleaseAssetNaming.diskImageName(for: version)
    }
}

enum UpdateFeedError: Error, Equatable {
    case malformedPayload
    case unpublishedRelease
    case unreadableVersion(String)
    case missingAsset(String)
    case insecureAssetURL(String)
    case requestFailed(Int)
    case rateLimited
}

extension UpdateFeedError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformedPayload:
            return "The release information from GitHub could not be read."
        case .unpublishedRelease:
            return "The latest release is not published yet."
        case .unreadableVersion(let tag):
            return "The release tag \(tag) is not a version Strongcopy understands."
        case .missingAsset(let name):
            return "The latest release does not contain \(name)."
        case .insecureAssetURL(let name):
            return "The download link for \(name) is not secure."
        case .requestFailed(let statusCode):
            return "GitHub responded with status \(statusCode)."
        case .rateLimited:
            return "GitHub is rate limiting update checks. Try again later."
        }
    }
}

enum ReleaseFeedDecoder {
    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let draft: Bool?
        let prerelease: Bool?
        let body: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
            case body
            case assets
        }
    }

    static func availableUpdate(from data: Data) throws -> AvailableUpdate {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UpdateFeedError.malformedPayload
        }

        guard payload.draft != true, payload.prerelease != true else {
            throw UpdateFeedError.unpublishedRelease
        }

        guard let version = AppVersion(payload.tagName) else {
            throw UpdateFeedError.unreadableVersion(payload.tagName)
        }

        return AvailableUpdate(
            version: version,
            diskImageURL: try assetURL(
                named: ReleaseAssetNaming.diskImageName(for: version),
                in: payload.assets
            ),
            checksumURL: try assetURL(
                named: ReleaseAssetNaming.checksumName(for: version),
                in: payload.assets
            ),
            releaseNotes: payload.body ?? ""
        )
    }

    private static func assetURL(named name: String, in assets: [Payload.Asset]) throws -> URL {
        guard let asset = assets.first(where: { $0.name == name }) else {
            throw UpdateFeedError.missingAsset(name)
        }

        guard let url = URL(string: asset.browserDownloadURL),
              url.scheme?.lowercased() == "https"
        else {
            throw UpdateFeedError.insecureAssetURL(name)
        }

        return url
    }
}

protocol UpdateFeed: Sendable {
    func latestRelease() async throws -> AvailableUpdate
}

struct GitHubUpdateFeed: UpdateFeed {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/mahata/strongcopy/releases/latest"
    )!

    private let url: URL
    private let session: URLSession

    init(url: URL = GitHubUpdateFeed.latestReleaseURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    static func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        return request
    }

    static func failure(forStatusCode statusCode: Int) -> UpdateFeedError? {
        switch statusCode {
        case 200..<300:
            return nil
        // GitHub reports an exhausted unauthenticated quota as 403 rather than 429.
        case 403, 429:
            return .rateLimited
        default:
            return .requestFailed(statusCode)
        }
    }

    func latestRelease() async throws -> AvailableUpdate {
        let (data, response) = try await session.data(for: Self.makeRequest(url: url))

        if let httpResponse = response as? HTTPURLResponse,
           let failure = Self.failure(forStatusCode: httpResponse.statusCode) {
            throw failure
        }

        return try ReleaseFeedDecoder.availableUpdate(from: data)
    }

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "\(ReleaseAssetNaming.appName)/\(version ?? "0.0.0")"
    }
}
