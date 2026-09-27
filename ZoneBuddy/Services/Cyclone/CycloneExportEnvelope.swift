import Compression
import CoreLocation
import FITSwiftSDK
import Foundation

struct CycloneExportEnvelope: Codable, Equatable {
    struct Source: Codable, Equatable {
        struct Link: Codable, Equatable {
            let namespace: String
            let id: String
        }

        let namespace: String
        let id: String
        var linkedSources: [Link] = []
    }

    struct Metrics: Codable, Equatable {
        let durationSeconds: Int
        let movingDurationSeconds: Int
        let distanceMeters: Double?
        let activeEnergyKcal: Double?
        let averageSpeedMps: Double?
        let maximumSpeedMps: Double?
        let averageHeartRateBpm: Double?
        let maximumHeartRateBpm: Double?
        let averagePowerWatts: Double?
        let maximumPowerWatts: Double?
        let averageCadenceRpm: Double?
        let workKilojoules: Double?

        enum CodingKeys: String, CodingKey {
            case durationSeconds, movingDurationSeconds, distanceMeters
            case activeEnergyKcal, averageSpeedMps, maximumSpeedMps
            case averageHeartRateBpm, maximumHeartRateBpm
            case averagePowerWatts, maximumPowerWatts, averageCadenceRpm
            case workKilojoules
        }

        func encode(to encoder: any Swift.Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(durationSeconds, forKey: .durationSeconds)
            try values.encode(movingDurationSeconds, forKey: .movingDurationSeconds)
            try values.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
            try values.encodeIfPresent(activeEnergyKcal, forKey: .activeEnergyKcal)
            try values.encodeIfPresent(averageSpeedMps, forKey: .averageSpeedMps)
            try values.encodeIfPresent(maximumSpeedMps, forKey: .maximumSpeedMps)
            try values.encodeIfPresent(averageHeartRateBpm, forKey: .averageHeartRateBpm)
            try values.encodeIfPresent(maximumHeartRateBpm, forKey: .maximumHeartRateBpm)
            try values.encodeIfPresent(averagePowerWatts, forKey: .averagePowerWatts)
            try values.encodeIfPresent(maximumPowerWatts, forKey: .maximumPowerWatts)
            try values.encodeIfPresent(averageCadenceRpm, forKey: .averageCadenceRpm)
            try values.encodeIfPresent(workKilojoules, forKey: .workKilojoules)
        }
    }

    struct Stream: Codable, Equatable {
        let metric: String
        let unit: String
        let samples: [[Double]]
    }

    struct Point: Codable, Equatable {
        let latitude: Double
        let longitude: Double
        let altitudeMeters: Double?
        let elapsedMilliseconds: Int
    }

    struct Interval: Codable, Equatable {
        let index: Int
        let durationSeconds: Int
        let powerZone: Int?
    }

    struct Zones: Codable, Equatable {
        let powerSeconds: [String: Int]
        let heartRateSeconds: [String: Int]
    }

    let source: Source
    let type: String
    let virtual: Bool
    let title: String
    let descriptionMarkdown: String
    let startedAt: Date
    let timezone: String
    let localDate: String
    let metrics: Metrics
    let streams: [Stream]
    let route: [Point]
    let laps: [Interval]
    let intervals: [Interval]
    let zones: Zones
}

enum CycloneEnvelopeBuilder {
    static func live(
        session: WorkoutSession,
        samples: [BikeDataSample],
        heartRateSamples: [RideHeartRateSample],
        locations: [CLLocation]
    ) -> CycloneExportEnvelope {
        let startedAt = samples.map(\.timestamp).min()
            ?? heartRateSamples.map(\.timestamp).min()
            ?? session.completedAt.addingTimeInterval(-Double(session.totalDuration))

        var streams: [CycloneExportEnvelope.Stream] = []
        appendStream("power", unit: "W", values: samples.compactMap { sample in
            sample.power.map { (sample.timestamp, Double($0)) }
        }, start: startedAt, to: &streams)
        appendStream("cadence", unit: "rpm", values: samples.compactMap { sample in
            sample.cadence.map { (sample.timestamp, $0) }
        }, start: startedAt, to: &streams)
        appendStream("speed", unit: "m/s", values: samples.compactMap { sample in
            sample.speed.map { (sample.timestamp, $0 / 3.6) }
        }, start: startedAt, to: &streams)
        let heartRates = heartRateSamples.isEmpty
            ? samples.compactMap { sample in sample.heartRate.map { (sample.timestamp, Double($0)) } }
            : heartRateSamples.map { ($0.timestamp, Double($0.beatsPerMinute)) }
        appendStream("heart_rate", unit: "bpm", values: heartRates, start: startedAt, to: &streams)

        let route = locations.sorted { $0.timestamp < $1.timestamp }.map {
            CycloneExportEnvelope.Point(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude,
                altitudeMeters: $0.verticalAccuracy >= 0 ? $0.altitude : nil,
                elapsedMilliseconds: max(0, Int($0.timestamp.timeIntervalSince(startedAt) * 1_000))
            )
        }
        return make(session: session, startedAt: startedAt, streams: streams, route: route)
    }

