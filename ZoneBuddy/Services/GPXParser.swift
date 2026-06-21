import Foundation

enum GPXParseError: Error, Equatable {
    case unreadable
    case noTrackPoints
    case malformedXML(String)
    case tooLarge(bytes: Int)
}

/// Parses GPX files into a `Route` ready for `context.insert`. All static —
/// the parser is `Sendable` and does not touch the main actor.
///
/// Pipeline:
///   1. Parse `<trkpt lat lon>` + `<ele>` triples in document order, across
///      all `<trkseg>` segments. `<rtept>` and `<wpt>` are ignored.
///   2. Compute cumulative distance via Haversine; drop zero-distance neighbours.
///   3. Resample to a uniform 5m step (linear interpolation of elevation).
///   4. Smooth elevation with a centred ~50m moving average.
///   5. Grade per step = central elevation difference over the smoothing
///      window, clamped to ±20% to guard against tunnel/GPS spikes.
///   6. Single pass accumulates gain/loss/min/max/total distance.
struct GPXParser {
    /// Hard upper bound on input file size — a 10Hz action-camera GPX of a
    /// multi-day ride can blow past 5MB; we'd rather surface a clear error
    /// than spend a minute parsing.
    static let maxBytes = 5 * 1024 * 1024

    /// Resampled spacing, metres. 5m gives ~200 points per km — fine enough
    /// for accurate grade lookups, sparse enough to keep the blob and chart
    /// renderable.
    static let resampleStepMeters: Double = 5.0

    /// Window over which elevation is smoothed and grade is computed, metres.
    /// 50m matches what Garmin / Ride With GPS use for their grade displays.
    static let smoothingWindowMeters: Double = 50.0

    /// Sanity guard against tunnel-induced elevation spikes producing
    /// nonsensical 80% grades.
    static let maxGradePercent: Double = 20.0

    /// Default rolling-resistance coefficient (road tyres on tarmac).
    static let defaultCrr: Double = 0.004
    /// Default wind-resistance coefficient (kg/m) for a road bike in the hoods.
    static let defaultCw: Double = 0.51

    struct RawPoint: Sendable {
        let lat: Double
        let lon: Double
        let ele: Double
    }

    static func parseRawPoints(from data: Data) throws -> [RawPoint] {
        guard data.count <= maxBytes else { throw GPXParseError.tooLarge(bytes: data.count) }
        guard !data.isEmpty else { throw GPXParseError.unreadable }

        let delegate = GPXSAXDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw GPXParseError.malformedXML(reason)
        }
        if let err = delegate.error { throw err }
        guard !delegate.points.isEmpty else { throw GPXParseError.noTrackPoints }
        return delegate.points
    }

    /// Full pipeline. Build a `Route` from raw GPX bytes.
    static func makeRoute(name: String, from data: Data) throws -> Route {
        let raw = try parseRawPoints(from: data)
        let resampled = resampleAndSmooth(raw)
        guard !resampled.isEmpty else { throw GPXParseError.noTrackPoints }
        return Route(name: name, points: resampled, rawGPX: data)
    }

    // MARK: - Pipeline

    /// Build cumulative-distance / smoothed-elevation / grade samples from raw
    /// `(lat, lon, ele)` triples.
    static func resampleAndSmooth(_ raw: [RawPoint]) -> [RoutePoint] {
        guard raw.count >= 2 else { return [] }

        // Cumulative distance from start, accumulated by Haversine between
        // consecutive raw points. Zero-distance neighbours (a stationary GPS
        // fix) are skipped so the resample doesn't sit on duplicate samples.
        struct Sample { let distance: Double; let ele: Double; let lat: Double; let lon: Double }
        var samples: [Sample] = []
        samples.reserveCapacity(raw.count)
        samples.append(Sample(distance: 0, ele: raw[0].ele, lat: raw[0].lat, lon: raw[0].lon))

        var cumulative: Double = 0
        for i in 1..<raw.count {
            let d = haversineMeters(
                lat1: raw[i - 1].lat, lon1: raw[i - 1].lon,
                lat2: raw[i].lat,     lon2: raw[i].lon
            )
            if d <= 0.01 { continue } // dedupe stationary fixes
            cumulative += d
            samples.append(Sample(distance: cumulative, ele: raw[i].ele, lat: raw[i].lat, lon: raw[i].lon))
        }
        guard samples.count >= 2 else { return [] }

        let totalDistance = samples.last!.distance
        // Resample to a uniform step. `sampleIndex` walks forward through the
        // raw samples; for each resample target we linearly interpolate
        // elevation and lat/lon between the bracketing samples.
        var resampled: [Sample] = []
        resampled.reserveCapacity(Int(totalDistance / resampleStepMeters) + 2)
        resampled.append(samples[0])
        var sampleIndex = 1
        var target = resampleStepMeters
        while target <= totalDistance {
            while sampleIndex < samples.count - 1 && samples[sampleIndex].distance < target {
                sampleIndex += 1
            }
            let lo = samples[sampleIndex - 1]
            let hi = samples[sampleIndex]
            let span = max(hi.distance - lo.distance, 0.0001)
            let t = (target - lo.distance) / span
            resampled.append(Sample(
                distance: target,
                ele: lo.ele + (hi.ele - lo.ele) * t,
                lat: lo.lat + (hi.lat - lo.lat) * t,
                lon: lo.lon + (hi.lon - lo.lon) * t
            ))
            target += resampleStepMeters
        }
        // Append the final sample if the route doesn't land exactly on a step.
        if resampled.last!.distance < totalDistance - 0.001 {
            resampled.append(samples.last!)
        }

        // Smooth elevation with a centred moving average over the smoothing
        // window. Window size in samples == window-metres / step-metres.
        let windowSamples = max(2, Int(smoothingWindowMeters / resampleStepMeters))
        let halfWindow = windowSamples / 2

        // Sliding-window sum for O(n) smoothing.
        var smoothedEle = [Double](repeating: 0, count: resampled.count)
        var windowSum: Double = 0
        var windowCount = 0
        // Prime the window with the first `halfWindow` samples.
        for j in 0..<min(halfWindow, resampled.count) {
            windowSum += resampled[j].ele
            windowCount += 1
        }
        for i in 0..<resampled.count {
            // Extend the trailing edge.
            let addIdx = i + halfWindow
            if addIdx < resampled.count {
                windowSum += resampled[addIdx].ele
                windowCount += 1
            }
            // Retract the leading edge.
            let dropIdx = i - halfWindow - 1
            if dropIdx >= 0 {
                windowSum -= resampled[dropIdx].ele
                windowCount -= 1
            }
            smoothedEle[i] = windowSum / Double(max(1, windowCount))
        }

        // Grade via central difference over the smoothing window. The window
        // spans 2*halfWindow*step metres around point i.
        var out: [RoutePoint] = []
        out.reserveCapacity(resampled.count)
        let windowMeters = Double(2 * halfWindow) * resampleStepMeters
        for i in 0..<resampled.count {
            let lo = max(0, i - halfWindow)
            let hi = min(resampled.count - 1, i + halfWindow)
            let dz = smoothedEle[hi] - smoothedEle[lo]
            let dx = max(Double(hi - lo) * resampleStepMeters, windowMeters * 0.1)
            var grade = (dz / dx) * 100.0
            if grade > maxGradePercent { grade = maxGradePercent }
            if grade < -maxGradePercent { grade = -maxGradePercent }
            out.append(RoutePoint(
                distanceMeters: resampled[i].distance,
                elevationMeters: smoothedEle[i],
                gradePercent: grade,
                latitude: resampled[i].lat,
                longitude: resampled[i].lon
            ))
        }
        return out
    }

    // MARK: - Geometry

    /// Great-circle distance in metres between two lat/lon points (Haversine).
    /// R = 6_371_000m (mean Earth radius).
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLam = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2)
              + cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}

