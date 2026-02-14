import Foundation
@testable import ZoneBuddy

final class MockTimerProvider: TimerProviding, @unchecked Sendable {
    private var handler: (@MainActor @Sendable () -> Void)?
    private(set) var timerStarted = false

    func scheduledTimer(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> TimerCancellable {
        self.handler = handler
        self.timerStarted = true
        return MockTimerCancellable { self.handler = nil }
    }

    @MainActor
    func fire(times count: Int = 1) {
        for _ in 0..<count {
            handler?()
        }
    }
}

final class MockTimerCancellable: TimerCancellable, @unchecked Sendable {
    private let onCancel: () -> Void
    private(set) var wasCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        wasCancelled = true
        onCancel()
    }
}
