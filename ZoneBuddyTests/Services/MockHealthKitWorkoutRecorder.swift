import Foundation
@testable import ZoneBuddy

final class MockHealthKitWorkoutRecorder: HealthKitWorkoutRecording {
    var liveCalories: Double? = nil
    private(set) var endWorkoutCount = 0

    func requestAuthorization() async -> Bool { true }
    func startWorkout(startDate: Date) async -> Bool { true }
    func addSamples(_ samples: [BikeDataSample]) async {}
    func addHeartRateSamples(_ samples: [(bpm: Int, date: Date)]) async {}
    func endWorkout(endDate: Date, metadata: [String: Any]) async {
        endWorkoutCount += 1
    }
    func pauseWorkout() {}
    func resumeWorkout() {}
}
