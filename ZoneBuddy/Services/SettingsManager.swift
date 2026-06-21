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

    /// Rider mass in kg. Synced via iCloud key-value store so the value
    /// matches across the user's iPhone + iPad.
    var riderWeightKg: Double {
        didSet {
            store.set(riderWeightKg, forKey: Keys.riderWeightKg)
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

    /// Set to true the first time we observe a connected trainer that advertises
    /// FTMS Indoor Bike Simulation support. Used to gate Route Ride UI — the
    /// mode is hidden entirely until the user has owned a capable trainer at
    /// least once. Sticky: never reset to false, since "previously owned a
    /// capable trainer" is the contract.
    var hasConnectedSimCapableTrainer: Bool {
        didSet {
            store.set(hasConnectedSimCapableTrainer, forKey: Keys.hasConnectedSimCapableTrainer)
            store.synchronize()
        }
    }

    /// When true, completed rides upload to Strava automatically. Off by
    /// default — a connected user must opt in; otherwise every ride is uploaded
    /// manually from the history detail screen.
    var stravaAutoUpload: Bool {
        didSet {
            store.set(stravaAutoUpload, forKey: Keys.stravaAutoUpload)
            store.synchronize()
        }
    }

    /// Whether auto-upload also covers FTP tests. Off by default — most riders
    /// don't want a test on their Strava feed. Manual upload of a test is still
    /// available regardless.
    var stravaAutoUploadIncludesFTPTests: Bool {
        didSet {
            store.set(stravaAutoUploadIncludesFTPTests, forKey: Keys.stravaAutoUploadIncludesFTPTests)
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
        static let riderWeightKg = "riderWeightKg"
        static let layoutPreferences = "layoutPreferences"
        static let lastConnectedBikeID = "lastConnectedBikeID"
        static let lastConnectedBikeName = "lastConnectedBikeName"
        static let promptForBikeBeforeWorkout = "promptForBikeBeforeWorkout"
        static let hasConnectedSimCapableTrainer = "hasConnectedSimCapableTrainer"
        static let stravaAutoUpload = "stravaAutoUpload"
        static let stravaAutoUploadIncludesFTPTests = "stravaAutoUploadIncludesFTPTests"
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

        let savedWeight = store.double(forKey: Keys.riderWeightKg)
        self.riderWeightKg = savedWeight == 0 ? 75 : savedWeight

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

        self.hasConnectedSimCapableTrainer = store.bool(forKey: Keys.hasConnectedSimCapableTrainer)

        self.stravaAutoUpload = store.bool(forKey: Keys.stravaAutoUpload)
        self.stravaAutoUploadIncludesFTPTests = store.bool(forKey: Keys.stravaAutoUploadIncludesFTPTests)

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

        let savedWeight = store.double(forKey: Keys.riderWeightKg)
        if savedWeight > 0 {
            riderWeightKg = savedWeight
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

        // Sticky: only adopt the cloud value if it would *upgrade* the local
        // flag to true. A device that hasn't yet seen its trainer's caps
        // shouldn't downgrade another device that has.
        if store.bool(forKey: Keys.hasConnectedSimCapableTrainer) {
            hasConnectedSimCapableTrainer = true
        }

        if store.object(forKey: Keys.stravaAutoUpload) != nil {
            stravaAutoUpload = store.bool(forKey: Keys.stravaAutoUpload)
        }
        if store.object(forKey: Keys.stravaAutoUploadIncludesFTPTests) != nil {
            stravaAutoUploadIncludesFTPTests = store.bool(forKey: Keys.stravaAutoUploadIncludesFTPTests)
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
