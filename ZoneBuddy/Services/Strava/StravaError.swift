import Foundation

/// Errors surfaced by the Strava token + upload services. `userMessage` is what
/// the history detail screen shows next to a failed upload.
enum StravaError: Error, Equatable {
    /// No connected account.
    case notConnected
    /// The refresh token was rejected — the user must reconnect.
    case needsReconnect
    /// A non-success HTTP status from Strava or the proxy.
    case httpStatus(Int)
    /// Strava accepted the file but failed to process it into an activity.
    case processingFailed(String)
    /// Upload processing didn't finish within the poll budget.
    case timedOut
    /// Unexpected/unparseable response.
    case invalidResponse
    /// The session has no stored TCX (e.g. a ride from before the integration).
    case noRideData

    var userMessage: String {
        switch self {
        case .notConnected: return "Connect your Strava account in Settings."
        case .needsReconnect: return "Strava sign-in expired. Reconnect in Settings."
        case .httpStatus(let code): return "Strava returned an error (\(code))."
        case .processingFailed(let reason): return reason
        case .timedOut: return "Strava took too long to process the ride. Try again."
        case .invalidResponse: return "Unexpected response from Strava."
        case .noRideData: return "This ride has no data available to upload."
        }
    }
}
