#if DEBUG
import Foundation

/// Debug-only `HealthKitWorkoutRecording` that does nothing. Selected by
/// `HealthKitWorkoutProvider` when fakes are enabled and `preventHealthKitWrite`
/// is true. Avoids HealthKit auth prompts and stops fake data from landing in
/// the user's Health database.
final class NoOpHealthKitWorkoutManager: HealthKitWorkoutRecording {
    var liveCalories: Double? { nil }

    func requestAuthorization() async -> Bool { true }
    func startWorkout(startDate: Date) async -> Bool { true }
    func addSamples(_ samples: [BikeDataSample]) async {}
    func addHeartRateSamples(_ samples: [(bpm: Int, date: Date)]) async {}
    func endWorkout(endDate: Date, watchEnergyEstimateKcal: Double?, metadata: [String: Any]) async {}
    func pauseWorkout() {}
    func resumeWorkout() {}
}
#endif
