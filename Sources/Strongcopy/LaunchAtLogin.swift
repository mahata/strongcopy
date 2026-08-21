import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

extension LaunchAtLoginState {
    init(status: SMAppService.Status) {
        switch status {
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        // A login item that was never registered reports `notFound`, which is the
        // ordinary starting state for a freshly installed app rather than a
        // failure. Only a missing app bundle makes the feature unavailable, and
        // that is decided from the bundle path instead.
        case .notRegistered, .notFound:
            self = .disabled
        @unknown default:
            self = .disabled
        }
    }
}

enum LaunchAtLoginAvailability {
    /// `SMAppService` cannot distinguish a development build from a freshly
    /// installed app by status alone: both report `notFound`. The bundle path is
    /// the only reliable signal.
    static func isSupported(bundleURL: URL) -> Bool {
        bundleURL.pathExtension == "app"
    }
}

@MainActor
protocol LoginItemRegistering: AnyObject {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class SMAppServiceLoginItem: LoginItemRegistering {
    private let service: SMAppService
    private let isSupported: Bool

    init(bundle: Bundle = .main) {
        self.service = .mainApp
        self.isSupported = LaunchAtLoginAvailability.isSupported(bundleURL: bundle.bundleURL)
    }

    var state: LaunchAtLoginState {
        guard isSupported else {
            return .unavailable
        }
        return LaunchAtLoginState(status: service.status)
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginController {
    enum ToggleOutcome: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
        case failed(String)
    }

    private let loginItem: any LoginItemRegistering

    // Constructed in the body rather than as a default argument, because default
    // arguments are evaluated in a nonisolated context outside Swift 6 mode.
    init(loginItem: (any LoginItemRegistering)? = nil) {
        self.loginItem = loginItem ?? SMAppServiceLoginItem()
    }

    var state: LaunchAtLoginState {
        loginItem.state
    }

    func toggle() -> ToggleOutcome {
        switch loginItem.state {
        case .unavailable:
            return .unavailable
        case .requiresApproval:
            return .requiresApproval
        case .enabled:
            do {
                try loginItem.unregister()
            } catch {
                return .failed(error.localizedDescription)
            }
        case .disabled:
            do {
                try loginItem.register()
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        // register() and unregister() report success even when they cannot take
        // effect, so the resulting state is the only trustworthy signal.
        return outcome(for: loginItem.state)
    }

    func openSystemSettings() {
        loginItem.openSystemSettings()
    }

    private func outcome(for state: LaunchAtLoginState) -> ToggleOutcome {
        switch state {
        case .enabled:
            return .enabled
        case .disabled:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .unavailable:
            return .unavailable
        }
    }
}

enum LaunchAtLoginMenuPresentation {
    struct Appearance: Equatable {
        let state: NSControl.StateValue
        let isEnabled: Bool
        let toolTip: String?
    }

    static let unavailableToolTip =
        "Available when Strongcopy runs from its app bundle, not from a development build."

    static func appearance(for state: LaunchAtLoginState) -> Appearance {
        switch state {
        case .enabled:
            return Appearance(state: .on, isEnabled: true, toolTip: nil)
        case .disabled:
            return Appearance(state: .off, isEnabled: true, toolTip: nil)
        case .requiresApproval:
            return Appearance(state: .mixed, isEnabled: true, toolTip: nil)
        case .unavailable:
            return Appearance(state: .off, isEnabled: false, toolTip: unavailableToolTip)
        }
    }
}