    static func retainedOrLegacy(session: WorkoutSession) -> CycloneExportEnvelope? {
        if let compressed = session.cycloneExportData,
           let data = CycloneCompression.decompress(compressed),
           let envelope = try? decoder.decode(CycloneExportEnvelope.self, from: data) {
            return envelope
        }
        if let fit = session.stravaFITData, let decoded = decodeFIT(fit, session: session) { return decoded }
        if let tcx = session.stravaTCXData, let decoded = decodeTCX(tcx, session: session) { return decoded }
        guard session.totalDuration > 0 else { return nil }
        return make(
            session: session,
            startedAt: session.completedAt.addingTimeInterval(-Double(session.totalDuration)),
            streams: [],
            route: []
        )
    }

    static func compressed(_ envelope: CycloneExportEnvelope) -> Data? {
        guard let data = try? encoder.encode(envelope) else { return nil }
        return CycloneCompression.compress(data)
    }

    private static func make(
        session: WorkoutSession,
        startedAt: Date,
        streams: [CycloneExportEnvelope.Stream],
        route: [CycloneExportEnvelope.Point]
    ) -> CycloneExportEnvelope {
        let intervals = (session.intervals ?? []).sorted { $0.sortOrder < $1.sortOrder }.enumerated().map {
            CycloneExportEnvelope.Interval(
                index: $0.offset,
                durationSeconds: $0.element.duration,
                powerZone: $0.element.zone?.rawValue
            )
        }
        let virtual: Bool = {
            if case .routeRide = session.modality { return true }
            return false
        }()
        let timeZone = TimeZone.current
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return CycloneExportEnvelope(
            source: .init(namespace: "zonebuddy", id: session.id.uuidString),
            type: "indoor_ride",
            virtual: virtual,
            title: session.name.isEmpty ? "Indoor ride" : session.name,
            descriptionMarkdown: "Recorded with ZoneBuddy",
            startedAt: startedAt,
            timezone: timeZone.identifier,
            localDate: dateFormatter.string(from: startedAt),
            metrics: .init(
                durationSeconds: session.totalDuration,
                movingDurationSeconds: session.totalDuration,
                distanceMeters: session.totalDistance,
                activeEnergyKcal: session.totalCalories.map(Double.init),
                averageSpeedMps: session.totalDistance.map { $0 / Double(max(session.totalDuration, 1)) },
                maximumSpeedMps: nil,
                averageHeartRateBpm: session.avgHeartRate.map(Double.init),
                maximumHeartRateBpm: session.maxHeartRate.map(Double.init),
                averagePowerWatts: session.avgPower.map(Double.init),
                maximumPowerWatts: session.maxPower.map(Double.init),
                averageCadenceRpm: average(in: streams.first { $0.metric == "cadence" }),
                workKilojoules: session.totalOutputKJ
            ),
            streams: streams,
            route: route,
            laps: intervals,
            intervals: intervals,
            zones: .init(
                powerSeconds: [
                    "1": session.onTargetZone1Sec, "2": session.onTargetZone2Sec,
                    "3": session.onTargetZone3Sec, "4": session.onTargetZone4Sec,
                    "5": session.onTargetZone5Sec, "6": session.onTargetZone6Sec,
                    "7": session.onTargetZone7Sec,
                ],
                heartRateSeconds: [
                    "1": session.hrZone1Sec, "2": session.hrZone2Sec,
                    "3": session.hrZone3Sec, "4": session.hrZone4Sec,
                    "5": session.hrZone5Sec,
                ]
            )
        )
    }

    private static func appendStream(
        _ metric: String,
        unit: String,
        values: [(Date, Double)],
        start: Date,
        to streams: inout [CycloneExportEnvelope.Stream]
    ) {
        guard !values.isEmpty else { return }
        streams.append(.init(
            metric: metric,
            unit: unit,
            samples: values.sorted { $0.0 < $1.0 }.map {
                [Double(max(0, Int($0.0.timeIntervalSince(start) * 1_000))), $0.1]
            }
        ))
    }

