import CoreLocation
import Foundation

final class RideExportCoordinator: RideExportHandling {
    static let shared = RideExportCoordinator(handlers: [
        StravaRideExportHandler.shared,
        CycloneRideExportHandler.shared,
    ])

    private let handlers: [RideExportHandling]

    init(handlers: [RideExportHandling]) {
        self.handlers = handlers
    }

    func handleFinishedRide(
        session: WorkoutSession,
        samples: [BikeDataSample],
        heartRateSamples: [RideHeartRateSample],
        timerSegments: [RideTimerSegment],
        locations: [CLLocation],
        totalCalories: Int?
    ) {
        for handler in handlers {
            handler.handleFinishedRide(
                session: session,
                samples: samples,
                heartRateSamples: heartRateSamples,
                timerSegments: timerSegments,
                locations: locations,
                totalCalories: totalCalories
            )
        }
    }
}
