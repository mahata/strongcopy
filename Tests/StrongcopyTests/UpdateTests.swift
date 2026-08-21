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

final class UpdatePreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "org.mahata.strongcopy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAutomaticChecksAreEnabledUntilTheUserOptsOut() {
        XCTAssertTrue(UpdatePreferences(defaults: defaults).automaticChecksEnabled)
    }

    func testOptingOutOfAutomaticChecksPersists() {
        UpdatePreferences(defaults: defaults).automaticChecksEnabled = false

        XCTAssertFalse(UpdatePreferences(defaults: defaults).automaticChecksEnabled)
    }

    func testDeclinedVersionRoundTrips() {
        let preferences = UpdatePreferences(defaults: defaults)
        preferences.declinedVersion = AppVersion("1.4.2")

        XCTAssertEqual(UpdatePreferences(defaults: defaults).declinedVersion, AppVersion("1.4.2"))
    }

    func testDeclinedVersionIsAbsentUntilSet() {
        XCTAssertNil(UpdatePreferences(defaults: defaults).declinedVersion)
    }

    func testUnreadableStoredVersionIsTreatedAsAbsent() {
        defaults.set("garbage", forKey: "DeclinedUpdateVersion")

        XCTAssertNil(UpdatePreferences(defaults: defaults).declinedVersion)
    }

    func testClearingDeclinedVersionRemovesIt() {
        let preferences = UpdatePreferences(defaults: defaults)
        preferences.declinedVersion = AppVersion("1.4.2")
        preferences.declinedVersion = nil

        XCTAssertNil(UpdatePreferences(defaults: defaults).declinedVersion)
    }

    func testLastCheckDateRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        UpdatePreferences(defaults: defaults).lastCheckDate = date

        XCTAssertEqual(UpdatePreferences(defaults: defaults).lastCheckDate, date)
    }
}

final class UpdateAvailabilityTests: XCTestCase {
    func testSignedAppBundleIsSupported() {
        XCTAssertTrue(
            UpdateAvailability.isSupported(
                bundleURL: URL(fileURLWithPath: "/Applications/Strongcopy.app"),
                teamIdentifier: "ABCDE12345"
            )
        )
    }

    // An ad-hoc signature carries no Team ID, so the pinned requirement that
    // guards the download cannot be built and updating must stay unavailable.
    func testAdHocSignedBundleIsNotSupported() {
        XCTAssertFalse(
            UpdateAvailability.isSupported(
                bundleURL: URL(fileURLWithPath: "/Applications/Strongcopy.app"),
                teamIdentifier: nil
            )
        )
        XCTAssertFalse(
            UpdateAvailability.isSupported(
                bundleURL: URL(fileURLWithPath: "/Applications/Strongcopy.app"),
                teamIdentifier: ""
            )
        )
    }

    func testBareExecutableDirectoryIsNotSupported() {
        XCTAssertFalse(
            UpdateAvailability.isSupported(
                bundleURL: URL(fileURLWithPath: "/Users/example/strongcopy/.build/debug"),
                teamIdentifier: "ABCDE12345"
            )
        )
    }
}

