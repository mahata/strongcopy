import AppKit
import Foundation

@MainActor
protocol PasteboardChangeCounting: AnyObject {
    var changeCount: Int { get }
}

@MainActor
final class SystemPasteboard: PasteboardChangeCounting {
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }
}

@MainActor
final class ClipboardMonitor {
    static let defaultPollingInterval: TimeInterval = 0.2

    private let pasteboard: any PasteboardChangeCounting
    private let scheduler: any Scheduling
    private let pollingInterval: TimeInterval
    private let onChange: @MainActor () -> Void
    private var lastChangeCount: Int?
    private var pollingCancellation: (any Cancellation)?

    init(
        pasteboard: any PasteboardChangeCounting,
        scheduler: any Scheduling,
        pollingInterval: TimeInterval = defaultPollingInterval,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler
        self.pollingInterval = pollingInterval
        self.onChange = onChange
    }

    func start() {
        guard pollingCancellation == nil else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        pollingCancellation = scheduler.scheduleRepeating(every: pollingInterval) { [weak self] in
            self?.checkForChanges()
        }
    }

    func stop() {
        pollingCancellation?.cancel()
        pollingCancellation = nil
        lastChangeCount = nil
    }

    private func checkForChanges() {
        let currentChangeCount = pasteboard.changeCount

        guard let lastChangeCount else {
            self.lastChangeCount = currentChangeCount
            return
        }
        guard currentChangeCount != lastChangeCount else {
            return
        }

        self.lastChangeCount = currentChangeCount
        onChange()
    }
}
