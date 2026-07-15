import AppKit
import SwiftUI

@MainActor
protocol CopyFeedbackPresenting: AnyObject {
    func show()
    func hide()
}

@MainActor
final class CopyFeedbackController {
    static let defaultDisplayDuration: TimeInterval = 0.8

    private let presenter: any CopyFeedbackPresenting
    private let scheduler: any Scheduling
    private let displayDuration: TimeInterval
    private var dismissalCancellation: (any Cancellation)?

    init(
        presenter: any CopyFeedbackPresenting,
        scheduler: any Scheduling,
        displayDuration: TimeInterval = defaultDisplayDuration
    ) {
        self.presenter = presenter
        self.scheduler = scheduler
        self.displayDuration = displayDuration
    }

    func showFeedback() {
        presenter.show()
        dismissalCancellation?.cancel()
        dismissalCancellation = scheduler.schedule(after: displayDuration) { [weak self] in
            self?.hideFeedback()
        }
    }

    func stop() {
        dismissalCancellation?.cancel()
        dismissalCancellation = nil
        presenter.hide()
    }

    private func hideFeedback() {
        dismissalCancellation = nil
        presenter.hide()
    }
}

@MainActor
final class CopyHUDPresenter: CopyFeedbackPresenting {
    private static let panelSize = NSSize(width: 132, height: 52)
    private static let screenMargin: CGFloat = 24

    private lazy var panel: NSPanel = makePanel()

    func show() {
        panel.setFrameOrigin(panelOrigin())
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: CopyHUDView())
        return panel
    }

    private func panelOrigin() -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        return NSPoint(
            x: visibleFrame.maxX - Self.panelSize.width - Self.screenMargin,
            y: visibleFrame.maxY - Self.panelSize.height - Self.screenMargin
        )
    }
}

private struct CopyHUDView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Copied")
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
