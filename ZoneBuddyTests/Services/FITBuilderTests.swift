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
    func compressesPauseGapsSoElapsedAndTimerDurationMatch() throws {
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
        #expect(messages.eventMesgs.map { $0.getEventType() } == [.start, .stopAll])
        #expect(messages.sessionMesgs[0].getTotalTimerTime() == 4)
        #expect(messages.sessionMesgs[0].getTotalElapsedTime() == 4)
        #expect(messages.lapMesgs[0].getTotalElapsedTime() == 4)
        let recordTimestamps = messages.recordMesgs.compactMap { $0.getTimestamp()?.date }
        #expect(recordTimestamps.last?.timeIntervalSince(recordTimestamps.first!) == 4)
    }

    @Test
    func addsRecordsAtTimerBoundariesWhenSensorSamplesStartLateAndEndEarly() throws {
        let data = try FITBuilder.makeFIT(
            samples: [bike(1, power: 150), bike(2, power: 200), bike(3, power: 250)],
            heartRateSamples: [],
            timerSegments: [RideTimerSegment(start: start, end: start.addingTimeInterval(4))],
            intervals: [.init(zone: .zone2, duration: 4)],
            totalDuration: 4,
            totalCalories: nil,
            serialNumber: 11
        )

        let messages = try decode(data)
        let timestamps = messages.recordMesgs.compactMap { $0.getTimestamp()?.date }
        #expect(timestamps.count == 5)
        #expect(timestamps.first == start)
        #expect(timestamps.last == start.addingTimeInterval(4))
        #expect(timestamps.last?.timeIntervalSince(timestamps.first!) == 4)
        #expect(messages.recordMesgs.map { $0.getPower() } == [150, 150, 200, 250, 250])
    }

    @Test
    func carriesAsynchronousTrainerTelemetryAcrossHeartRateOnlySeconds() throws {
        let data = try FITBuilder.makeFIT(
            samples: [
                bike(0.8, power: 150),
                bike(1.8, power: 160),
                bike(3.2, power: 180),
                bike(4, power: 190),
            ],
            heartRateSamples: (0...4).map {
                RideHeartRateSample(timestamp: start.addingTimeInterval(TimeInterval($0)), beatsPerMinute: 140 + $0)
            },
            timerSegments: [RideTimerSegment(start: start, end: start.addingTimeInterval(4))],
            intervals: [.init(zone: .zone2, duration: 4)],
            totalDuration: 4,
            totalCalories: nil,
            serialNumber: 12
        )

        let messages = try decode(data)
        #expect(messages.recordMesgs.map { $0.getPower() } == [150, 160, 160, 180, 190])
        #expect(messages.recordMesgs.map { $0.getCadence() } == [90, 90, 90, 90, 90])
        #expect(messages.recordMesgs.map { $0.getHeartRate() } == [140, 141, 142, 143, 144])
    }

    @Test
    func leavesLongTrainerOutagesWithoutPower() throws {
        let data = try FITBuilder.makeFIT(
            samples: [bike(0, power: 150), bike(4, power: 200)],
            heartRateSamples: (0...4).map {
                RideHeartRateSample(timestamp: start.addingTimeInterval(TimeInterval($0)), beatsPerMinute: 140)
            },
            timerSegments: [RideTimerSegment(start: start, end: start.addingTimeInterval(4))],
            intervals: [.init(zone: .zone2, duration: 4)],
            totalDuration: 4,
            totalCalories: nil,
            serialNumber: 13
        )

        let messages = try decode(data)
        #expect(messages.recordMesgs.map { $0.getPower() } == [150, 150, nil, nil, 200])
    }

    @Test
    func doesNotCarryTrainerTelemetryAcrossPauseBoundaries() throws {
        let secondStart = start.addingTimeInterval(12)
        let data = try FITBuilder.makeFIT(
            samples: [bike(0, power: 150), bike(13, power: 200)],
            heartRateSamples: [RideHeartRateSample(timestamp: secondStart, beatsPerMinute: 145)],
            timerSegments: [
                RideTimerSegment(start: start, end: start.addingTimeInterval(1)),
                RideTimerSegment(start: secondStart, end: secondStart.addingTimeInterval(1)),
            ],
            intervals: [.init(zone: .zone2, duration: 2)],
            totalDuration: 2,
            totalCalories: nil,
            serialNumber: 14
        )

        let messages = try decode(data)
        #expect(messages.recordMesgs.map { $0.getPower() } == [150, nil, 200])
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
