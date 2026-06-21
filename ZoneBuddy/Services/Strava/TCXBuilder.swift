import Foundation
import CoreLocation

/// Builds a Garmin **TCX** document from a finished ride's telemetry, suitable
/// for upload to Strava's `/uploads` endpoint (`data_type=tcx`).
///
/// TCX is chosen over a manual activity because it carries the full per-second
/// streams Strava renders — power (via the Garmin `ns3:Watts` extension), heart
/// rate, cadence, distance — and, for route rides, lat/lon trackpoints that
/// become the activity map (the Zwift-style virtual ride).
///
/// Pure and dependency-free so it's exhaustively unit-testable: same inputs →
/// byte-identical document, no network or clock.
enum TCXBuilder {
    /// Reject sample-to-sample gaps longer than this when integrating distance.
    /// Matches `WorkoutSampleAggregator` so the embedded distance lines up with
    /// the app's own totals and the HealthKit summary.
    private static let maxIntegrationGapSeconds: TimeInterval = 30

    /// Build a TCX document for a ride.
    ///
    /// - Parameters:
    ///   - samples: Per-tick bike telemetry (≈1 Hz). Defines the trackpoint
    ///     timeline; an empty array yields a document with no trackpoints.
    ///   - locations: Route GPS fixes, ascending by time. Empty for indoor rides
    ///     — without them no `<Position>` is emitted and Strava shows no map.
    ///   - totalCalories: Optional lap-level calorie total.
    /// - Returns: UTF-8 encoded TCX XML.
    static func makeTCX(
        samples: [BikeDataSample],
        locations: [CLLocation],
        totalCalories: Int? = nil
    ) -> Data {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let sortedLocations = locations.sorted { $0.timestamp < $1.timestamp }

        let startDate = sorted.first?.timestamp ?? Date(timeIntervalSince1970: 0)
        let endDate = sorted.last?.timestamp ?? startDate
        let totalSeconds = max(0, endDate.timeIntervalSince(startDate))

        // Build trackpoints, integrating distance as we go so <DistanceMeters>
        // is monotonic and consistent with the in-app distance model.
        var trackpoints: [String] = []
        trackpoints.reserveCapacity(sorted.count)
        var cumulativeMeters = 0.0
        var maxSpeedMS = 0.0
        var previousDate: Date?
        var locationCursor = 0

        for sample in sorted {
            if let speed = sample.speed, let prev = previousDate {
                let dt = sample.timestamp.timeIntervalSince(prev)
                if dt > 0, dt < maxIntegrationGapSeconds {
                    let metersPerSecond = speed * 1000.0 / 3600.0
                    cumulativeMeters += metersPerSecond * dt
                    if metersPerSecond > maxSpeedMS { maxSpeedMS = metersPerSecond }
                }
            }
            previousDate = sample.timestamp

            // Attach the nearest GPS fix in time (two-pointer; both sorted asc).
            var matchedLocation: CLLocation?
            if !sortedLocations.isEmpty {
                while locationCursor + 1 < sortedLocations.count,
                      abs(sortedLocations[locationCursor + 1].timestamp.timeIntervalSince(sample.timestamp))
                      <= abs(sortedLocations[locationCursor].timestamp.timeIntervalSince(sample.timestamp)) {
                    locationCursor += 1
                }
                matchedLocation = sortedLocations[locationCursor]
            }

            trackpoints.append(
                trackpoint(
                    time: sample.timestamp,
                    location: matchedLocation,
                    distanceMeters: cumulativeMeters,
                    heartRate: sample.heartRate,
                    cadence: sample.cadence,
                    watts: sample.power
                )
            )
        }

        var lapChildren: [String] = [
            "        <TotalTimeSeconds>\(format(totalSeconds))</TotalTimeSeconds>",
            "        <DistanceMeters>\(format(cumulativeMeters))</DistanceMeters>",
            "        <MaximumSpeed>\(format(maxSpeedMS))</MaximumSpeed>",
        ]
        if let totalCalories {
            lapChildren.append("        <Calories>\(totalCalories)</Calories>")
        }
        lapChildren.append("        <Intensity>Active</Intensity>")
        lapChildren.append("        <TriggerMethod>Manual</TriggerMethod>")
        lapChildren.append("        <Track>")
        lapChildren.append(contentsOf: trackpoints)
        lapChildren.append("        </Track>")

        let startISO = iso8601(startDate)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(startISO)</Id>
              <Lap StartTime="\(startISO)">
        \(lapChildren.joined(separator: "\n"))
              </Lap>
              <Creator xsi:type="Device_t">
                <Name>ZoneBuddy</Name>
              </Creator>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """

        return Data(xml.utf8)
    }

    /// Build a *synthetic* TCX for a ride whose per-second streams weren't
    /// captured (e.g. a workout completed before the Strava integration). It
    /// reconstructs a coarse trackpoint timeline from persisted summary data so
    /// the activity lands on Strava with the **correct date, duration, distance,
    /// and average power/HR** — even though the moment-to-moment detail is gone.
    ///
    /// `startDate` must be the ride's true start (`completedAt − duration`) so
    /// Strava attributes the activity to when the ride actually happened.
    ///
    /// When `routePoints` is supplied (a route ride whose source `Route` still
    /// exists), the rider is walked along the route at constant pace so the
    /// activity regains its GPS map.
    ///
    /// - Parameter sampleInterval: spacing between synthesized trackpoints, s.
    static func makeSyntheticTCX(
        startDate: Date,
        duration: Int,
        avgPower: Int?,
        avgHeartRate: Int?,
        totalDistanceMeters: Double?,
        totalCalories: Int?,
        routePoints: [RoutePoint]? = nil,
        sampleInterval: Int = 5
    ) -> Data {
        let totalSeconds = max(1, duration)
        let routeTotal = routePoints?.last?.distanceMeters ?? 0
        let totalDistance = totalDistanceMeters ?? (routeTotal > 0 ? routeTotal : 0)
        // A constant speed reproduces `totalDistance` once `makeTCX` integrates
        // it over the trackpoint timeline (km/h: the integrator divides by 3.6).
        let speedKmh: Double? = totalDistance > 0 ? (totalDistance / Double(totalSeconds)) * 3.6 : nil

        // Trackpoint offsets: 0, interval, 2·interval, … and always the exact end.
        let step = max(1, sampleInterval)
        var offsets = Array(stride(from: 0, to: totalSeconds, by: step))
        if offsets.last != totalSeconds { offsets.append(totalSeconds) }

        let points = routePoints ?? []
        var cursor = 0
        var samples: [BikeDataSample] = []
        var locations: [CLLocation] = []
        samples.reserveCapacity(offsets.count)

        for sec in offsets {
            let timestamp = startDate.addingTimeInterval(Double(sec))
            samples.append(BikeDataSample(
                timestamp: timestamp,
                power: avgPower,
                cadence: nil,
                heartRate: avgHeartRate,
                speed: speedKmh,
                distance: nil,
                calories: nil
            ))

            guard !points.isEmpty, routeTotal > 0 else { continue }
            let targetDistance = (Double(sec) / Double(totalSeconds)) * routeTotal
            // Both `sec` and `targetDistance` increase monotonically, so the
            // cursor only ever moves forward.
            while cursor + 1 < points.count, points[cursor + 1].distanceMeters < targetDistance {
                cursor += 1
            }
            let lo = points[cursor]
            let hi = cursor + 1 < points.count ? points[cursor + 1] : lo
            let span = hi.distanceMeters - lo.distanceMeters
            let t = span > 0 ? (targetDistance - lo.distanceMeters) / span : 0
            locations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: lo.latitude + (hi.latitude - lo.latitude) * t,
                    longitude: lo.longitude + (hi.longitude - lo.longitude) * t
                ),
                altitude: lo.elevationMeters + (hi.elevationMeters - lo.elevationMeters) * t,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: timestamp
            ))
        }

        return makeTCX(samples: samples, locations: locations, totalCalories: totalCalories)
    }

    // MARK: - Trackpoint

    private static func trackpoint(
        time: Date,
        location: CLLocation?,
        distanceMeters: Double,
        heartRate: Int?,
        cadence: Double?,
        watts: Int?
    ) -> String {
        var lines: [String] = ["          <Trackpoint>"]
        lines.append("            <Time>\(iso8601(time))</Time>")

        if let location {
            lines.append("            <Position>")
            lines.append("              <LatitudeDegrees>\(format(location.coordinate.latitude, decimals: 7))</LatitudeDegrees>")
            lines.append("              <LongitudeDegrees>\(format(location.coordinate.longitude, decimals: 7))</LongitudeDegrees>")
            lines.append("            </Position>")
            if location.verticalAccuracy >= 0 {
                lines.append("            <AltitudeMeters>\(format(location.altitude))</AltitudeMeters>")
            }
        }

        lines.append("            <DistanceMeters>\(format(distanceMeters))</DistanceMeters>")

        if let heartRate, heartRate > 0 {
            lines.append("            <HeartRateBpm><Value>\(heartRate)</Value></HeartRateBpm>")
        }

        if let cadence {
            // TCX <Cadence> is an integer RPM, 0–254.
            let rpm = min(254, max(0, Int(cadence.rounded())))
            lines.append("            <Cadence>\(rpm)</Cadence>")
        }

        if let watts {
            lines.append("            <Extensions>")
            lines.append("              <ns3:TPX>")
            lines.append("                <ns3:Watts>\(max(0, watts))</ns3:Watts>")
            lines.append("              </ns3:TPX>")
            lines.append("            </Extensions>")
        }

        lines.append("          </Trackpoint>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting

    /// TCX timestamps are UTC ISO-8601 with no fractional seconds, e.g.
    /// `2026-06-20T12:00:00Z`. A fixed formatter keeps output deterministic.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func iso8601(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Locale-independent fixed-precision formatting — `String(format:)` honors
    /// the C locale, so the decimal separator is always `.` regardless of the
    /// device region. Trailing zeros are fine for XML and keep output stable.
    private static func format(_ value: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
