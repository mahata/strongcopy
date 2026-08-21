import XCTest
@testable import Strongcopy

final class AppVersionTests: XCTestCase {
    func testParsesPlainVersion() {
        XCTAssertEqual(AppVersion("1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
    }

    func testParsesReleaseTagWithLeadingV() {
        XCTAssertEqual(AppVersion("v0.1.5"), AppVersion(major: 0, minor: 1, patch: 5))
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(AppVersion("  v2.0.1  "), AppVersion(major: 2, minor: 0, patch: 1))
    }

    func testRejectsMalformedVersions() {
        for text in ["", "v", "1.2", "1.2.3.4", "1.2.x", "-1.0.0", "1.-2.3", "one.two.three", "  "] {
            XCTAssertNil(AppVersion(text), "Expected \(text) to be rejected")
        }
    }

    func testOrdersByMajorThenMinorThenPatch() {
        XCTAssertLessThan(AppVersion("1.0.0")!, AppVersion("2.0.0")!)
        XCTAssertLessThan(AppVersion("1.1.0")!, AppVersion("1.2.0")!)
        XCTAssertLessThan(AppVersion("1.1.1")!, AppVersion("1.1.2")!)
        XCTAssertLessThan(AppVersion("1.9.9")!, AppVersion("2.0.0")!)
    }

    func testComparesNumericallyRatherThanLexicographically() {
        XCTAssertLessThan(AppVersion("0.1.9")!, AppVersion("0.1.10")!)
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!)
    }

    func testEqualVersionsAreNotOrdered() {
        XCTAssertFalse(AppVersion("1.2.3")! < AppVersion("1.2.3")!)
        XCTAssertEqual(AppVersion("1.2.3"), AppVersion("v1.2.3"))
    }

    func testDescriptionOmitsTagPrefix() {
        XCTAssertEqual(AppVersion("v1.2.3")!.description, "1.2.3")
    }
}

final class ReleaseFeedDecodingTests: XCTestCase {
    private func payload(
        tag: String = "v0.1.5",
        draft: Bool = false,
        prerelease: Bool = false,
        body: String = "## What's Changed",
        assets: [(String, String)] = [
            (
                "Strongcopy-0.1.5.dmg",
                "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg"
            ),
            (
                "Strongcopy-0.1.5.dmg.sha256",
                "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg.sha256"
            ),
        ]
    ) -> Data {
        let encodedAssets = assets
            .map { #"{"name":"\#($0.0)","browser_download_url":"\#($0.1)"}"# }
            .joined(separator: ",")

        return Data(
            """
            {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),\
            "body":"\(body)","assets":[\(encodedAssets)]}
            """.utf8
        )
    }

    func testDecodesVersionAssetsAndNotes() throws {
        let update = try ReleaseFeedDecoder.availableUpdate(from: payload())

        XCTAssertEqual(update.version, AppVersion(major: 0, minor: 1, patch: 5))
        XCTAssertEqual(
            update.diskImageURL.absoluteString,
            "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg"
        )
        XCTAssertEqual(
            update.checksumURL.absoluteString,
            "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg.sha256"
        )
        XCTAssertEqual(update.releaseNotes, "## What's Changed")
        XCTAssertEqual(update.diskImageName, "Strongcopy-0.1.5.dmg")
    }

    func testRejectsDraftRelease() {
        assertThrows(.unpublishedRelease, from: payload(draft: true))
    }

    func testRejectsPrerelease() {
        assertThrows(.unpublishedRelease, from: payload(prerelease: true))
    }

    func testRejectsUnreadableTag() {
        assertThrows(.unreadableVersion("nightly"), from: payload(tag: "nightly"))
    }

    func testRejectsMissingDiskImageAsset() {
        assertThrows(
            .missingAsset("Strongcopy-0.1.5.dmg"),
            from: payload(assets: [
                (
                    "Strongcopy-0.1.5.dmg.sha256",
                    "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg.sha256"
                )
            ])
        )
    }

    func testRejectsMissingChecksumAsset() {
        assertThrows(
            .missingAsset("Strongcopy-0.1.5.dmg.sha256"),
            from: payload(assets: [
                (
                    "Strongcopy-0.1.5.dmg",
                    "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg"
                )
            ])
        )
    }

    // A release whose assets carry a different version than the tag cannot be
    // verified after download, because the mounted bundle is checked against the
    // tag.
    func testRejectsAssetsNamedForAnotherVersion() {
        assertThrows(
            .missingAsset("Strongcopy-0.1.5.dmg"),
            from: payload(assets: [
                (
                    "Strongcopy-9.9.9.dmg",
                    "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-9.9.9.dmg"
                ),
                (
                    "Strongcopy-9.9.9.dmg.sha256",
                    "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-9.9.9.dmg.sha256"
                ),
            ])
        )
    }

    func testRejectsAssetServedOverPlainHTTP() {
        assertThrows(
            .insecureAssetURL("Strongcopy-0.1.5.dmg"),
            from: payload(assets: [
                (
                    "Strongcopy-0.1.5.dmg",
                    "http://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg"
                ),
                (
                    "Strongcopy-0.1.5.dmg.sha256",
                    "https://github.com/mahata/strongcopy/releases/download/v0.1.5/Strongcopy-0.1.5.dmg.sha256"
                ),
            ])
        )
    }

    func testRejectsMalformedPayload() {
        assertThrows(.malformedPayload, from: Data("not json".utf8))
    }

    private func assertThrows(
        _ expected: UpdateFeedError,
        from data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try ReleaseFeedDecoder.availableUpdate(from: data), file: file, line: line) { error in
            XCTAssertEqual(error as? UpdateFeedError, expected, file: file, line: line)
        }
    }
}

final class GitHubUpdateFeedRequestTests: XCTestCase {
    func testRequestsTheLatestReleaseOverHTTPS() {
        let request = GitHubUpdateFeed.makeRequest(url: GitHubUpdateFeed.latestReleaseURL)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/mahata/strongcopy/releases/latest"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    // GitHub rejects API requests that arrive without a User-Agent.
    func testSendsAUserAgent() {
        let request = GitHubUpdateFeed.makeRequest(url: GitHubUpdateFeed.latestReleaseURL)

        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent")?.isEmpty, false)
    }

    func testTreatsRateLimitingAsItsOwnFailure() {
        XCTAssertEqual(GitHubUpdateFeed.failure(forStatusCode: 403), .rateLimited)
        XCTAssertEqual(GitHubUpdateFeed.failure(forStatusCode: 429), .rateLimited)
        XCTAssertEqual(GitHubUpdateFeed.failure(forStatusCode: 500), .requestFailed(500))
        XCTAssertNil(GitHubUpdateFeed.failure(forStatusCode: 200))
    }
}
