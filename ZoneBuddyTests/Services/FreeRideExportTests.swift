import Foundation
import Testing
@testable import ZoneBuddy

@MainActor
struct FreeRideExportTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ second: Double, power: Int = 180) -> BikeDataSample {
        .init(timestamp: start.addingTimeInterval(second), power: power, cadence: 85, heartRate: nil, speed: 36, distance: nil, calories: nil)
    }

    @Test
    func freeRideTCXRetainsIndependentHeartRateAndPower() throws {
        let session = WorkoutSession(name: "Free ride", totalDuration: 2, modality: .freeRide)
        session.stravaTCXData = TCXBuilder.makeTCX(
            samples: [sample(0), sample(2, power: 220)],
            heartRateSamples: [
                .init(timestamp: start.addingTimeInterval(0.4), beatsPerMinute: 140),
                .init(timestamp: start.addingTimeInterval(1.4), beatsPerMinute: 145),
                .init(timestamp: start.addingTimeInterval(2.4), beatsPerMinute: 150),
            ], locations: [])
        let envelope = try #require(CycloneEnvelopeBuilder.retainedOrLegacy(session: session))
        #expect(envelope.streams.first { $0.metric == "power" }?.samples == [[0, 180], [2000, 220]])
        #expect(envelope.streams.first { $0.metric == "heart_rate" }?.samples == [[0, 140], [1000, 145], [2000, 150]])
        let xml = String(decoding: session.stravaTCXData!, as: UTF8.self)
        #expect(xml.contains("<DistanceMeters>20.00</DistanceMeters>"))
    }

    @Test
    func heartRateOnlyTCXRetainsTimeline() throws {
        let data = TCXBuilder.makeTCX(samples: [], heartRateSamples: [
            .init(timestamp: start, beatsPerMinute: 120),
            .init(timestamp: start.addingTimeInterval(5), beatsPerMinute: 130),
        ], locations: [])
        let xml = String(decoding: data, as: UTF8.self)
        #expect(xml.contains("<TotalTimeSeconds>5.00</TotalTimeSeconds>"))
        #expect(xml.contains("<Value>130</Value>"))
    }

}
