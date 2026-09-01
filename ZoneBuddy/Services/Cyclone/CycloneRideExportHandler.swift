import CoreLocation
import Foundation
import SwiftData

/// Captures a normalized Cyclone envelope only while enrollment is active.
/// Manual export remains available for legacy sessions through FIT/TCX decode
/// or summary fallback.
final class CycloneRideExportHandler: RideExportHandling {
    static let shared = CycloneRideExportHandler()
    private let service: CycloneService

    init(service: CycloneService = .shared) {
        self.service = service
    }

    func handleFinishedRide(
        session: WorkoutSession,
        samples: [BikeDataSample],
        heartRateSamples: [RideHeartRateSample],
        timerSegments: [RideTimerSegment],
        locations: [CLLocation],
        totalCalories: Int?
    ) {
        guard service.isConnected else { return }
        let envelope = CycloneEnvelopeBuilder.live(
            session: session,
            samples: samples,
            heartRateSamples: heartRateSamples,
            locations: locations
        )
        session.cycloneExportData = CycloneEnvelopeBuilder.compressed(envelope)
        try? session.modelContext?.save()
    }
}
