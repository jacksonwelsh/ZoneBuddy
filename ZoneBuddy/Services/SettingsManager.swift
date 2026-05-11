import Foundation
import SwiftUI
import Combine

struct WorkoutLayoutPreferences: Codable, Equatable {
    var showPower: Bool = true
    var showCadence: Bool = true
    var showHeartRate: Bool = true
    var showSpeed: Bool = true
    var showDistance: Bool = true
    var showCalories: Bool = true
    var showAvgPower: Bool = true
    var showOutput: Bool = true
    var showZoneInfo: Bool = true
    var showPowerBar: Bool = true
    var showMusicControls: Bool = true
    var showHeartRateBar: Bool = false // off by default on iPhone, shown on iPad
}

@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    private let store = NSUbiquitousKeyValueStore.default

    var transitionWarningDuration: Int {
        didSet {
            store.set(Int64(transitionWarningDuration), forKey: Keys.transitionWarningDuration)
            store.synchronize()
        }
    }

    var audioCuesEnabled: Bool {
        didSet {
            store.set(audioCuesEnabled, forKey: Keys.audioCuesEnabled)
            store.synchronize()
        }
    }

    var playlistTakesOverMusic: Bool {
        didSet {
            store.set(playlistTakesOverMusic, forKey: Keys.playlistTakesOverMusic)
            store.synchronize()
        }
    }

    var functionalThresholdPower: Int {
        didSet {
            store.set(Int64(functionalThresholdPower), forKey: Keys.functionalThresholdPower)
            store.synchronize()
        }
    }

    var maxHeartRate: Int {
        didSet {
            store.set(Int64(maxHeartRate), forKey: Keys.maxHeartRate)
            store.synchronize()
        }
    }

    var layoutPreferences: WorkoutLayoutPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(layoutPreferences) {
                store.set(data, forKey: Keys.layoutPreferences)
                store.synchronize()
            }
        }
    }

    /// UUID string of the last connected bike's CBPeripheral, used for auto-reconnect.
    var lastConnectedBikeID: String? {
        didSet {
            if let id = lastConnectedBikeID {
                store.set(id, forKey: Keys.lastConnectedBikeID)
            } else {
                store.removeObject(forKey: Keys.lastConnectedBikeID)
            }
            store.synchronize()
        }
    }

    /// Display name of the last connected bike, shown in UI.
    var lastConnectedBikeName: String? {
        didSet {
            if let name = lastConnectedBikeName {
                store.set(name, forKey: Keys.lastConnectedBikeName)
            } else {
                store.removeObject(forKey: Keys.lastConnectedBikeName)
            }
            store.synchronize()
        }
    }

    /// When true, show a bike connection sheet before each workout if not already connected.
    var promptForBikeBeforeWorkout: Bool {
        didSet {
            store.set(promptForBikeBeforeWorkout, forKey: Keys.promptForBikeBeforeWorkout)
            store.synchronize()
        }
    }

    /// True once the user has completed the first-launch onboarding flow.
    /// Backed by local `UserDefaults` (not iCloud) so a fresh install replays onboarding —
    /// permissions like Bluetooth need to be re-requested after reinstall anyway.
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    private enum Keys {
        static let transitionWarningDuration = "transitionWarningDuration"
        static let audioCuesEnabled = "audioCuesEnabled"
        static let playlistTakesOverMusic = "playlistTakesOverMusic"
        static let functionalThresholdPower = "functionalThresholdPower"
        static let maxHeartRate = "maxHeartRate"
        static let layoutPreferences = "layoutPreferences"
        static let lastConnectedBikeID = "lastConnectedBikeID"
        static let lastConnectedBikeName = "lastConnectedBikeName"
        static let promptForBikeBeforeWorkout = "promptForBikeBeforeWorkout"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        /// UserDefaults.standard key written by the iOS Settings.app toggle (Settings.bundle).
        /// Read on launch + foreground; if true, we clear `hasCompletedOnboarding` and reset this back to false.
        static let rerunOnboarding = "rerun_onboarding"
    }

    private init() {
        // Initialize from store
        let savedDuration = Int(store.longLong(forKey: Keys.transitionWarningDuration))
        self.transitionWarningDuration = savedDuration == 0 ? 10 : savedDuration

        if store.object(forKey: Keys.audioCuesEnabled) == nil {
            self.audioCuesEnabled = true
        } else {
            self.audioCuesEnabled = store.bool(forKey: Keys.audioCuesEnabled)
        }

        if store.object(forKey: Keys.playlistTakesOverMusic) == nil {
            self.playlistTakesOverMusic = true
        } else {
            self.playlistTakesOverMusic = store.bool(forKey: Keys.playlistTakesOverMusic)
        }

        let savedFTP = Int(store.longLong(forKey: Keys.functionalThresholdPower))
        self.functionalThresholdPower = savedFTP == 0 ? 200 : savedFTP

        let savedMaxHR = Int(store.longLong(forKey: Keys.maxHeartRate))
        self.maxHeartRate = savedMaxHR == 0 ? 190 : savedMaxHR

        if let layoutData = store.data(forKey: Keys.layoutPreferences),
           let prefs = try? JSONDecoder().decode(WorkoutLayoutPreferences.self, from: layoutData) {
            self.layoutPreferences = prefs
        } else {
            self.layoutPreferences = WorkoutLayoutPreferences()
        }

        self.lastConnectedBikeID = store.string(forKey: Keys.lastConnectedBikeID)
        self.lastConnectedBikeName = store.string(forKey: Keys.lastConnectedBikeName)

        if store.object(forKey: Keys.promptForBikeBeforeWorkout) == nil {
            self.promptForBikeBeforeWorkout = false
        } else {
            self.promptForBikeBeforeWorkout = store.bool(forKey: Keys.promptForBikeBeforeWorkout)
        }

        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFromCloud()
        }
    }

    private func refreshFromCloud() {
        let savedDuration = Int(store.longLong(forKey: Keys.transitionWarningDuration))
        transitionWarningDuration = savedDuration == 0 ? 10 : savedDuration

        if store.object(forKey: Keys.audioCuesEnabled) != nil {
            audioCuesEnabled = store.bool(forKey: Keys.audioCuesEnabled)
        }

        if store.object(forKey: Keys.playlistTakesOverMusic) != nil {
            playlistTakesOverMusic = store.bool(forKey: Keys.playlistTakesOverMusic)
        }

        let savedFTP = Int(store.longLong(forKey: Keys.functionalThresholdPower))
        if savedFTP > 0 {
            functionalThresholdPower = savedFTP
        }

        let savedMaxHR = Int(store.longLong(forKey: Keys.maxHeartRate))
        if savedMaxHR > 0 {
            maxHeartRate = savedMaxHR
        }

        if let layoutData = store.data(forKey: Keys.layoutPreferences),
           let prefs = try? JSONDecoder().decode(WorkoutLayoutPreferences.self, from: layoutData) {
            layoutPreferences = prefs
        }

        lastConnectedBikeID = store.string(forKey: Keys.lastConnectedBikeID)
        lastConnectedBikeName = store.string(forKey: Keys.lastConnectedBikeName)

        if store.object(forKey: Keys.promptForBikeBeforeWorkout) != nil {
            promptForBikeBeforeWorkout = store.bool(forKey: Keys.promptForBikeBeforeWorkout)
        }
    }

    /// Reads the `rerun_onboarding` toggle written by the iOS Settings.app (via Settings.bundle).
    /// If set, clears `hasCompletedOnboarding` so the next launch replays onboarding, then resets
    /// the toggle back to false so it's a one-shot. Call on app launch and on foreground.
    func consumeRerunFlagIfSet() {
        UserDefaults.standard.register(defaults: [Keys.rerunOnboarding: false])
        if UserDefaults.standard.bool(forKey: Keys.rerunOnboarding) {
            hasCompletedOnboarding = false
            UserDefaults.standard.set(false, forKey: Keys.rerunOnboarding)
        }
    }
}
