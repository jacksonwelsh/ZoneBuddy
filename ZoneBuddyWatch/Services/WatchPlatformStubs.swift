import Foundation

// Stubs for iOS-only types that WorkoutPlayerViewModel references.
// On watchOS these features are unused — the VM gracefully handles nil optionals.

struct BikeData {
    let instantaneousPower: Int?
    let heartRate: Int?
}

protocol BikeConnecting: Observable {
    var isConnected: Bool { get }
    var connectedBikeName: String? { get }
    var latestBikeData: BikeData? { get }
    var accumulatedSamples: [BikeDataSample] { get }
    func drainSamples() -> [BikeDataSample]
}

protocol MusicPlaybackManaging {
    func startPlayback(playlistID: String, kind: String?, shuffle: Bool, repeatMode: Bool, autoMix: Bool) async
    func pausePlayback()
    func resumePlayback()
    func stopPlayback()
}
