import AppKit

enum StatusItemAppearance {
    static let symbolName = "clipboard"
    static let accessibilityDescription = "Strongcopy"
    static let tooltip = "Strongcopy is running"
}

enum StatusMenuItem: CaseIterable {
    case about
    case launchAtLogin
    case quit

    var title: String {
        switch self {
        case .about:
            return "About Strongcopy"
        case .launchAtLogin:
            return "Open at Login"
        case .quit:
            return "Quit Strongcopy"
        }
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
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    init(
        bundle: Bundle = .main,
        launchAtLogin: LaunchAtLoginController? = nil
    ) {
        self.bundle = bundle
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginController()
        super.init()
    }

    func start() {
        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: StatusItemAppearance.symbolName,
                accessibilityDescription: StatusItemAppearance.accessibilityDescription
            )
            button.image?.isTemplate = true
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
