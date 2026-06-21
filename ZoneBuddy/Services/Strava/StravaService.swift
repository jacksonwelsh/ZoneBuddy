import Foundation
import Observation
import SwiftData

/// App-facing facade for Strava: connection state for the UI, plus a single
/// `upload(_:)` entry point that drives a session through its upload lifecycle
/// and records the result back onto the `WorkoutSession`.
///
/// `@Observable` so Settings and the history detail screen track connect/
/// disconnect and per-session upload state live.
@Observable
final class StravaService {
    static let shared = StravaService(
        tokenStore: .shared,
        auth: StravaAuthService.shared,
        uploader: StravaUploader(tokenProvider: StravaTokenProvider())
    )

    private let tokenStore: StravaTokenStore
    private let auth: StravaAuthenticating
    private let uploader: StravaUploading

    init(tokenStore: StravaTokenStore, auth: StravaAuthenticating, uploader: StravaUploading) {
        self.tokenStore = tokenStore
        self.auth = auth
        self.uploader = uploader
    }

    var isConnected: Bool { tokenStore.isConnected }
    var athleteName: String? { tokenStore.athleteName }

    func connect() async throws {
        try await auth.connect()
    }

    func disconnect() {
        auth.disconnect()
    }

    /// Upload (or retry) a finished session. Idempotent against Strava via the
    /// session's UUID `external_id`, so a retry after a partial failure resolves
    /// to the same activity rather than duplicating it. Writes `uploading` →
    /// `uploaded`/`failed` onto the session as it goes.
    func upload(_ session: WorkoutSession) async {
        guard isConnected else {
            mark(session, state: .failed, error: StravaError.notConnected.userMessage)
            return
        }
        // Use the TCX captured at finish time, or — for an older ride without one
        // — synthesize one from persisted summary data and keep it so a retry
        // doesn't rebuild it.
        guard let tcx = resolvedTCX(for: session) else {
            mark(session, state: .failed, error: StravaError.noRideData.userMessage)
            return
        }
        if session.stravaTCXData == nil {
            session.stravaTCXData = tcx
        }

        mark(session, state: .uploading, error: nil)

        let request = StravaUploadRequest(
            tcx: tcx,
            name: session.name,
            description: "Recorded with ZoneBuddy",
            externalID: session.id.uuidString,
            isVirtual: StravaUploadPolicy.isVirtualRide(session.modality)
        )

        do {
            let activityID = try await uploader.upload(request)
            session.stravaActivityID = activityID
            mark(session, state: .uploaded, error: nil)
        } catch let error as StravaError {
            mark(session, state: .failed, error: error.userMessage)
        } catch {
            mark(session, state: .failed, error: error.localizedDescription)
        }
    }

    /// The TCX to upload: the one captured at finish time if present, otherwise
    /// a synthesized one built from the session's persisted summary. Returns nil
    /// only when there's nothing to reconstruct from (a zero-duration row).
    private func resolvedTCX(for session: WorkoutSession) -> Data? {
        if let existing = session.stravaTCXData { return existing }
        guard session.totalDuration > 0 else { return nil }

        // True start time = completion minus elapsed duration, so Strava dates
        // the activity to when the ride actually happened.
        let startDate = session.completedAt.addingTimeInterval(-Double(session.totalDuration))

        // For a route ride whose source Route still exists, hand the geometry to
        // the builder so the synthesized activity regains its map.
        var routePoints: [RoutePoint]?
        if case .routeRide(let routeID, _, _) = session.modality,
           let routeID,
           let context = session.modelContext {
            let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeID })
            routePoints = (try? context.fetch(descriptor))?.first?.points
        }

        return TCXBuilder.makeSyntheticTCX(
            startDate: startDate,
            duration: session.totalDuration,
            avgPower: session.avgPower,
            avgHeartRate: session.avgHeartRate,
            totalDistanceMeters: session.totalDistance,
            totalCalories: session.totalCalories,
            routePoints: routePoints
        )
    }

    private func mark(_ session: WorkoutSession, state: StravaUploadState, error: String?) {
        session.stravaUploadState = state
        session.stravaUploadError = error
        try? session.modelContext?.save()
    }
}
