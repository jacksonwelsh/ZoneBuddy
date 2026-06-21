import Foundation

/// Pure decisions about *which* sessions go to Strava and *how* they're tagged.
/// Kept free of side effects so the rules are unit-testable in isolation.
enum StravaUploadPolicy {
    /// Whether a freshly finished session should upload automatically.
    ///
    /// Auto-upload is opt-in (`autoUploadEnabled`). FTP tests are excluded by
    /// default — most riders don't want a test on their feed — but can be opted
    /// back in. The manual "Upload to Strava" button on the history detail
    /// screen is always available regardless of this decision.
    static func shouldAutoUpload(
        modality: SessionModality,
        autoUploadEnabled: Bool,
        includeFTPTests: Bool
    ) -> Bool {
        guard autoUploadEnabled else { return false }
        if case .ftpTest = modality { return includeFTPTests }
        return true
    }

    /// Route rides become Strava `VirtualRide`s (with a GPS map, Zwift-style).
    /// Everything else is a trainer `Ride`.
    static func isVirtualRide(_ modality: SessionModality) -> Bool {
        if case .routeRide = modality { return true }
        return false
    }
}
