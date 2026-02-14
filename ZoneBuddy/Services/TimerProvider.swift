import Foundation

protocol TimerCancellable: Sendable {
    func cancel()
}

protocol TimerProviding: Sendable {
    func scheduledTimer(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> TimerCancellable
}

final class LiveTimerProvider: TimerProviding, Sendable {
    func scheduledTimer(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> TimerCancellable {
        let wrapper = RunLoopTimerCancellable(interval: interval, handler: handler)
        wrapper.start()
        return wrapper
    }
}

final class RunLoopTimerCancellable: TimerCancellable, @unchecked Sendable {
    private var timer: Timer?
    private let interval: TimeInterval
    private let handler: @MainActor @Sendable () -> Void

    init(interval: TimeInterval, handler: @escaping @MainActor @Sendable () -> Void) {
        self.interval = interval
        self.handler = handler
    }

    func start() {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [handler] _ in
            Task { @MainActor in
                handler()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
