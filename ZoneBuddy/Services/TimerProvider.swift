import Foundation

protocol TimerProviding: Sendable {
    func ticks(every interval: Duration) -> any AsyncSequence<Date, Never>
}

final class LiveTimerProvider: TimerProviding, Sendable {
    func ticks(every interval: Duration) -> any AsyncSequence<Date, Never> {
        let (stream, continuation) = AsyncStream.makeStream(of: Date.self)
        
        let task = Task {
            var nextTick = ContinuousClock.now
            
            while !Task.isCancelled {
                continuation.yield(Date())
                nextTick += interval
                
                do {
                    try await Task.sleep(until: nextTick, clock: .continuous)
                } catch {
                    break
                }
            }
            continuation.finish()
        }
        
        continuation.onTermination = { _ in
            task.cancel()
        }
        
        return stream
    }
}