@MainActor
final class UpdateControllerTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var preferences = UpdatePreferences(defaults: .standard)
    private var feed = FakeUpdateFeed()
    private var installer = FakeUpdateInstaller()
    private var presenter = RecordingUpdatePresenter()
    private var scheduler = RecordingScheduler()
    private var clock = MutableClock()

    private let installedVersion = AppVersion("1.0.0")!

    override func setUp() {
        super.setUp()
        suiteName = "org.mahata.strongcopy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        preferences = UpdatePreferences(defaults: defaults)
        feed = FakeUpdateFeed()
        installer = FakeUpdateInstaller()
        presenter = RecordingUpdatePresenter()
        scheduler = RecordingScheduler()
        clock = MutableClock()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeController(isSupported: Bool = true) -> UpdateController {
        let controller = UpdateController(
            feed: feed,
            installer: installer,
            preferences: preferences,
            scheduler: scheduler,
            installedVersion: installedVersion,
            isSupported: isSupported,
            now: { [clock] in clock.date }
        )
        controller.presenter = presenter
        return controller
    }

    private func update(_ version: String) -> AvailableUpdate {
        AvailableUpdate(
            version: AppVersion(version)!,
            diskImageURL: URL(string: "https://example.invalid/Strongcopy-\(version).dmg")!,
            checksumURL: URL(string: "https://example.invalid/Strongcopy-\(version).dmg.sha256")!,
            releaseNotes: "Notes"
        )
    }

    func testNewerReleaseIsOfferedAndInstalledWhenAccepted() async {
        await feed.setResult(.success(update("1.1.0")))
        presenter.promptResponse = .install
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: true).value

        XCTAssertEqual(presenter.promptedUpdates.map(\.version), [AppVersion("1.1.0")])
        XCTAssertEqual(installer.installedUpdates.map(\.version), [AppVersion("1.1.0")])
    }

    func testDecliningRecordsTheVersionWithoutInstalling() async {
        await feed.setResult(.success(update("1.1.0")))
        presenter.promptResponse = .later
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: true).value

        XCTAssertTrue(installer.installedUpdates.isEmpty)
        XCTAssertEqual(preferences.declinedVersion, AppVersion("1.1.0"))
    }

    func testDeclinedVersionIsNotOfferedAgainOnAScheduledCheck() async {
        preferences.declinedVersion = AppVersion("1.1.0")
        await feed.setResult(.success(update("1.1.0")))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: false).value

        XCTAssertTrue(presenter.promptedUpdates.isEmpty)
    }

    func testAReleaseNewerThanTheDeclinedOneIsOfferedAgain() async {
        preferences.declinedVersion = AppVersion("1.1.0")
        await feed.setResult(.success(update("1.2.0")))
        presenter.promptResponse = .later
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: false).value

        XCTAssertEqual(presenter.promptedUpdates.map(\.version), [AppVersion("1.2.0")])
    }

    func testAskingExplicitlyOffersEvenAPreviouslyDeclinedVersion() async {
        preferences.declinedVersion = AppVersion("1.1.0")
        await feed.setResult(.success(update("1.1.0")))
        presenter.promptResponse = .later
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: true).value

        XCTAssertEqual(presenter.promptedUpdates.map(\.version), [AppVersion("1.1.0")])
    }

    func testSameVersionIsReportedAsUpToDateWhenAskedExplicitly() async {
        await feed.setResult(.success(update("1.0.0")))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: true).value

        XCTAssertEqual(presenter.upToDateVersions, [installedVersion])
        XCTAssertTrue(presenter.promptedUpdates.isEmpty)
    }

    func testOlderReleaseIsNeverOffered() async {
        await feed.setResult(.success(update("0.9.0")))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: true).value

        XCTAssertTrue(presenter.promptedUpdates.isEmpty)
        XCTAssertEqual(presenter.upToDateVersions, [installedVersion])
    }

    func testScheduledCheckStaysSilentWhenAlreadyUpToDate() async {
        await feed.setResult(.success(update("1.0.0")))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: false).value

        XCTAssertTrue(presenter.upToDateVersions.isEmpty)
        XCTAssertTrue(presenter.failureMessages.isEmpty)
    }

    func testFeedFailureIsReportedWhenAskedExplicitly() async {
        await feed.setResult(.failure(UpdateFeedError.rateLimited))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: true).value

        XCTAssertEqual(presenter.failureMessages.count, 1)
    }

    func testFeedFailureStaysSilentOnAScheduledCheck() async {
        await feed.setResult(.failure(UpdateFeedError.rateLimited))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: false).value

        XCTAssertTrue(presenter.failureMessages.isEmpty)
    }

    func testInstallFailureIsAlwaysReported() async {
        await feed.setResult(.success(update("1.1.0")))
        presenter.promptResponse = .install
        installer.failure = FakeInstallError.denied
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: false).value

        XCTAssertEqual(presenter.failureMessages, [FakeInstallError.denied.localizedDescription])
    }

    func testCheckingRecordsTheTimeOfTheAttempt() async {
        await feed.setResult(.failure(UpdateFeedError.rateLimited))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: false).value

        XCTAssertEqual(preferences.lastCheckDate, clock.date)
    }

    func testUnsupportedBuildNeverContactsTheFeed() async {
        await feed.setResult(.success(update("1.1.0")))
        let controller = makeController(isSupported: false)

        await controller.checkForUpdates(userInitiated: true).value

        let requestCount = await feed.requestCount
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(presenter.failureMessages, [UpdateController.unavailableMessage])
        XCTAssertEqual(controller.activity, .unavailable)
    }

    func testActivityReturnsToIdleAfterAcheck() async {
        await feed.setResult(.success(update("1.0.0")))
        let controller = makeController()

        await controller.checkForUpdates(userInitiated: true).value

        XCTAssertEqual(controller.activity, .idle)
    }

    func testASecondCheckIsIgnoredWhileOneIsInFlight() async {
        await feed.setResult(.success(update("1.1.0")))
        presenter.promptResponse = .later
        let controller = makeController()

        let first = controller.checkForUpdates(userInitiated: true)
        let second = controller.checkForUpdates(userInitiated: true)
        await first.value
        await second.value

        let requestCount = await feed.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(presenter.promptedUpdates.count, 1)
    }

    func testScheduledCheckingIsSkippedWhenTheUserOptedOut() {
        preferences.automaticChecksEnabled = false

        XCTAssertFalse(makeController().shouldCheckOnSchedule())
    }

    func testScheduledCheckingIsSkippedOnUnsupportedBuilds() {
        XCTAssertFalse(makeController(isSupported: false).shouldCheckOnSchedule())
    }

    func testScheduledCheckingRunsWhenNothingWasCheckedYet() {
        XCTAssertTrue(makeController().shouldCheckOnSchedule())
    }

    func testScheduledCheckingIsSkippedSoonAfterTheLastCheck() {
        preferences.lastCheckDate = clock.date
        clock.date += UpdateController.checkInterval - 1

        XCTAssertFalse(makeController().shouldCheckOnSchedule())
    }

    func testScheduledCheckingResumesOnceTheIntervalHasElapsed() {
        preferences.lastCheckDate = clock.date
        clock.date += UpdateController.checkInterval

        XCTAssertTrue(makeController().shouldCheckOnSchedule())
    }

    // A clock that moved backwards would otherwise leave the app stuck without
    // checking until real time caught up with the stored timestamp.
    func testScheduledCheckingRunsWhenTheStoredTimeIsInTheFuture() {
        preferences.lastCheckDate = clock.date + UpdateController.checkInterval

        XCTAssertTrue(makeController().shouldCheckOnSchedule())
    }

    func testStartingSchedulesADailyCheckThatStoppingCancels() {
        preferences.automaticChecksEnabled = false
        let controller = makeController()

        controller.start()

        XCTAssertEqual(scheduler.repeatingIntervals, [UpdateController.checkInterval])
        XCTAssertFalse(scheduler.isRepeatingCancelled)

        controller.stop()

        XCTAssertTrue(scheduler.isRepeatingCancelled)
    }

    func testUnsupportedBuildSchedulesNothing() {
        makeController(isSupported: false).start()

        XCTAssertTrue(scheduler.repeatingIntervals.isEmpty)
    }

    func testTogglingAutomaticChecksFlipsThePreference() {
        let controller = makeController()

        XCTAssertFalse(controller.toggleAutomaticChecks())
        XCTAssertFalse(preferences.automaticChecksEnabled)
        XCTAssertTrue(controller.toggleAutomaticChecks())
        XCTAssertTrue(preferences.automaticChecksEnabled)
    }
}

