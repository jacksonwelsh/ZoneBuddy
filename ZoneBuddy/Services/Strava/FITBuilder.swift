import Foundation
import FITSwiftSDK

/// Builds standards-compliant FIT activity files for structured indoor rides.
/// FIT is Strava's richest upload format: records retain the sensor streams,
/// events retain pause/resume boundaries, and each prescribed interval becomes
/// a lap for Strava's lap analysis.
enum FITBuilder {
    struct WorkoutInterval: Equatable {
        let zone: PowerZone?
        let duration: Int
    }

    private struct RecordValue {
        let timestamp: Date
        let sample: BikeDataSample?
        let heartRate: Int?
        let distanceMeters: Double
        let activeOffset: TimeInterval
    }

    static func makeFIT(
        samples: [BikeDataSample],
        heartRateSamples: [RideHeartRateSample],
        timerSegments: [RideTimerSegment],
        intervals: [WorkoutInterval],
        totalDuration: Int,
        totalCalories: Int?,
        serialNumber: UInt32
    ) throws -> Data {
        let segments = resolvedSegments(
            timerSegments,
            samples: samples,
            heartRates: heartRateSamples,
            totalDuration: totalDuration
        )
        let startDate = segments.first!.start
        let endDate = segments.last!.end
        let timerSeconds = max(1, totalDuration)

        let records = makeRecords(
            samples: samples,
            heartRates: heartRateSamples,
            segments: segments
        )

        let fileID = FileIdMesg()
        try fileID.setType(.activity)
        try fileID.setManufacturer(.development)
        try fileID.setProduct(0)
        try fileID.setProductName("ZoneBuddy")
        try fileID.setTimeCreated(DateTime(date: startDate))
        try fileID.setSerialNumber(serialNumber == 0 ? 1 : serialNumber)

        let device = DeviceInfoMesg()
        try device.setTimestamp(DateTime(date: startDate))
        try device.setDeviceIndex(DeviceIndexValues.creator)
        try device.setManufacturer(.development)
        try device.setProduct(0)
        try device.setProductName("ZoneBuddy")
        try device.setSerialNumber(serialNumber == 0 ? 1 : serialNumber)

        let encoder = Encoder()
        encoder.write(mesg: fileID)
        encoder.write(mesg: device)

        // Timer events and records are emitted in timestamp order. Start sorts
        // before a record at the same second; stop sorts after it.
        var timeline: [(date: Date, order: Int, message: Mesg)] = []
        for segment in segments {
            let start = EventMesg()
            try start.setTimestamp(DateTime(date: segment.start))
            try start.setEvent(.timer)
            try start.setEventType(.start)
            try start.setTimerTrigger(.manual)
            timeline.append((segment.start, 0, start))

            let stop = EventMesg()
            try stop.setTimestamp(DateTime(date: segment.end))
            try stop.setEvent(.timer)
            try stop.setEventType(.stopAll)
            try stop.setTimerTrigger(.manual)
            timeline.append((segment.end, 2, stop))
        }

        for value in records {
            let record = RecordMesg()
            try record.setTimestamp(DateTime(date: value.timestamp))
            try record.setDistance(value.distanceMeters)
            if let speed = value.sample?.speed, speed >= 0 {
                try record.setEnhancedSpeed(speed / 3.6)
            }
            if let heartRate = value.heartRate, heartRate > 0 {
                try record.setHeartRate(UInt8(clamping: heartRate))
            }
            if let cadence = value.sample?.cadence, cadence >= 0 {
                try record.setCadence(UInt8(clamping: Int(cadence.rounded())))
            }
            if let power = value.sample?.power, power >= 0 {
                try record.setPower(UInt16(clamping: power))
            }
            timeline.append((value.timestamp, 1, record))
        }

        timeline.sort {
            if $0.date == $1.date { return $0.order < $1.order }
            return $0.date < $1.date
        }
        for item in timeline { encoder.write(mesg: item.message) }

        let lapRanges = makeLapRanges(intervals: intervals, totalDuration: timerSeconds)
        for (index, range) in lapRanges.enumerated() {
            let lapStart = date(atActiveOffset: range.lowerBound, in: segments)
            let lapEnd = date(atActiveOffset: range.upperBound, in: segments)
            let lapRecords = records.filter {
                $0.activeOffset >= range.lowerBound &&
                $0.activeOffset <= range.upperBound
            }
            let lap = LapMesg()
            try lap.setMessageIndex(UInt16(clamping: index))
            try lap.setStartTime(DateTime(date: lapStart))
            try lap.setTimestamp(DateTime(date: lapEnd))
            try lap.setTotalTimerTime(range.upperBound - range.lowerBound)
            try lap.setTotalElapsedTime(max(0, lapEnd.timeIntervalSince(lapStart)))
            try lap.setTotalDistance(
                distance(at: range.upperBound, in: records) - distance(at: range.lowerBound, in: records)
            )
            try lap.setSport(.cycling)
            try lap.setSubSport(.indoorCycling)
            try lap.setLapTrigger(.manual)
            try lap.setIntensity(intervals.indices.contains(index) && intervals[index].zone == nil ? .warmup : .interval)
            try setSummaries(on: lap, from: lapRecords)
            if let totalCalories {
                let fraction = (range.upperBound - range.lowerBound) / Double(timerSeconds)
                try lap.setTotalCalories(UInt16(clamping: Int((Double(totalCalories) * fraction).rounded())))
            }
            encoder.write(mesg: lap)
        }

        let session = SessionMesg()
        try session.setMessageIndex(0)
        try session.setStartTime(DateTime(date: startDate))
        try session.setTimestamp(DateTime(date: endDate))
        try session.setTotalTimerTime(Double(timerSeconds))
        try session.setTotalElapsedTime(max(Double(timerSeconds), endDate.timeIntervalSince(startDate)))
        try session.setTotalDistance(records.last?.distanceMeters ?? 0)
        try session.setSport(.cycling)
        try session.setSubSport(.indoorCycling)
        try session.setFirstLapIndex(0)
        try session.setNumLaps(UInt16(clamping: lapRanges.count))
        try setSummaries(on: session, from: records)
        if let totalCalories { try session.setTotalCalories(UInt16(clamping: totalCalories)) }
        let work = integratedWork(in: records, segments: segments)
        if work > 0 { try session.setTotalWork(UInt32(clamping: Int(work.rounded()))) }
        encoder.write(mesg: session)

        let activity = ActivityMesg()
        try activity.setTimestamp(DateTime(date: endDate))
        try activity.setTotalTimerTime(Double(timerSeconds))
        try activity.setNumSessions(1)
        try activity.setType(.manual)
        let offset = TimeZone.current.secondsFromGMT(for: endDate)
        let localTimestamp = Int(DateTime(date: endDate).timestamp) + offset
        try activity.setLocalTimestamp(LocalDateTime(max(0, localTimestamp)))
        encoder.write(mesg: activity)

        return encoder.close()
    }

