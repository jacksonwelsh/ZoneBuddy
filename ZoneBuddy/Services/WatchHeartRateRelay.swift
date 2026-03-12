import Foundation

@Observable
final class WatchHeartRateRelay: HeartRateStreaming {
    var latestHeartRate: Int? {
        WorkoutConnectivityManager.shared.latestWatchHeartRate
    }

    func startMonitoring(from startDate: Date) {}

    func stopMonitoring() {
        WorkoutConnectivityManager.shared.clearHeartRate()
    }
}