    private static func average(in stream: CycloneExportEnvelope.Stream?) -> Double? {
        guard let values = stream?.samples.compactMap({ $0.count == 2 ? $0[1] : nil }), !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func decodeFIT(_ data: Data, session: WorkoutSession) -> CycloneExportEnvelope? {
        let decoder = Decoder(stream: FITSwiftSDK.InputStream(data: data))
        guard (try? decoder.isFIT()) == true, (try? decoder.checkIntegrity()) == true else { return nil }
        let listener = FitListener()
        decoder.addMesgListener(listener)
        guard (try? decoder.read()) != nil else { return nil }
        let records = listener.fitMessages.recordMesgs
        guard let start = records.compactMap({ $0.getTimestamp()?.date }).min() else { return nil }
        var streams: [CycloneExportEnvelope.Stream] = []
        appendStream("power", unit: "W", values: records.compactMap { record in
            guard let date = record.getTimestamp()?.date, let value = record.getPower() else { return nil }
            return (date, Double(value))
        }, start: start, to: &streams)
        appendStream("heart_rate", unit: "bpm", values: records.compactMap { record in
            guard let date = record.getTimestamp()?.date, let value = record.getHeartRate() else { return nil }
            return (date, Double(value))
        }, start: start, to: &streams)
        appendStream("cadence", unit: "rpm", values: records.compactMap { record in
            guard let date = record.getTimestamp()?.date, let value = record.getCadence() else { return nil }
            return (date, Double(value))
        }, start: start, to: &streams)
        appendStream("speed", unit: "m/s", values: records.compactMap { record in
            guard let date = record.getTimestamp()?.date, let value = record.getEnhancedSpeed() else { return nil }
            return (date, value)
        }, start: start, to: &streams)
        return make(session: session, startedAt: start, streams: streams, route: [])
    }

    private static func decodeTCX(_ data: Data, session: WorkoutSession) -> CycloneExportEnvelope? {
        let parser = CycloneTCXParser()
        guard parser.parse(data), let start = parser.points.compactMap(\.date).min() else { return nil }
        var streams: [CycloneExportEnvelope.Stream] = []
        appendStream("power", unit: "W", values: parser.points.compactMap { point in
            guard let date = point.date, let value = point.power else { return nil }; return (date, value)
        }, start: start, to: &streams)
        appendStream("heart_rate", unit: "bpm", values: parser.points.compactMap { point in
            guard let date = point.date, let value = point.heartRate else { return nil }; return (date, value)
        }, start: start, to: &streams)
        appendStream("cadence", unit: "rpm", values: parser.points.compactMap { point in
            guard let date = point.date, let value = point.cadence else { return nil }; return (date, value)
        }, start: start, to: &streams)
        let route = parser.points.compactMap { point -> CycloneExportEnvelope.Point? in
            guard let date = point.date, let latitude = point.latitude, let longitude = point.longitude else { return nil }
            return .init(latitude: latitude, longitude: longitude, altitudeMeters: point.altitude, elapsedMilliseconds: max(0, Int(date.timeIntervalSince(start) * 1_000)))
        }
        return make(session: session, startedAt: start, streams: streams, route: route)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.keyEncodingStrategy = .convertToSnakeCase
        value.dateEncodingStrategy = .iso8601
        return value
    }()
    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.keyDecodingStrategy = .convertFromSnakeCase
        value.dateDecodingStrategy = .iso8601
        return value
    }()
}

enum CycloneCompression {
    static func compress(_ data: Data) -> Data? {
        transform(data, operation: compression_encode_buffer, initialCapacity: max(64, data.count + data.count / 4))
    }

    static func decompress(_ data: Data) -> Data? {
        var capacity = max(1_024, data.count * 4)
        while capacity <= 64 * 1_024 * 1_024 {
            if let result = transform(data, operation: compression_decode_buffer, initialCapacity: capacity) { return result }
            capacity *= 2
        }
        return nil
    }

    private static func transform(
        _ data: Data,
        operation: (UnsafeMutablePointer<UInt8>, Int, UnsafePointer<UInt8>, Int, UnsafeMutableRawPointer?, compression_algorithm) -> Int,
        initialCapacity: Int
    ) -> Data? {
        var output = Data(count: initialCapacity)
        let count = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                operation(
                    destination.bindMemory(to: UInt8.self).baseAddress!, initialCapacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard count > 0 else { return nil }
        output.count = count
        return output
    }
}

private final class CycloneTCXParser: NSObject, XMLParserDelegate {
    struct Point {
        var date: Date?
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var power: Double?
        var heartRate: Double?
        var cadence: Double?
    }

    private(set) var points: [Point] = []
    private var point: Point?
    private var element = ""
    private var text = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        // Garmin extensions use qualified names such as ns3:Watts. Process
        // namespaces so the delegate receives local names regardless of prefix.
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        text = ""
        if elementName == "Trackpoint" { point = Point() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Time": point?.date = Self.date(from: value)
        case "LatitudeDegrees": point?.latitude = Double(value)
        case "LongitudeDegrees": point?.longitude = Double(value)
        case "AltitudeMeters": point?.altitude = Double(value)
        case "Value": point?.heartRate = Double(value)
        case "Cadence": point?.cadence = Double(value)
        case "Watts": point?.power = Double(value)
        case "Trackpoint": if let point { points.append(point) }; point = nil
        default: break
        }
        element = ""
        text = ""
    }

    private static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
