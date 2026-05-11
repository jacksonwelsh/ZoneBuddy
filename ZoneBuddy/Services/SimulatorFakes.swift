#if DEBUG
import Foundation
import Observation

/// Debug-only controller for simulator-mode fakes. Singleton.
///
/// Activation: env var `ZB_SIMULATOR_FAKES=1` (set via the "(Sim Fakes)"
/// schemes) OR a runtime toggle persisted in `UserDefaults.standard`.
///
/// State here is read by `FakeBikeConnectionManager`, `FakeHeartRateStreamer`,
/// the Watch app entry, and `SimulatorDebugView` to drive the simulation.
@Observable
final class SimulatorFakes {
    static let shared = SimulatorFakes()

    /// True iff env var was set at launch OR runtime toggle is on.
    var isEnabled: Bool { envVarSet || userToggleEnabled }

    /// Persisted runtime toggle. UserDefaults.standard (NOT iCloud KV store).
    var userToggleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(userToggleEnabled, forKey: Self.userToggleKey)
        }
    }

    /// Slider-driven target power in watts (0...500). The fake bike's smoothed
    /// power follows this value.
    var targetPower: Int = 150

    /// When non-nil, the fake HR streamer uses this directly instead of
    /// deriving from `FakeBikeConnectionManager.shared.latestBikeData`.
    var hrOverride: Int? = nil

    /// Toggle to test the disconnected state without restarting the app.
    var bikeConnected: Bool = true

    /// When true, the iOS HealthKitWorkoutProvider returns the no-op manager
    /// so fake workouts don't prompt for permissions or pollute Health.
    var preventHealthKitWrite: Bool = true

    @ObservationIgnored let envVarSet: Bool

    private static let userToggleKey = "sim.fakes.userEnabled"

    private init() {
        envVarSet = ProcessInfo.processInfo.environment["ZB_SIMULATOR_FAKES"] == "1"
        userToggleEnabled = UserDefaults.standard.bool(forKey: Self.userToggleKey)
    }
}
#endif
