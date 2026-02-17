import Foundation

protocol TimerProviding: Sendable {
    func ticks(every interval: Duration) -> any AsyncSequence<Date, Never>
}

final class LiveTimerProvider: TimerProviding, Sendable {
    func ticks(every interval: Duration) -> any AsyncSequence<Date, Never> {
        let (stream, continuation) = AsyncStream.makeStream(of: Date.self)

        let seconds = Double(interval.components.seconds)
            + Double(interval.components.attoseconds) / 1e18

        // Use a GCD timer instead of ContinuousClock. GCD timers fire reliably
        // in the background (as long as the process is alive via audio mode),
        // without depending on the MainActor executor being responsive.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: seconds, leeway: .milliseconds(50))
        timer.setEventHandler {
            continuation.yield(Date())
        }
        timer.resume()

        continuation.onTermination = { _ in
            timer.cancel()
        }

        return stream
    }
}
