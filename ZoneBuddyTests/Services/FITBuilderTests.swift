import Foundation
import FITSwiftSDK
import Testing
@testable import ZoneBuddy

struct FITBuilderTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func bike(
        _ offset: TimeInterval,
        power: Int = 200,
        cadence: Double = 90,
        heartRate: Int? = 120,
        speed: Double = 36
    ) -> BikeDataSample {
        BikeDataSample(
            timestamp: start.addingTimeInterval(offset),
            power: power,
            cadence: cadence,
            heartRate: heartRate,
            speed: speed,
            distance: nil,
            calories: nil
        )
    }

    private func decode(_ data: Data) throws -> FitMessages {
        let decoder = Decoder(stream: FITSwiftSDK.InputStream(data: data))
        #expect(try decoder.isFIT())
        #expect(try decoder.checkIntegrity())
        let listener = FitListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        return listener.fitMessages
    }

    @Test
    func emitsInstantaneousWattsAndCompleteIndoorSessionSummaries() throws {
        let samples = [
            bike(0, power: 150),
            bike(1, power: 200),
            bike(2, power: 250),
        ]
        let data = try FITBuilder.makeFIT(
            samples: samples,
            heartRateSamples: [],
            timerSegments: [RideTimerSegment(start: start, end: start.addingTimeInterval(2))],
            intervals: [.init(zone: .zone2, duration: 2)],
            totalDuration: 2,
            totalCalories: 25,
            serialNumber: 42
        )

        let messages = try decode(data)
        #expect(messages.recordMesgs.map { $0.getPower() } == [150, 200, 250])
        #expect(messages.recordMesgs.allSatisfy { $0.getEnhancedSpeed() == 10 })
        #expect(messages.sessionMesgs.count == 1)
        #expect(messages.sessionMesgs[0].getSport() == .cycling)
        #expect(messages.sessionMesgs[0].getSubSport() == .indoorCycling)
        #expect(messages.sessionMesgs[0].getAvgPower() == 200)
        #expect(messages.sessionMesgs[0].getMaxPower() == 250)
        #expect(messages.sessionMesgs[0].getTotalWork() == 450)
        #expect(messages.sessionMesgs[0].getTotalCalories() == 25)
        #expect(messages.deviceInfoMesgs[0].getProductName() == "ZoneBuddy")
    }

    @Test
    func emitsOneLapPerPowerZoneInterval() throws {
        let samples = (0...6).map { bike(TimeInterval($0), power: 100 + $0 * 10) }
        let data = try FITBuilder.makeFIT(
            samples: samples,
            heartRateSamples: [],
            timerSegments: [RideTimerSegment(start: start, end: start.addingTimeInterval(6))],
            intervals: [
                .init(zone: nil, duration: 2),
                .init(zone: .zone3, duration: 3),
                .init(zone: .zone1, duration: 1),
            ],
            totalDuration: 6,
            totalCalories: nil,
            serialNumber: 7
        )

        let messages = try decode(data)
        #expect(messages.lapMesgs.count == 3)
        #expect(messages.lapMesgs.map { $0.getTotalTimerTime() } == [2, 3, 1])
        #expect(messages.lapMesgs.map { $0.getIntensity() } == [.warmup, .interval, .interval])
        #expect(messages.sessionMesgs[0].getNumLaps() == 3)
    }

    @Test
    func preservesPauseEventsAndExcludesPausedTimeFromTimerDuration() throws {
        let secondStart = start.addingTimeInterval(12)
        let samples = [bike(0), bike(1), bike(2), bike(12), bike(13), bike(14)]
        let data = try FITBuilder.makeFIT(
            samples: samples,
            heartRateSamples: [],
            timerSegments: [
                RideTimerSegment(start: start, end: start.addingTimeInterval(2)),
                RideTimerSegment(start: secondStart, end: secondStart.addingTimeInterval(2)),
            ],
            intervals: [.init(zone: .zone2, duration: 4)],
            totalDuration: 4,
            totalCalories: nil,
            serialNumber: 8
        )

        let messages = try decode(data)
        #expect(messages.eventMesgs.map { $0.getEventType() } == [.start, .stopAll, .start, .stopAll])
        #expect(messages.sessionMesgs[0].getTotalTimerTime() == 4)
        #expect(messages.sessionMesgs[0].getTotalElapsedTime() == 14)
    }

    @Test
    func watchHeartRateOverridesBikeHRAndWorksWithoutBikeRecords() throws {
        let data = try FITBuilder.makeFIT(
            samples: [bike(0, heartRate: 100), bike(1, heartRate: 101)],
            heartRateSamples: [
                RideHeartRateSample(timestamp: start, beatsPerMinute: 145),
                RideHeartRateSample(timestamp: start.addingTimeInterval(1), beatsPerMinute: 146),
            ],
            timerSegments: [RideTimerSegment(start: start, end: start.addingTimeInterval(1))],
            intervals: [.init(zone: .zone2, duration: 1)],
            totalDuration: 1,
            totalCalories: nil,
            serialNumber: 9
        )
        let messages = try decode(data)
        #expect(messages.recordMesgs.map { $0.getHeartRate() } == [145, 146])

        let heartRateOnly = try FITBuilder.makeFIT(
            samples: [],
            heartRateSamples: [RideHeartRateSample(timestamp: start, beatsPerMinute: 155)],
            timerSegments: [RideTimerSegment(start: start, end: start.addingTimeInterval(1))],
            intervals: [.init(zone: .zone1, duration: 1)],
            totalDuration: 1,
            totalCalories: nil,
            serialNumber: 10
        )
        #expect(try decode(heartRateOnly).recordMesgs[0].getHeartRate() == 155)
    }
}
