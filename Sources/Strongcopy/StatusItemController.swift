import AppKit

enum StatusItemAppearance {
    static let symbolName = "clipboard"
    static let accessibilityDescription = "Strongcopy"
    static let tooltip = "Strongcopy is running"
}

enum StatusMenuItem: CaseIterable {
    case about
    case quit

    var title: String {
        switch self {
        case .about:
            return "About Strongcopy"
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
final class StatusItemController {
    private let bundle: Bundle
    private var statusItem: NSStatusItem?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
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
        for item in StatusMenuItem.allCases {
            switch item {
            case .about:
                menu.addItem(
                    withTitle: item.title,
                    action: #selector(handleAbout),
                    keyEquivalent: ""
                ).target = self
            case .quit:
                menu.addItem(NSMenuItem.separator())
                menu.addItem(
                    withTitle: item.title,
                    action: #selector(handleQuit),
                    keyEquivalent: "q"
                ).target = self
            }
        }
        return menu
    }

    @objc
    private func handleAbout() {
        showAbout()
    }

    @objc
    private func handleQuit() {
        quit()
    }
}
