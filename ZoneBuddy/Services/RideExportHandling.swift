import Foundation
import CoreLocation

/// A timestamped heart-rate observation collected independently of the bike.
/// The Watch/BLE heart-rate stream is deliberately separate from
/// `BikeDataSample`: it remains available when no trainer is connected and it
/// takes precedence over a trainer's bundled HR value during export.
struct RideHeartRateSample: Equatable {
    let timestamp: Date
    let beatsPerMinute: Int
}

/// One uninterrupted period during which the workout timer was running.
/// Export formats such as FIT can represent these boundaries, keeping paused
/// time out of Strava's moving time without discarding the original timestamps.
struct RideTimerSegment: Equatable {
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// The seam the workout player calls when a ride finishes, right after the
/// `WorkoutSession` is persisted. The live implementation captures the richest
/// Strava file supported for the ride type and auto-uploads when enabled.
///
/// Declared here (shared with the watchOS target, which also compiles the
/// player view model) so the VM can hold the dependency. On watchOS no
/// implementation is injected, so finishing a ride is a no-op for export.
///
/// Only Foundation + CoreLocation appear in the signature so this stays
/// watchOS-safe; the concrete Strava handler lives in the iOS-only `Strava`
/// folder.
protocol RideExportHandling {
    func handleFinishedRide(
        session: WorkoutSession,
        samples: [BikeDataSample],
        heartRateSamples: [RideHeartRateSample],
        timerSegments: [RideTimerSegment],
        locations: [CLLocation],
        totalCalories: Int?
    )
}
