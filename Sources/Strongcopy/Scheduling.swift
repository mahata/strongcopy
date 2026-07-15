import Foundation

@MainActor
protocol Cancellation: AnyObject {
    func cancel()
}

@MainActor
protocol Scheduling: AnyObject {
    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation
}

@MainActor
final class TimerScheduler: Scheduling {
    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation {
        makeTimer(interval: interval, repeats: true, action: action)
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation {
        makeTimer(interval: delay, repeats: false, action: action)
    }

    private func makeTimer(
        interval: TimeInterval,
        repeats: Bool,
        action: @escaping @MainActor () -> Void
    ) -> any Cancellation {
        let target = TimerTarget(action: action)
        let timer = Timer(
            timeInterval: interval,
            target: target,
            selector: #selector(TimerTarget.fire),
            userInfo: nil,
            repeats: repeats
        )
        let cancellation = TimerCancellation(timer: timer, target: target)

        RunLoop.main.add(timer, forMode: .common)
        return cancellation
    }
}

@MainActor
private final class TimerTarget: NSObject {
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc
    func fire() {
        action()
    }
}

@MainActor
private final class TimerCancellation: Cancellation {
    private var timer: Timer?
    private var target: TimerTarget?

    init(timer: Timer, target: TimerTarget) {
        self.timer = timer
        self.target = target
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        target = nil
    }
}
