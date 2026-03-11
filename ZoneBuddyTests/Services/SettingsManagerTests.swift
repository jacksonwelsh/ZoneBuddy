import Testing
import Foundation
@testable import ZoneBuddy

struct SettingsManagerTests {
    @Test func defaultValues() {
        let settings = SettingsManager.shared
        // We can't easily test NSUbiquitousKeyValueStore in unit tests without mocking,
        // but we can at least check if the shared instance exists and has reasonable defaults.
        #expect(settings.transitionWarningDuration >= 3)
        #expect(settings.transitionWarningDuration <= 30)
    }

    @Test func ftpDefaultValue() {
        let settings = SettingsManager.shared
        #expect(settings.functionalThresholdPower >= 50)
        #expect(settings.functionalThresholdPower <= 500)
    }

    @Test func layoutPreferencesDefaultAllVisible() {
        let prefs = WorkoutLayoutPreferences()
        #expect(prefs.showPower == true)
        #expect(prefs.showCadence == true)
        #expect(prefs.showHeartRate == true)
        #expect(prefs.showSpeed == true)
        #expect(prefs.showDistance == true)
        #expect(prefs.showCalories == true)
        #expect(prefs.showAvgPower == true)
        #expect(prefs.showZoneInfo == true)
        #expect(prefs.showPowerBar == true)
        #expect(prefs.showMusicControls == true)
    }

    @Test func layoutPreferencesEncodeDecode() throws {
        var prefs = WorkoutLayoutPreferences()
        prefs.showPower = false
        prefs.showSpeed = false
        prefs.showMusicControls = false

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(WorkoutLayoutPreferences.self, from: data)

        #expect(decoded == prefs)
        #expect(decoded.showPower == false)
        #expect(decoded.showCadence == true)
        #expect(decoded.showSpeed == false)
        #expect(decoded.showMusicControls == false)
    }
}
