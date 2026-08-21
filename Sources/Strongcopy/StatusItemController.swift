import AppKit
import StrongcopyBrand

enum StatusItemAppearance {
    static let accessibilityDescription = "Strongcopy"
    static let tooltip = "Strongcopy is running"
    static let pointSize: CGFloat = 16

    /// The app icon's mark, redrawn as a menu bar template so macOS can tint it for
    /// the light and dark menu bars and highlight it while the menu is open.
    static func menuBarImage() -> NSImage {
        let image = NSImage(
            size: NSSize(width: pointSize, height: pointSize),
            flipped: false
        ) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            BrandArtwork.drawStatusMark(in: context, extent: bounds.size)
            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}

enum StatusMenuItem: CaseIterable {
    case about
    case checkForUpdates
    case automaticUpdates
    case launchAtLogin
    case quit

    var title: String {
        switch self {
        case .about:
            return "About Strongcopy"
        case .checkForUpdates:
            return "Check for Updates…"
        case .automaticUpdates:
            return "Automatically Check for Updates"
        case .launchAtLogin:
            return "Open at Login"
        case .quit:
            return "Quit Strongcopy"
        }
    }
}

enum UpdateMenuPresentation {
    struct Appearance: Equatable {
        let title: String
        let state: NSControl.StateValue
        let isEnabled: Bool
        let toolTip: String?
    }

    static let unavailableToolTip = UpdateController.unavailableMessage

    static func checkAppearance(for activity: UpdateActivity) -> Appearance {
        switch activity {
        case .unavailable:
            return Appearance(
                title: StatusMenuItem.checkForUpdates.title,
                state: .off,
                isEnabled: false,
                toolTip: unavailableToolTip
            )
        case .idle:
            return Appearance(
                title: StatusMenuItem.checkForUpdates.title,
                state: .off,
                isEnabled: true,
                toolTip: nil
            )
        case .checking:
            return Appearance(title: "Checking for Updates…", state: .off, isEnabled: false, toolTip: nil)
        case .installing:
            return Appearance(title: "Installing Update…", state: .off, isEnabled: false, toolTip: nil)
        }
    }

    static func automaticAppearance(isOn: Bool, activity: UpdateActivity) -> Appearance {
        let title = StatusMenuItem.automaticUpdates.title

        guard activity != .unavailable else {
            return Appearance(title: title, state: .off, isEnabled: false, toolTip: unavailableToolTip)
        }

        return Appearance(title: title, state: isOn ? .on : .off, isEnabled: true, toolTip: nil)
    }
}

enum UpdatePromptText {
    static let restartNotice = "Strongcopy will replace itself and restart."

    /// Release notes are generated from merged pull requests and can run long, so
    /// the alert shows an opening excerpt rather than the whole changelog.
    static func informativeText(releaseNotes: String, limit: Int = 600) -> String {
        let notes = releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else {
            return restartNotice
        }

        let excerpt = notes.count > limit ? notes.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines) + "…" : notes
        return "\(excerpt)\n\n\(restartNotice)"
    }
}

enum AboutInfo {
    static func displayText(name: String?, version: String?) -> String {
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = (resolvedName?.isEmpty == false) ? (resolvedName ?? "Strongcopy") : "Strongcopy"

        let resolvedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedVersion, !resolvedVersion.isEmpty else {
            return "\(baseName) (dev)"
        }

        return "\(baseName) \(resolvedVersion)"
    }

    static func displayText(bundle: Bundle) -> String {
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return displayText(name: name, version: version)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let bundle: Bundle
    private let launchAtLogin: LaunchAtLoginController
    private let updates: UpdateController
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?
    private var automaticUpdatesItem: NSMenuItem?

    init(
        bundle: Bundle = .main,
        launchAtLogin: LaunchAtLoginController? = nil,
        updates: UpdateController? = nil
    ) {
        self.bundle = bundle
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginController()
        self.updates = updates ?? UpdateController(bundle: bundle, scheduler: TimerScheduler())
        super.init()
        self.updates.presenter = self
    }

    func start() {
        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusItemAppearance.menuBarImage()
            button.toolTip = StatusItemAppearance.tooltip
        }
        statusItem.menu = makeMenu()
        self.statusItem = statusItem
        updates.start()
    }

    func stop() {
        updates.stop()

        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        launchAtLoginItem = nil
        checkForUpdatesItem = nil
        automaticUpdatesItem = nil
    }

