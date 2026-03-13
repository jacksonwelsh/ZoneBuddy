import Foundation

protocol HealthKitWorkoutRecording {
    /// Live calories from the workout builder (e.g. Watch's HKLiveWorkoutBuilder).
    /// Returns nil when not available (e.g. iOS HKWorkoutBuilder without Watch).
    var liveCalories: Double? { get }

    func requestAuthorization() async -> Bool
    func startWorkout(startDate: Date) async -> Bool
    func addSamples(_ samples: [BikeDataSample]) async
    func endWorkout(endDate: Date, metadata: [String: Any]) async
}

/// Protocol for streaming heart rate from HealthKit (Apple Watch, AirPods Pro, etc.)
protocol HeartRateStreaming {
    var latestHeartRate: Int? { get }
    func startMonitoring(from startDate: Date)
    func stopMonitoring()
}
