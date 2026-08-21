import Foundation

enum UpdateAvailability {
    /// Installing replaces the running bundle in place and is pinned to the Team
    /// ID of the running code, so updating needs both a real `.app` and a
    /// Developer ID signature. `swift run` fails the first test and ad-hoc local
    /// builds fail the second.
    static func isSupported(bundleURL: URL, teamIdentifier: String?) -> Bool {
        guard bundleURL.pathExtension == "app" else {
            return false
        }

        guard let teamIdentifier, !teamIdentifier.isEmpty else {
            return false
        }

        return true
    }
}

final class UpdatePreferences {
    private enum Key {
        static let automaticChecks = "AutomaticUpdateChecksEnabled"
        static let declinedVersion = "DeclinedUpdateVersion"
        static let lastCheckDate = "LastUpdateCheckDate"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.automaticChecks: true])
    }

    var automaticChecksEnabled: Bool {
        get { defaults.bool(forKey: Key.automaticChecks) }
        set { defaults.set(newValue, forKey: Key.automaticChecks) }
    }

    var declinedVersion: AppVersion? {
        get { defaults.string(forKey: Key.declinedVersion).flatMap(AppVersion.init) }
        set { defaults.set(newValue?.description, forKey: Key.declinedVersion) }
    }

    var lastCheckDate: Date? {
        get { defaults.object(forKey: Key.lastCheckDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastCheckDate) }
    }
}

enum UpdatePromptResponse: Equatable {
    case install
    case later
}

@MainActor
protocol UpdatePresenting: AnyObject {
    func presentUpdatePrompt(_ update: AvailableUpdate) -> UpdatePromptResponse
    func presentNoUpdateAvailable(currentVersion: AppVersion)
    func presentFailure(message: String)
}

@MainActor
protocol UpdateInstalling: AnyObject {
    func install(_ update: AvailableUpdate) async throws
}

enum UpdateActivity: Equatable {
    case unavailable
    case idle
    case checking
    case installing
}

@MainActor
final class UpdateController {
    static let checkInterval: TimeInterval = 24 * 60 * 60
    nonisolated static let unavailableMessage =
        "Updates are available when Strongcopy runs from a signed app bundle, not from a development build."

    weak var presenter: (any UpdatePresenting)?

    private let feed: any UpdateFeed
    private let installer: any UpdateInstalling
    private let preferences: UpdatePreferences
    private let scheduler: any Scheduling
    private let installedVersion: AppVersion?
    private let isSupported: Bool
    private let now: @MainActor () -> Date
    private var scheduledCheck: (any Cancellation)?
    private var state: UpdateActivity = .idle

    init(
        feed: any UpdateFeed,
        installer: any UpdateInstalling,
        preferences: UpdatePreferences,
        scheduler: any Scheduling,
        installedVersion: AppVersion?,
        isSupported: Bool,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.feed = feed
        self.installer = installer
        self.preferences = preferences
        self.scheduler = scheduler
        self.installedVersion = installedVersion
        self.isSupported = isSupported
        self.now = now
    }

    convenience init(bundle: Bundle = .main, scheduler: any Scheduling) {
        let installedVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init)

        self.init(
            feed: GitHubUpdateFeed(),
            installer: DiskImageUpdateInstaller(bundle: bundle),
            preferences: UpdatePreferences(),
            scheduler: scheduler,
            installedVersion: installedVersion,
            isSupported: UpdateAvailability.isSupported(
                bundleURL: bundle.bundleURL,
                teamIdentifier: CodeSignatureInspector.runningIdentity()?.teamIdentifier
            )
        )
    }

    var activity: UpdateActivity {
        supportedVersion == nil ? .unavailable : state
    }

    var automaticChecksEnabled: Bool {
        preferences.automaticChecksEnabled
    }

    func start() {
        guard supportedVersion != nil, scheduledCheck == nil else {
            return
        }

        scheduledCheck = scheduler.scheduleRepeating(every: Self.checkInterval) { [weak self] in
            self?.checkOnSchedule()
        }
        checkOnSchedule()
    }

    func stop() {
        scheduledCheck?.cancel()
        scheduledCheck = nil
    }

    func checkOnSchedule() {
        guard shouldCheckOnSchedule() else {
            return
        }

        checkForUpdates(userInitiated: false)
    }

    /// The elapsed-time budget lives in preferences rather than in memory so that
    /// quitting and relaunching cannot turn into a burst of requests.
    func shouldCheckOnSchedule() -> Bool {
        guard supportedVersion != nil, preferences.automaticChecksEnabled else {
            return false
        }

        guard let lastCheckDate = preferences.lastCheckDate else {
            return true
        }

        let elapsed = now().timeIntervalSince(lastCheckDate)
        return elapsed >= Self.checkInterval || elapsed < 0
    }

    @discardableResult
    func checkForUpdates(userInitiated: Bool) -> Task<Void, Never> {
        Task { await performCheck(userInitiated: userInitiated) }
    }

    @discardableResult
    func toggleAutomaticChecks() -> Bool {
        preferences.automaticChecksEnabled.toggle()
        return preferences.automaticChecksEnabled
    }

    private var supportedVersion: AppVersion? {
        isSupported ? installedVersion : nil
    }

    private func performCheck(userInitiated: Bool) async {
        guard let installedVersion = supportedVersion else {
            if userInitiated {
                presenter?.presentFailure(message: Self.unavailableMessage)
            }
            return
        }

        guard state == .idle else {
            return
        }

        state = .checking
        defer { state = .idle }

        preferences.lastCheckDate = now()

        let update: AvailableUpdate
        do {
            update = try await feed.latestRelease()
        } catch {
            if userInitiated {
                presenter?.presentFailure(message: error.localizedDescription)
            }
            return
        }

        guard update.version > installedVersion else {
            if userInitiated {
                presenter?.presentNoUpdateAvailable(currentVersion: installedVersion)
            }
            return
        }

        // Releases land on every merge, so a version the user turned down stays
        // turned down until a newer one supersedes it. Asking explicitly always
        // gets an answer.
        if !userInitiated,
           let declinedVersion = preferences.declinedVersion,
           declinedVersion >= update.version {
            return
        }

        guard let presenter else {
            return
        }

        switch presenter.presentUpdatePrompt(update) {
        case .later:
            preferences.declinedVersion = update.version
            return
        case .install:
            break
        }

        state = .installing
        do {
            try await installer.install(update)
        } catch {
            presenter.presentFailure(message: error.localizedDescription)
        }
    }
}
