import Foundation
@testable import ZoneBuddy

final class MockTimerProvider: TimerProviding, @unchecked Sendable {
    private var continuation: AsyncStream<Date>.Continuation?
    private(set) var timerStarted = false

    func ticks(every interval: Duration) -> any AsyncSequence<Date, Never> {
        let (stream, continuation) = AsyncStream.makeStream(of: Date.self)
        self.continuation = continuation
        self.timerStarted = true
        return stream
    }

    @MainActor
    func fire(at date: Date = Date()) {
        continuation?.yield(date)
    }
    
    @MainActor
    func fire(after seconds: TimeInterval, from baseDate: Date = Date()) {
        continuation?.yield(baseDate.addingTimeInterval(seconds))
    }
}
