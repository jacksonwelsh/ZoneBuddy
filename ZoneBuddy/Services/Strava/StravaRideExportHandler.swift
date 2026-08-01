import Foundation
import CoreLocation
import SwiftData

/// Live `RideExportHandling`: captures structured indoor rides as FIT (the
/// richest Strava format) and other rides as TCX, then kicks off auto-upload.
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
        heartRateSamples: [RideHeartRateSample],
        timerSegments: [RideTimerSegment],
        locations: [CLLocation],
        totalCalories: Int?
    ) {
        // FIT is compact, so retain structured rides even if Strava is not yet
        // connected. Connecting later can then upload the real watt/HR/cadence
        // streams instead of a coarse reconstruction. Keep the much larger TCX
        // capture for other modalities limited to connected Strava users.
        let isStructured: Bool = {
            if case .structured = session.modality { return true }
            return false
        }()
        guard isStructured || service.isConnected else { return }

        if isStructured {
            let intervalSnapshots = (session.intervals ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { FITBuilder.WorkoutInterval(zone: $0.zone, duration: $0.duration) }
            session.stravaFITData = try? FITBuilder.makeFIT(
                samples: samples,
                heartRateSamples: heartRateSamples,
                timerSegments: timerSegments,
                intervals: intervalSnapshots,
                totalDuration: session.totalDuration,
                totalCalories: totalCalories,
                serialNumber: Self.serialNumber(for: session.id)
            )
        }

        // Keep TCX for route rides (where it carries the simulated GPS map),
        // free rides, FTP tests, and as a safety fallback if FIT encoding fails.
        if session.stravaFITData == nil {
            session.stravaTCXData = TCXBuilder.makeTCX(
                samples: samples,
                locations: locations,
                totalCalories: totalCalories
            )
        }
        try? session.modelContext?.save()

        if StravaUploadPolicy.shouldAutoUpload(
            modality: session.modality,
            autoUploadEnabled: settings.stravaAutoUpload,
            includeFTPTests: settings.stravaAutoUploadIncludesFTPTests
        ), service.isConnected {
            Task { await service.upload(session) }
        }
    }

    private static func serialNumber(for id: UUID) -> UInt32 {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return bytes.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
