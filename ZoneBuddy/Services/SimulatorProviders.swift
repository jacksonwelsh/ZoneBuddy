import Foundation

/// Resolves the active `BikeConnecting`. In DEBUG with fakes enabled, returns
/// the singleton `FakeBikeConnectionManager` and avoids touching
/// `LiveBikeConnectionManager.shared` (which lazy-instantiates FTMSKit and
/// would otherwise trigger a Bluetooth permission prompt).
enum BikeManagerProvider {
    static var current: any BikeConnecting {
        #if DEBUG
        if SimulatorFakes.shared.isEnabled {
            return FakeBikeConnectionManager.shared
        }
        #endif
        return LiveBikeConnectionManager.shared
    }
}

/// Returns a fake HR streamer when fakes are enabled, otherwise nil — call
/// sites coalesce to their normal `WCSession.isSupported() ? ... : ...`
/// selection. Keeping the live-platform decision at the call site avoids
/// importing `WatchConnectivity` here.
enum HeartRateStreamerProvider {
    static func makeFakeIfEnabled() -> HeartRateStreaming? {
        #if DEBUG
        if SimulatorFakes.shared.isEnabled {
            return FakeHeartRateStreamer()
        }
        #endif
        return nil
    }
}

enum HealthKitWorkoutProvider {
    static func make() -> HealthKitWorkoutRecording {
        #if DEBUG
        if SimulatorFakes.shared.isEnabled && SimulatorFakes.shared.preventHealthKitWrite {
            return NoOpHealthKitWorkoutManager()
        }
        #endif
        return LiveHealthKitWorkoutManager()
    }
}