// MARK: - XML SAX delegate

private final class GPXSAXDelegate: NSObject, XMLParserDelegate {
    var points: [GPXParser.RawPoint] = []
    var error: GPXParseError?

    /// We only collect points that appear inside `<trkseg>`. `<rtept>` (route
    /// points without elevation timing) and `<wpt>` (named waypoints) live
    /// outside that subtree and would muddle the resample if we mixed them in.
    private var inTrkseg = false
    private var inTrkpt = false
    private var inEle = false
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var eleBuffer = ""

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        switch elementName.lowercased() {
        case "trkseg":
            inTrkseg = true
        case "trkpt" where inTrkseg:
            inTrkpt = true
            currentLat = attributeDict["lat"].flatMap(Double.init)
            currentLon = attributeDict["lon"].flatMap(Double.init)
            currentEle = nil
        case "ele" where inTrkpt:
            inEle = true
            eleBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inEle { eleBuffer.append(string) }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName.lowercased() {
        case "ele" where inTrkpt:
            inEle = false
            currentEle = Double(eleBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
        case "trkpt":
            inTrkpt = false
            // Elevation is optional in GPX; default to 0 so points without
            // <ele> still anchor the route geometrically (the resulting grade
            // will be 0 across the gap, which is the best we can do).
            //
            // Validate the coordinate is a finite, in-range number before
            // accepting it. `Double.init` parses "nan"/"inf"/"1e400" from a
            // malformed or hand-edited GPX, and an unchecked NaN/Inf would
            // poison distance/grade math, get pushed to the trainer as a NaN
            // grade over BLE, and produce invalid HealthKit/CloudKit samples.
            // Drop the point entirely if it isn't a valid coordinate, and
            // discard a non-finite elevation (fall back to 0).
            if let lat = currentLat, let lon = currentLon,
               lat.isFinite, lon.isFinite,
               abs(lat) <= 90, abs(lon) <= 180 {
                let ele = currentEle.flatMap { $0.isFinite ? $0 : nil } ?? 0
                points.append(GPXParser.RawPoint(lat: lat, lon: lon, ele: ele))
            }
            currentLat = nil
            currentLon = nil
            currentEle = nil
        case "trkseg":
            inTrkseg = false
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil {
            error = .malformedXML(parseError.localizedDescription)
        }
    }
}
