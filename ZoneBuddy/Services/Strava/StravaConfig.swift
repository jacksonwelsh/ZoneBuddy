import Foundation

/// Static configuration for the Strava integration.
///
/// The OAuth **client secret** is deliberately absent: it lives only in the
/// server-side proxy (`jacksonwel.sh/zonebuddy/strava`). The app drives the
/// authorize step and holds tokens, but every exchange that needs the secret
/// (initial code → token, and refresh) is proxied.
enum StravaConfig {
    /// Strava API application client id. Public by design (it appears in the
    /// authorize URL). Replace with the real id from the Strava API settings.
    static let clientID = "259934"

    /// OAuth scopes: `read` for the athlete profile, `activity:write` to upload.
    static let scopes = "read,activity:write"

    /// Strava's user-facing authorize endpoint.
    static let authorizeURL = URL(string: "https://www.strava.com/oauth/authorize")!

    /// Strava REST API base.
    static let apiBaseURL = URL(string: "https://www.strava.com/api/v3")!

    /// The proxy base on the personal site.
    static let proxyBaseURL = URL(string: "https://jacksonwel.sh/zonebuddy/strava")!

    /// Where Strava redirects after authorize — the proxy's callback, which then
    /// bounces to the app's custom scheme. Must match the Strava app's
    /// "Authorization Callback Domain" (`jacksonwel.sh`).
    static let redirectURI = "https://jacksonwel.sh/zonebuddy/strava/callback"

    /// Custom URL scheme ASWebAuthenticationSession watches for to capture the
    /// final redirect. Registered in Info.plist.
    static let callbackScheme = "zonebuddy"

    /// Proxy endpoint that refreshes an access token using the secret.
    static var refreshURL: URL { proxyBaseURL.appendingPathComponent("refresh") }

    /// Public web URL for a Strava activity, used by the "View on Strava" link.
    static func activityURL(id: Int) -> URL {
        URL(string: "https://www.strava.com/activities/\(id)")!
    }
}