private enum FakeInstallError: Error, LocalizedError {
    case denied

    var errorDescription: String? {
        "Strongcopy could not be replaced."
    }
}

private actor FakeUpdateFeed: UpdateFeed {
    private var result: Result<AvailableUpdate, Error> = .failure(UpdateFeedError.malformedPayload)
    private(set) var requestCount = 0

    func setResult(_ result: Result<AvailableUpdate, Error>) {
        self.result = result
    }

    func latestRelease() async throws -> AvailableUpdate {
        requestCount += 1
        return try result.get()
    }
}

@MainActor
private final class FakeUpdateInstaller: UpdateInstalling {
    private(set) var installedUpdates: [AvailableUpdate] = []
    var failure: Error?

    func install(_ update: AvailableUpdate) async throws {
        if let failure {
            throw failure
        }
        installedUpdates.append(update)
    }
}

@MainActor
private final class RecordingUpdatePresenter: UpdatePresenting {
    private(set) var promptedUpdates: [AvailableUpdate] = []
    private(set) var upToDateVersions: [AppVersion] = []
    private(set) var failureMessages: [String] = []
    var promptResponse: UpdatePromptResponse = .later

    func presentUpdatePrompt(_ update: AvailableUpdate) -> UpdatePromptResponse {
        promptedUpdates.append(update)
        return promptResponse
    }

    func presentNoUpdateAvailable(currentVersion: AppVersion) {
        upToDateVersions.append(currentVersion)
    }

    func presentFailure(message: String) {
        failureMessages.append(message)
    }
}

@MainActor
private final class MutableClock {
    var date = Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private final class RecordingScheduler: Scheduling {
    private(set) var repeatingIntervals: [TimeInterval] = []
    private var repeatingCancellation: RecordedCancellation?

    var isRepeatingCancelled: Bool {
        repeatingCancellation?.isCancelled ?? false
    }

    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation {
        repeatingIntervals.append(interval)
        let cancellation = RecordedCancellation()
        repeatingCancellation = cancellation
        return cancellation
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation {
        RecordedCancellation()
    }
}

@MainActor
private final class RecordedCancellation: Cancellation {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}
