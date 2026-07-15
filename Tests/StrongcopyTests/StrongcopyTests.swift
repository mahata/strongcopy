import XCTest
@testable import Strongcopy

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testStartEstablishesBaselineWithoutFeedback() {
        let pasteboard = FakePasteboard(changeCount: 7)
        let scheduler = ManualScheduler()
        var feedbackCount = 0
        let monitor = ClipboardMonitor(pasteboard: pasteboard, scheduler: scheduler) {
            feedbackCount += 1
        }

        monitor.start()
        scheduler.fireRepeating()

        XCTAssertEqual(feedbackCount, 0)
    }

    func testChangeCountTransitionProducesOneFeedback() {
        let pasteboard = FakePasteboard(changeCount: 7)
        let scheduler = ManualScheduler()
        var feedbackCount = 0
        let monitor = ClipboardMonitor(pasteboard: pasteboard, scheduler: scheduler) {
            feedbackCount += 1
        }

        monitor.start()
        pasteboard.changeCount = 8
        scheduler.fireRepeating()
        scheduler.fireRepeating()

        XCTAssertEqual(feedbackCount, 1)
    }

    func testEachObservedTransitionProducesFeedback() {
        let pasteboard = FakePasteboard(changeCount: 7)
        let scheduler = ManualScheduler()
        var feedbackCount = 0
        let monitor = ClipboardMonitor(pasteboard: pasteboard, scheduler: scheduler) {
            feedbackCount += 1
        }

        monitor.start()
        pasteboard.changeCount = 8
        scheduler.fireRepeating()
        pasteboard.changeCount = 10
        scheduler.fireRepeating()

        XCTAssertEqual(feedbackCount, 2)
    }
}

@MainActor
final class CopyFeedbackControllerTests: XCTestCase {
    func testRepeatedFeedbackRefreshesDismissalWithoutStackingHides() {
        let presenter = RecordingFeedbackPresenter()
        let scheduler = ManualScheduler()
        let controller = CopyFeedbackController(presenter: presenter, scheduler: scheduler)

        controller.showFeedback()
        controller.showFeedback()
        scheduler.fireScheduled()

        XCTAssertEqual(presenter.showCount, 2)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testStopHidesFeedbackAndCancelsPendingDismissal() {
        let presenter = RecordingFeedbackPresenter()
        let scheduler = ManualScheduler()
        let controller = CopyFeedbackController(presenter: presenter, scheduler: scheduler)

        controller.showFeedback()
        controller.stop()
        scheduler.fireScheduled()

        XCTAssertEqual(presenter.hideCount, 1)
    }
}

@MainActor
private final class FakePasteboard: PasteboardChangeCounting {
    var changeCount: Int

    init(changeCount: Int) {
        self.changeCount = changeCount
    }
}

@MainActor
private final class RecordingFeedbackPresenter: CopyFeedbackPresenting {
    private(set) var showCount = 0
    private(set) var hideCount = 0

    func show() {
        showCount += 1
    }

    func hide() {
        hideCount += 1
    }
}

@MainActor
private final class ManualScheduler: Scheduling {
    private struct ScheduledAction {
        let cancellation: ManualCancellation
        let action: @MainActor () -> Void
    }

    private var repeatingAction: ScheduledAction?
    private var scheduledActions: [ScheduledAction] = []

    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation {
        let scheduledAction = ScheduledAction(
            cancellation: ManualCancellation(),
            action: action
        )
        repeatingAction = scheduledAction
        return scheduledAction.cancellation
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation {
        let scheduledAction = ScheduledAction(
            cancellation: ManualCancellation(),
            action: action
        )
        scheduledActions.append(scheduledAction)
        return scheduledAction.cancellation
    }

    func fireRepeating() {
        guard let repeatingAction, !repeatingAction.cancellation.isCancelled else {
            return
        }
        repeatingAction.action()
    }

    func fireScheduled() {
        let actions = scheduledActions
        scheduledActions.removeAll()

        for action in actions where !action.cancellation.isCancelled {
            action.action()
        }
    }
}

@MainActor
private final class ManualCancellation: Cancellation {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}
