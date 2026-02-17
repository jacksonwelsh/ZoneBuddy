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
}
