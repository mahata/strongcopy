import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var feedbackController: CopyFeedbackController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scheduler = TimerScheduler()

        let statusItemController = StatusItemController(
            updates: UpdateController(scheduler: scheduler)
        )
        statusItemController.start()
        self.statusItemController = statusItemController

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
