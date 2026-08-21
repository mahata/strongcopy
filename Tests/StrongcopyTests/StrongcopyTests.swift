import XCTest
import ServiceManagement
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

final class CopyHUDPlacementTests: XCTestCase {
    private let panelSize = NSSize(width: 132, height: 52)
    private let pointerOffset = NSSize(width: 12, height: 12)
    private let visibleFrame = NSRect(x: 100, y: 200, width: 400, height: 300)

    func testPositionsPanelAboveAndToTheRightOfPointer() {
        let origin = CopyHUDPlacement.panelOrigin(
            pointerLocation: NSPoint(x: 250, y: 350),
            visibleFrame: visibleFrame,
            panelSize: panelSize,
            pointerOffset: pointerOffset
        )

        XCTAssertEqual(origin, NSPoint(x: 262, y: 362))
    }

    func testClampsPanelToTopAndRightEdges() {
        let origin = CopyHUDPlacement.panelOrigin(
            pointerLocation: NSPoint(x: 490, y: 490),
            visibleFrame: visibleFrame,
            panelSize: panelSize,
            pointerOffset: pointerOffset
        )

        XCTAssertEqual(origin, NSPoint(x: 368, y: 448))
    }

    func testClampsPanelToBottomAndLeftEdges() {
        let origin = CopyHUDPlacement.panelOrigin(
            pointerLocation: NSPoint(x: 80, y: 150),
            visibleFrame: visibleFrame,
            panelSize: panelSize,
            pointerOffset: pointerOffset
        )

        XCTAssertEqual(origin, NSPoint(x: 100, y: 200))
    }
}

final class AboutInfoTests: XCTestCase {
    func testFormatsNameAndVersion() {
        XCTAssertEqual(
            AboutInfo.displayText(name: "Strongcopy", version: "1.2.3"),
            "Strongcopy 1.2.3"
        )
    }

    func testFallsBackToDevWhenVersionMissing() {
        XCTAssertEqual(
            AboutInfo.displayText(name: "Strongcopy", version: nil),
            "Strongcopy (dev)"
        )
    }

    func testFallsBackToDevWhenVersionBlank() {
        XCTAssertEqual(
            AboutInfo.displayText(name: "Strongcopy", version: "  "),
            "Strongcopy (dev)"
        )
    }

    func testFallsBackToDefaultNameWhenNameMissing() {
        XCTAssertEqual(
            AboutInfo.displayText(name: nil, version: "1.0.0"),
            "Strongcopy 1.0.0"
        )
    }

    func testTrimsWhitespaceAroundNameAndVersion() {
        XCTAssertEqual(
            AboutInfo.displayText(name: "  Strongcopy  ", version: "  2.0  "),
            "Strongcopy 2.0"
        )
    }
}

final class StatusMenuItemTests: XCTestCase {
    func testMenuItemOrderAndTitles() {
        XCTAssertEqual(
            StatusMenuItem.allCases.map(\.title),
            ["About Strongcopy", "Open at Login", "Quit Strongcopy"]
        )
    }
}

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testTogglingDisabledItemRegistersAndReportsEnabled() {
        let loginItem = FakeLoginItem(state: .disabled, stateAfterRegister: .enabled)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(controller.toggle(), .enabled)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(loginItem.unregisterCount, 0)
    }

    func testTogglingEnabledItemUnregistersAndReportsDisabled() {
        let loginItem = FakeLoginItem(state: .enabled, stateAfterUnregister: .disabled)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(controller.toggle(), .disabled)
        XCTAssertEqual(loginItem.unregisterCount, 1)
        XCTAssertEqual(loginItem.registerCount, 0)
    }

    func testSilentRegistrationFailureReportsActualStateInsteadOfEnabled() {
        let loginItem = FakeLoginItem(state: .disabled, stateAfterRegister: .disabled)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(controller.toggle(), .disabled)
        XCTAssertEqual(loginItem.registerCount, 1)
    }

    func testSilentUnregistrationFailureReportsActualStateInsteadOfDisabled() {
        let loginItem = FakeLoginItem(state: .enabled, stateAfterUnregister: .enabled)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(controller.toggle(), .enabled)
        XCTAssertEqual(loginItem.unregisterCount, 1)
    }

    func testRegistrationLeftAwaitingApprovalReportsRequiresApproval() {
        let loginItem = FakeLoginItem(state: .disabled, stateAfterRegister: .requiresApproval)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(controller.toggle(), .requiresApproval)
    }

    func testTogglingItemAwaitingApprovalPerformsNoRegistrationCalls() {
        let loginItem = FakeLoginItem(state: .requiresApproval)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(controller.toggle(), .requiresApproval)
        XCTAssertEqual(loginItem.registerCount, 0)
        XCTAssertEqual(loginItem.unregisterCount, 0)
    }

    func testTogglingUnavailableItemPerformsNoRegistrationCalls() {
        let loginItem = FakeLoginItem(state: .unavailable)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(controller.toggle(), .unavailable)
        XCTAssertEqual(loginItem.registerCount, 0)
        XCTAssertEqual(loginItem.unregisterCount, 0)
    }

    func testRegistrationErrorIsReportedAsFailure() {
        let loginItem = FakeLoginItem(state: .disabled)
        loginItem.registerError = FakeLoginItemError.denied
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(
            controller.toggle(),
            .failed(FakeLoginItemError.denied.localizedDescription)
        )
    }

    func testUnregistrationErrorIsReportedAsFailure() {
        let loginItem = FakeLoginItem(state: .enabled)
        loginItem.unregisterError = FakeLoginItemError.denied
        let controller = LaunchAtLoginController(loginItem: loginItem)

        XCTAssertEqual(
            controller.toggle(),
            .failed(FakeLoginItemError.denied.localizedDescription)
        )
    }

    func testOpenSystemSettingsForwardsToLoginItem() {
        let loginItem = FakeLoginItem(state: .requiresApproval)
        let controller = LaunchAtLoginController(loginItem: loginItem)

        controller.openSystemSettings()

        XCTAssertEqual(loginItem.openSystemSettingsCount, 1)
    }
}