    private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = AboutInfo.displayText(bundle: bundle)
        alert.informativeText = "Strongcopy is running and watching the clipboard."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // Manual enablement is authoritative; auto-enabling would re-enable the
        // login item whenever its target responds to the action.
        menu.autoenablesItems = false
        for item in StatusMenuItem.allCases {
            switch item {
            case .about:
                menu.addItem(
                    withTitle: item.title,
                    action: #selector(handleAbout),
                    keyEquivalent: ""
                ).target = self
            case .checkForUpdates:
                menu.addItem(NSMenuItem.separator())
                let menuItem = menu.addItem(
                    withTitle: item.title,
                    action: #selector(handleCheckForUpdates),
                    keyEquivalent: ""
                )
                menuItem.target = self
                checkForUpdatesItem = menuItem
            case .automaticUpdates:
                let menuItem = menu.addItem(
                    withTitle: item.title,
                    action: #selector(handleAutomaticUpdates),
                    keyEquivalent: ""
                )
                menuItem.target = self
                automaticUpdatesItem = menuItem
            case .launchAtLogin:
                menu.addItem(NSMenuItem.separator())
                let menuItem = menu.addItem(
                    withTitle: item.title,
                    action: #selector(handleLaunchAtLogin),
                    keyEquivalent: ""
                )
                menuItem.target = self
                launchAtLoginItem = menuItem
            case .quit:
                menu.addItem(NSMenuItem.separator())
                menu.addItem(
                    withTitle: item.title,
                    action: #selector(handleQuit),
                    keyEquivalent: "q"
                ).target = self
            }
        }
        refreshLaunchAtLoginItem()
        refreshUpdateItems()
        return menu
    }

    private func refreshUpdateItems() {
        let activity = updates.activity

        if let checkForUpdatesItem {
            let appearance = UpdateMenuPresentation.checkAppearance(for: activity)
            checkForUpdatesItem.title = appearance.title
            checkForUpdatesItem.isEnabled = appearance.isEnabled
            checkForUpdatesItem.toolTip = appearance.toolTip
        }

        if let automaticUpdatesItem {
            let appearance = UpdateMenuPresentation.automaticAppearance(
                isOn: updates.automaticChecksEnabled,
                activity: activity
            )
            automaticUpdatesItem.state = appearance.state
            automaticUpdatesItem.isEnabled = appearance.isEnabled
            automaticUpdatesItem.toolTip = appearance.toolTip
        }
    }

    private func refreshLaunchAtLoginItem() {
        guard let launchAtLoginItem else {
            return
        }

        let appearance = LaunchAtLoginMenuPresentation.appearance(for: launchAtLogin.state)
        launchAtLoginItem.state = appearance.state
        launchAtLoginItem.isEnabled = appearance.isEnabled
        launchAtLoginItem.toolTip = appearance.toolTip
    }

    private func handleToggleOutcome(_ outcome: LaunchAtLoginController.ToggleOutcome) {
        switch outcome {
        case .enabled, .disabled, .unavailable:
            break
        case .requiresApproval:
            showApprovalPrompt()
        case .failed(let message):
            showFailure(message: message)
        }

        refreshLaunchAtLoginItem()
    }

    private func showApprovalPrompt() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Strongcopy needs approval to open at login"
        alert.informativeText =
            "Allow Strongcopy under Login Items in System Settings > General > Login Items."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            launchAtLogin.openSystemSettings()
        }
    }

    private func showFailure(message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't change the login item"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc
    private func handleAbout() {
        showAbout()
    }

    @objc
    private func handleLaunchAtLogin() {
        handleToggleOutcome(launchAtLogin.toggle())
    }

    @objc
    private func handleCheckForUpdates() {
        updates.checkForUpdates(userInitiated: true)
        refreshUpdateItems()
    }

    @objc
    private func handleAutomaticUpdates() {
        updates.toggleAutomaticChecks()
        refreshUpdateItems()
    }

    @objc
    private func handleQuit() {
        quit()
    }
}

extension StatusItemController: UpdatePresenting {
    func presentUpdatePrompt(_ update: AvailableUpdate) -> UpdatePromptResponse {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Strongcopy \(update.version) is available"
        alert.informativeText = UpdatePromptText.informativeText(releaseNotes: update.releaseNotes)
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")

        return alert.runModal() == .alertFirstButtonReturn ? .install : .later
    }

    func presentNoUpdateAvailable(currentVersion: AppVersion) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Strongcopy is up to date"
        alert.informativeText = "Version \(currentVersion) is the latest release."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentFailure(message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't update Strongcopy"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLaunchAtLoginItem()
        refreshUpdateItems()
    }
}
