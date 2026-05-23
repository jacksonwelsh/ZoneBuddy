import Foundation
import CoreLocation
@testable import ZoneBuddy

final class MockHealthKitWorkoutRecorder: HealthKitWorkoutRecording {
    var liveCalories: Double? = nil
    private(set) var endWorkoutCount = 0
    private(set) var lastWatchEnergyEstimateKcal: Double?
    private(set) var lastMetadata: [String: Any] = [:]
    private(set) var didBeginRouteRecording = false
    private(set) var addedRouteLocations: [CLLocation] = []

    func requestAuthorization() async -> Bool { true }
    func startWorkout(startDate: Date) async -> Bool { true }
    func addSamples(_ samples: [BikeDataSample]) async {}
    func addHeartRateSamples(_ samples: [(bpm: Int, date: Date)]) async {}
    func endWorkout(endDate: Date, watchEnergyEstimateKcal: Double?, metadata: [String: Any]) async {
        endWorkoutCount += 1
        lastWatchEnergyEstimateKcal = watchEnergyEstimateKcal
        lastMetadata = metadata
    }
    func pauseWorkout() {}
    func resumeWorkout() {}

    func beginRouteRecording() async { didBeginRouteRecording = true }
    func addRouteLocations(_ locations: [CLLocation]) async {
        addedRouteLocations.append(contentsOf: locations)
    }
}