final class LaunchAtLoginStateTests: XCTestCase {
    func testMapsServiceStatusToState() {
        XCTAssertEqual(LaunchAtLoginState(status: .enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginState(status: .notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginState(status: .requiresApproval), .requiresApproval)
    }

    func testNeverRegisteredItemIsDisabledRatherThanUnavailable() {
        XCTAssertEqual(LaunchAtLoginState(status: .notFound), .disabled)
    }
}

final class LaunchAtLoginAvailabilityTests: XCTestCase {
    func testInstalledAppBundleIsSupported() {
        XCTAssertTrue(
            LaunchAtLoginAvailability.isSupported(
                bundleURL: URL(fileURLWithPath: "/Applications/Strongcopy.app")
            )
        )
    }

    func testBareExecutableDirectoryIsNotSupported() {
        XCTAssertFalse(
            LaunchAtLoginAvailability.isSupported(
                bundleURL: URL(fileURLWithPath: "/Users/example/strongcopy/.build/debug")
            )
        )
    }
}

final class LaunchAtLoginMenuPresentationTests: XCTestCase {
    func testEnabledStateShowsCheckmark() {
        let appearance = LaunchAtLoginMenuPresentation.appearance(for: .enabled)

        XCTAssertEqual(appearance.state, .on)
        XCTAssertTrue(appearance.isEnabled)
        XCTAssertNil(appearance.toolTip)
    }

    func testDisabledStateShowsNoCheckmark() {
        let appearance = LaunchAtLoginMenuPresentation.appearance(for: .disabled)

        XCTAssertEqual(appearance.state, .off)
        XCTAssertTrue(appearance.isEnabled)
        XCTAssertNil(appearance.toolTip)
    }

    func testRequiresApprovalStateShowsMixedCheckmark() {
        let appearance = LaunchAtLoginMenuPresentation.appearance(for: .requiresApproval)

        XCTAssertEqual(appearance.state, .mixed)
        XCTAssertTrue(appearance.isEnabled)
    }

    func testUnavailableStateIsDisabledWithExplanation() {
        let appearance = LaunchAtLoginMenuPresentation.appearance(for: .unavailable)

        XCTAssertEqual(appearance.state, .off)
        XCTAssertFalse(appearance.isEnabled)
        XCTAssertEqual(appearance.toolTip, LaunchAtLoginMenuPresentation.unavailableToolTip)
    }
}

private enum FakeLoginItemError: Error, LocalizedError {
    case denied

    var errorDescription: String? {
        "Operation not permitted"
    }
}

@MainActor
private final class FakeLoginItem: LoginItemRegistering {
    private(set) var state: LaunchAtLoginState
    private let stateAfterRegister: LaunchAtLoginState?
    private let stateAfterUnregister: LaunchAtLoginState?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSystemSettingsCount = 0
    var registerError: Error?
    var unregisterError: Error?

    init(
        state: LaunchAtLoginState,
        stateAfterRegister: LaunchAtLoginState? = nil,
        stateAfterUnregister: LaunchAtLoginState? = nil
    ) {
        self.state = state
        self.stateAfterRegister = stateAfterRegister
        self.stateAfterUnregister = stateAfterUnregister
    }

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        if let stateAfterRegister {
            state = stateAfterRegister
        }
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError {
            throw unregisterError
        }
        if let stateAfterUnregister {
            state = stateAfterUnregister
        }
    }

    func openSystemSettings() {
        openSystemSettingsCount += 1
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
