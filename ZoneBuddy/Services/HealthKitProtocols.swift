import Foundation

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
}

/// Protocol for streaming heart rate from HealthKit (Apple Watch, AirPods Pro, etc.)
protocol HeartRateStreaming {
    var latestHeartRate: Int? { get }
    func startMonitoring(from startDate: Date)
    func stopMonitoring()
}
