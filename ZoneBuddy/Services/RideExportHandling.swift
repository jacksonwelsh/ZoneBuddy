import Foundation
import CoreLocation

/// The seam the workout player calls when a ride finishes, right after the
/// `WorkoutSession` is persisted. The live (iOS) implementation builds a Strava
/// TCX from the ride's in-memory sample + location streams, stores it on the
/// session, and auto-uploads when the user has enabled it.
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
        locations: [CLLocation],
        totalCalories: Int?
    )
}
