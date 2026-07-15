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
    private static let pointerOffset = NSSize(width: 12, height: 12)

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
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        else {
            return .zero
        }
        let visibleFrame = screen.visibleFrame

        return CopyHUDPlacement.panelOrigin(
            pointerLocation: mouseLocation,
            visibleFrame: visibleFrame,
            panelSize: Self.panelSize,
            pointerOffset: Self.pointerOffset
        )
    }
}

enum CopyHUDPlacement {
    static func panelOrigin(
        pointerLocation: NSPoint,
        visibleFrame: NSRect,
        panelSize: NSSize,
        pointerOffset: NSSize
    ) -> NSPoint {
        let proposedOrigin = NSPoint(
            x: pointerLocation.x + pointerOffset.width,
            y: pointerLocation.y + pointerOffset.height
        )
        let maximumOrigin = NSPoint(
            x: visibleFrame.maxX - panelSize.width,
            y: visibleFrame.maxY - panelSize.height
        )

        return NSPoint(
            x: min(max(proposedOrigin.x, visibleFrame.minX), maximumOrigin.x),
            y: min(max(proposedOrigin.y, visibleFrame.minY), maximumOrigin.y)
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
