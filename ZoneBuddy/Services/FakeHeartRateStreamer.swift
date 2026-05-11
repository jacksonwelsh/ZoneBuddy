#if DEBUG
import Foundation
import FTMSKit

/// Debug-only fake HR streamer used in place of `WatchHeartRateRelay` /
/// `BLEHeartRateScanner` when `SimulatorFakes` is enabled. Emits HR at 1Hz
/// either from `SimulatorFakes.shared.hrOverride` or derived from the fake
/// bike's smoothed power (`power × 0.6 + 80`).
@Observable
final class FakeHeartRateStreamer: HeartRateStreaming {
    private(set) var latestHeartRate: Int? = nil

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var smoothed: Double = 90

    func startMonitoring(from startDate: Date) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self?.tick()
            }
        }
    }

    func stopMonitoring() {
        task?.cancel()
        task = nil
        latestHeartRate = nil
    }

    private func tick() {
        let target: Double
        if let override = SimulatorFakes.shared.hrOverride {
            target = Double(override)
        } else {
            let p = Double(FakeBikeConnectionManager.shared.latestBikeData?.instantaneousPower ?? 100)
            target = p * 0.6 + 80
        }
        smoothed += (target - smoothed) * 0.18 + Double.random(in: -1...1)
        smoothed = min(200, max(50, smoothed))
        latestHeartRate = Int(smoothed)
    }
}
#endif
