import Foundation

@Observable
final class PeerHeartRateRelay: HeartRateStreaming {
    var latestHeartRate: Int? {
        HRRelayService.shared.latestRelayedHeartRate
    }

    func startMonitoring(from startDate: Date) {
        HRRelayService.shared.startBrowsing()
    }

    func stopMonitoring() {
        HRRelayService.shared.stopBrowsing()
    }
}
