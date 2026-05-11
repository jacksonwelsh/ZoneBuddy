#if DEBUG
import Foundation

/// Watch-side fake that conforms to both `HealthKitWorkoutRecording` and
/// `HeartRateStreaming` (matching the dual surface of `WatchHealthKitManager`).
/// Generates a smoothed HR following `SimulatorFakes.shared.targetPower` so
/// the Watch player UI can be exercised without HealthKit data on the
/// simulator. All HK writes are no-ops.
@Observable
final class FakeWatchHealthKitManager: HealthKitWorkoutRecording, HeartRateStreaming {
    private(set) var latestHeartRate: Int? = nil
    var liveCalories: Double? = nil

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var smoothed: Double = 90

    func requestAuthorization() async -> Bool { true }
    func startWorkout(startDate: Date) async -> Bool { true }
    func addSamples(_ samples: [BikeDataSample]) async {}
    func addHeartRateSamples(_ samples: [(bpm: Int, date: Date)]) async {}
    func endWorkout(endDate: Date, metadata: [String: Any]) async {
        stopMonitoring()
    }
    func pauseWorkout() {}
    func resumeWorkout() {}

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
            target = Double(SimulatorFakes.shared.targetPower) * 0.6 + 80
        }
        smoothed += (target - smoothed) * 0.18 + Double.random(in: -1...1)
        smoothed = min(200, max(50, smoothed))
        latestHeartRate = Int(smoothed)
        liveCalories = (liveCalories ?? 0) + smoothed * 0.001
    }
}
#endif
