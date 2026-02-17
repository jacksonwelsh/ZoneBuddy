import Testing
import Foundation
import SwiftData
@testable import ZoneBuddy

@Suite("WorkoutCoder")
struct WorkoutCoderTests {
    private func makeContainer() -> ModelContainer {
        try! ModelContainer(
            for: Workout.self, Interval.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test @MainActor func encodeProducesValidURL() throws {
        let container = makeContainer()
        let workout = Workout(name: "Test", intervals: [
            Interval(zone: .zone2, duration: 300, sortOrder: 0),
            Interval(zone: nil, duration: 60, sortOrder: 1),
        ])
        container.mainContext.insert(workout)

        let url = try WorkoutCoder.encode(workout)
        #expect(url.scheme == "https")
        #expect(url.host() == "zonebuddy.jacksn.dev")
        #expect(url.pathComponents[1] == "workout")
        let payload = url.pathComponents[2]
        #expect(payload.hasPrefix("A"))
    }

    @Test @MainActor func roundTripPreservesData() throws {
        let container = makeContainer()
        let workout = Workout(name: "PZ Endurance", intervals: [
            Interval(zone: nil, duration: 300, sortOrder: 0),
            Interval(zone: .zone2, duration: 300, sortOrder: 1),
            Interval(zone: .zone5, duration: 120, sortOrder: 2),
        ], transitionWarningDuration: 15)
        container.mainContext.insert(workout)

        let url = try WorkoutCoder.encode(workout)
        let decoded = try WorkoutCoder.decode(url)

        #expect(decoded.name == "PZ Endurance")
        #expect(decoded.transitionWarningDuration == 15)
        #expect(decoded.intervals.count == 3)
        #expect(decoded.intervals[0].zone == nil)
        #expect(decoded.intervals[0].duration == 300)
        #expect(decoded.intervals[1].zone == 2)
        #expect(decoded.intervals[1].duration == 300)
        #expect(decoded.intervals[2].zone == 5)
        #expect(decoded.intervals[2].duration == 120)
    }

    @Test func decodeRejectsUnknownHost() {
        let url = URL(string: "https://evil.com/workout/Apayload")!
        #expect(throws: WorkoutCoderError.invalidURL) {
            try WorkoutCoder.decode(url)
        }
    }

    @Test func decodeRejectsWrongPath() {
        let url = URL(string: "https://zonebuddy.jacksn.dev/settings/Apayload")!
        #expect(throws: WorkoutCoderError.invalidPath) {
            try WorkoutCoder.decode(url)
        }
    }

    @Test func decodeRejectsUnsupportedVersion() {
        let url = URL(string: "https://zonebuddy.jacksn.dev/workout/Zpayload")!
        #expect(throws: WorkoutCoderError.unsupportedVersion) {
            try WorkoutCoder.decode(url)
        }
    }

    @Test func decodeRejectsInvalidBase64() {
        let url = URL(string: "https://zonebuddy.jacksn.dev/workout/A!!!invalid!!!")!
        #expect(throws: WorkoutCoderError.decodingFailed) {
            try WorkoutCoder.decode(url)
        }
    }

    @Test func base64URLRoundTrip() {
        let original = Data("Hello, World! Special chars: +/=".utf8)
        let encoded = original.base64URLEncodedString()
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        let decoded = Data(base64URLEncoded: encoded)
        #expect(decoded == original)
    }
}