    private static func resolvedSegments(
        _ segments: [RideTimerSegment],
        samples: [BikeDataSample],
        heartRates: [RideHeartRateSample],
        totalDuration: Int
    ) -> [RideTimerSegment] {
        let valid = segments.filter { $0.end >= $0.start }.sorted { $0.start < $1.start }
        if !valid.isEmpty { return valid }
        let first = ([samples.map(\.timestamp).min(), heartRates.map(\.timestamp).min()]
            .compactMap { $0 }.min()) ?? Date(timeIntervalSince1970: 631_065_600)
        return [RideTimerSegment(start: first, end: first.addingTimeInterval(Double(max(1, totalDuration))))]
    }

    private static func makeRecords(
        samples: [BikeDataSample],
        heartRates: [RideHeartRateSample],
        segments: [RideTimerSegment]
    ) -> [RecordValue] {
        // FIT timestamps have one-second precision. Coalesce sources by second
        // so Watch HR can augment (or independently create) a trainer record.
        var bikes: [Int: BikeDataSample] = [:]
        for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            bikes[Int(sample.timestamp.timeIntervalSince1970)] = sample
        }
        var hrs: [Int: Int] = [:]
        for sample in heartRates.sorted(by: { $0.timestamp < $1.timestamp }) where sample.beatsPerMinute > 0 {
            hrs[Int(sample.timestamp.timeIntervalSince1970)] = sample.beatsPerMinute
        }

