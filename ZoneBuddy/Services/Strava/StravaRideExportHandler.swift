import Foundation
import CoreLocation
import SwiftData

/// Live `RideExportHandling`: captures a finished ride as a Strava TCX and
/// kicks off an automatic upload when enabled. Injected into the workout player
/// on iOS only.
final class StravaRideExportHandler: RideExportHandling {
    static let shared = StravaRideExportHandler()

    private let service: StravaService
    private let settings: SettingsManager

    init(service: StravaService = .shared, settings: SettingsManager = .shared) {
        self.service = service
        self.settings = settings
    }

    func handleFinishedRide(
        session: WorkoutSession,
        samples: [BikeDataSample],
        locations: [CLLocation],
        totalCalories: Int?
    ) {
        // Only capture/upload for a connected account. A ride finished while
        // disconnected can't be uploaded later anyway (no stored TCX to rebuild
        // from), so skipping the blob keeps the store lean for non-Strava users.
        guard service.isConnected else { return }

        session.stravaTCXData = TCXBuilder.makeTCX(
            samples: samples,
            locations: locations,
            totalCalories: totalCalories
        )
        try? session.modelContext?.save()

        if StravaUploadPolicy.shouldAutoUpload(
            modality: session.modality,
            autoUploadEnabled: settings.stravaAutoUpload,
            includeFTPTests: settings.stravaAutoUploadIncludesFTPTests
        ) {
            Task { await service.upload(session) }
        }
    }
}
