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
    case privacyPolicy
    case launchAtLogin
    case quit

    var title: String {
        switch self {
        case .about:
            return "About Strongcopy"
        case .privacyPolicy:
            return "Privacy Policy"
        case .launchAtLogin:
            return "Open at Login"
        case .quit:
            return "Quit Strongcopy"
        }
    }
}

/// Addresses the app links out to. App Review guideline 5.1.1(i) asks for the
/// privacy policy to be reachable from inside the app and not only from the
/// App Store listing, which an accessory app with no window has to satisfy from
/// its menu bar.
enum StrongcopyLinks {
    static let privacyPolicy = "https://strongcopy.mahata.org/privacy/"
}

@MainActor
protocol URLOpening: AnyObject {
    func open(_ url: URL)
}

@MainActor
final class WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
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
    private let urlOpener: any URLOpening
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    // Dependencies are constructed in the body rather than as default arguments,
    // because default arguments are evaluated in a nonisolated context outside
    // Swift 6 mode.
    init(
        bundle: Bundle = .main,
        launchAtLogin: LaunchAtLoginController? = nil,
        urlOpener: (any URLOpening)? = nil
    ) {
        self.bundle = bundle
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginController()
        self.urlOpener = urlOpener ?? WorkspaceURLOpener()
        super.init()
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
    }

    func stop() {
        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        launchAtLoginItem = nil
    }

    private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = AboutInfo.displayText(bundle: bundle)
        alert.informativeText = "Strongcopy is running and watching the clipboard."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openPrivacyPolicy() {
        guard let url = URL(string: StrongcopyLinks.privacyPolicy) else {
            return
        }

        urlOpener.open(url)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // Internal rather than private so tests can build the menu without putting a
    // real item in the menu bar.
    func makeMenu() -> NSMenu {
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
            case .privacyPolicy:
                menu.addItem(
                    withTitle: item.title,
                    action: #selector(handlePrivacyPolicy),
                    keyEquivalent: ""
                ).target = self
            case .launchAtLogin:
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
        return menu
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
    private func handlePrivacyPolicy() {
        openPrivacyPolicy()
    }

    @objc
    private func handleLaunchAtLogin() {
        handleToggleOutcome(launchAtLogin.toggle())
    }

    @objc
    private func handleQuit() {
        quit()
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLaunchAtLoginItem()
    }
}
