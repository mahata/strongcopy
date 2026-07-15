import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var feedbackController: CopyFeedbackController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItemController = StatusItemController()
        statusItemController.start()
        self.statusItemController = statusItemController

        let scheduler = TimerScheduler()
        let feedbackController = CopyFeedbackController(
            presenter: CopyHUDPresenter(),
            scheduler: scheduler
        )
        let clipboardMonitor = ClipboardMonitor(
            pasteboard: SystemPasteboard(),
            scheduler: scheduler
        ) {
            feedbackController.showFeedback()
        }

        self.feedbackController = feedbackController
        self.clipboardMonitor = clipboardMonitor
        clipboardMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        feedbackController?.stop()
        statusItemController?.stop()
    }
}
