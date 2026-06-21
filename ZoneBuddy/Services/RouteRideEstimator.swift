import Foundation

/// Estimates how long an imported route would take to ride. Pure and
/// SwiftData-free (takes `[RoutePoint]`) so it's cheap to call from the
/// preview screen and trivial to unit-test.
///
/// The model assumes the rider holds a constant fraction of FTP for the whole
/// route and computes the steady-state ground speed at each segment's grade via
/// `CyclingPhysics`. Real rides vary effort, so this is deliberately a rough
/// "endurance pace" ballpark, surfaced with a `~` in the UI.
enum RouteRideEstimator {
    /// Fraction of FTP we assume the rider holds on a route ride. ~0.7 lands in
    /// the endurance/tempo band — a sustainable all-route effort.
    static let assumedPowerFraction = 0.7

    /// Lowest speed we'll integrate against, m/s (~1.8 km/h). Without a floor a
    /// near-zero speed on a clamped 20% wall would blow the estimate up toward
    /// infinity; in reality the rider would stand, push harder, or walk.
    static let minSpeedMS = 0.5

    /// Estimated ride time in seconds. Returns 0 for empty/single-point input.
    static func estimatedSeconds(points: [RoutePoint], ftp: Int, riderWeightKg: Double) -> Double {
        guard points.count >= 2 else { return 0 }

        let power = Double(max(ftp, 1)) * assumedPowerFraction
        var seconds = 0.0
        for i in 1..<points.count {
            let segmentDistance = points[i].distanceMeters - points[i - 1].distanceMeters
            guard segmentDistance > 0 else { continue }
            // Use the leading point's grade for the segment it begins.
            let speed = CyclingPhysics.virtualSpeedMS(
                powerWatts: power,
                gradePercent: points[i - 1].gradePercent,
                riderWeightKg: riderWeightKg
            )
            seconds += segmentDistance / max(speed, minSpeedMS)
        }
        return seconds
    }

    /// Coarse "~1h 23m" / "~47m" label for an estimate in seconds. The `~`
    /// signals it's a ballpark and we drop seconds — the model is only
    /// approximate, so second-level precision would be false confidence.
    static func formattedEstimate(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "~\(hours)h \(minutes)m"
        }
        return "~\(max(minutes, 1))m"
    }
}
