import Foundation
import CoreLocation

protocol HealthKitWorkoutRecording {
    /// Live calories from the workout builder (e.g. Watch's HKLiveWorkoutBuilder).
    /// Returns nil when not available (e.g. iOS HKWorkoutBuilder without Watch).
    var liveCalories: Double? { get }

    func requestAuthorization() async -> Bool
    func startWorkout(startDate: Date) async -> Bool
    func addSamples(_ samples: [BikeDataSample]) async
    func addHeartRateSamples(_ samples: [(bpm: Int, date: Date)]) async
    /// `watchEnergyEstimateKcal` is the Watch's cumulative HR-based active-energy
    /// estimate (passed in from the BLE-cached value). When provided and greater
    /// than the recorder's own power-based active kcal, the iOS recorder writes
    /// a `.basalEnergyBurned` summary sample for the delta so Fitness's "Total
    /// Calories" reflects the Watch's HR-based estimate.
    func endWorkout(endDate: Date, watchEnergyEstimateKcal: Double?, metadata: [String: Any]) async
    func pauseWorkout()
    func resumeWorkout()

    /// Begin recording an HKWorkoutRoute alongside the current workout. Called
    /// only for Route mode rides on iOS — Watch and free-ride / structured
    /// workouts implement this as a no-op.
    func beginRouteRecording() async
    /// Append a batch of synthesized CLLocation samples to the in-progress
    /// HKWorkoutRoute. No-op if `beginRouteRecording()` wasn't called.
    func addRouteLocations(_ locations: [CLLocation]) async
}

/// Protocol for streaming heart rate from HealthKit (Apple Watch, AirPods Pro, etc.)
protocol HeartRateStreaming {
    var latestHeartRate: Int? { get }
    func startMonitoring(from startDate: Date)
    func stopMonitoring()
}
