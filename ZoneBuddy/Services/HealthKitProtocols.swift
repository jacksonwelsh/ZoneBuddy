import Foundation

protocol HealthKitWorkoutRecording {
    func requestAuthorization() async -> Bool
    func startWorkout(startDate: Date) async -> Bool
    func addSamples(_ samples: [BikeDataSample]) async
    func endWorkout(endDate: Date) async
}

/// Protocol for streaming heart rate from HealthKit (Apple Watch, AirPods Pro, etc.)
protocol HeartRateStreaming {
    var latestHeartRate: Int? { get }
    func startMonitoring(from startDate: Date)
    func stopMonitoring()
}