        let seconds = Set(bikes.keys).union(hrs.keys).sorted()
        var distance = 0.0
        var previousBike: BikeDataSample?
        var result: [RecordValue] = []
        for second in seconds {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(second))
            guard let activeOffset = activeOffset(for: timestamp, in: segments) else { continue }
            let bike = bikes[second]
            if let bike, let previous = previousBike,
               areInSameSegment(previous.timestamp, bike.timestamp, segments: segments),
               let speed = bike.speed {
                let dt = bike.timestamp.timeIntervalSince(previous.timestamp)
                if dt > 0 { distance += max(0, speed) / 3.6 * dt }
            }
            if let bike { previousBike = bike }
            result.append(RecordValue(
                timestamp: timestamp,
                sample: bike,
                heartRate: hrs[second] ?? bike?.heartRate,
                distanceMeters: distance,
                activeOffset: activeOffset
            ))
        }
        return result
    }

    private static func activeOffset(for date: Date, in segments: [RideTimerSegment]) -> TimeInterval? {
        var accumulated: TimeInterval = 0
        for segment in segments {
            if date >= segment.start && date <= segment.end {
                return accumulated + date.timeIntervalSince(segment.start)
            }
            accumulated += segment.duration
        }
        return nil
    }

    private static func date(atActiveOffset offset: TimeInterval, in segments: [RideTimerSegment]) -> Date {
        var remaining = max(0, offset)
        for segment in segments {
            if remaining <= segment.duration { return segment.start.addingTimeInterval(remaining) }
            remaining -= segment.duration
        }
        return segments.last!.end
    }

    private static func areInSameSegment(_ first: Date, _ second: Date, segments: [RideTimerSegment]) -> Bool {
        segments.contains { first >= $0.start && first <= $0.end && second >= $0.start && second <= $0.end }
    }

    private static func makeLapRanges(
        intervals: [WorkoutInterval],
        totalDuration: Int
    ) -> [Range<TimeInterval>] {
        guard !intervals.isEmpty else { return [0..<Double(totalDuration)] }
        var ranges: [Range<TimeInterval>] = []
        var start: TimeInterval = 0
        for interval in intervals where start < Double(totalDuration) {
            let end = min(Double(totalDuration), start + Double(max(0, interval.duration)))
            if end > start { ranges.append(start..<end) }
            start = end
        }
        if ranges.isEmpty { return [0..<Double(totalDuration)] }
        if start < Double(totalDuration) { ranges.append(start..<Double(totalDuration)) }
        return ranges
    }

    private static func distance(at activeOffset: TimeInterval, in records: [RecordValue]) -> Double {
        records.last(where: { $0.activeOffset <= activeOffset })?.distanceMeters ?? 0
    }

    private static func integratedWork(in records: [RecordValue], segments: [RideTimerSegment]) -> Double {
        var joules = 0.0
        var previousPoweredRecord: RecordValue?
        for record in records {
            guard let watts = record.sample?.power else { continue }
            defer { previousPoweredRecord = record }
            guard let previousPoweredRecord,
                  areInSameSegment(previousPoweredRecord.timestamp, record.timestamp, segments: segments) else { continue }
            let dt = record.timestamp.timeIntervalSince(previousPoweredRecord.timestamp)
            if dt > 0 { joules += Double(max(0, watts)) * dt }
        }
        return joules
    }

    private static func setSummaries(on lap: LapMesg, from records: [RecordValue]) throws {
        let speeds = records.compactMap { $0.sample?.speed }.filter { $0 >= 0 }.map { $0 / 3.6 }
        let heartRates = records.compactMap(\.heartRate).filter { $0 > 0 }
        let cadences = records.compactMap { $0.sample?.cadence }.filter { $0 >= 0 }
        let powers = records.compactMap { $0.sample?.power }.filter { $0 >= 0 }
        if !speeds.isEmpty {
            try lap.setAvgSpeed(speeds.reduce(0, +) / Double(speeds.count))
            try lap.setMaxSpeed(speeds.max()!)
        }
        if !heartRates.isEmpty {
            try lap.setAvgHeartRate(UInt8(clamping: heartRates.reduce(0, +) / heartRates.count))
            try lap.setMaxHeartRate(UInt8(clamping: heartRates.max()!))
        }
        if !cadences.isEmpty {
            try lap.setAvgCadence(UInt8(clamping: Int((cadences.reduce(0, +) / Double(cadences.count)).rounded())))
            try lap.setMaxCadence(UInt8(clamping: Int(cadences.max()!.rounded())))
        }
        if !powers.isEmpty {
            try lap.setAvgPower(UInt16(clamping: powers.reduce(0, +) / powers.count))
            try lap.setMaxPower(UInt16(clamping: powers.max()!))
        }
    }

    private static func setSummaries(on session: SessionMesg, from records: [RecordValue]) throws {
        let speeds = records.compactMap { $0.sample?.speed }.filter { $0 >= 0 }.map { $0 / 3.6 }
        let heartRates = records.compactMap(\.heartRate).filter { $0 > 0 }
        let cadences = records.compactMap { $0.sample?.cadence }.filter { $0 >= 0 }
        let powers = records.compactMap { $0.sample?.power }.filter { $0 >= 0 }
        if !speeds.isEmpty {
            try session.setAvgSpeed(speeds.reduce(0, +) / Double(speeds.count))
            try session.setMaxSpeed(speeds.max()!)
        }
        if !heartRates.isEmpty {
            try session.setAvgHeartRate(UInt8(clamping: heartRates.reduce(0, +) / heartRates.count))
            try session.setMaxHeartRate(UInt8(clamping: heartRates.max()!))
        }
        if !cadences.isEmpty {
            try session.setAvgCadence(UInt8(clamping: Int((cadences.reduce(0, +) / Double(cadences.count)).rounded())))
            try session.setMaxCadence(UInt8(clamping: Int(cadences.max()!.rounded())))
        }
        if !powers.isEmpty {
            try session.setAvgPower(UInt16(clamping: powers.reduce(0, +) / powers.count))
            try session.setMaxPower(UInt16(clamping: powers.max()!))
        }
    }
}
