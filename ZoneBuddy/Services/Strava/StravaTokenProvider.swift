import Foundation

/// Supplies a currently-valid Strava access token, refreshing through the proxy
/// when the stored one is near expiry. Injected into the uploader so upload code
/// never deals with token lifetime directly.
protocol StravaTokenProviding {
    func validAccessToken() async throws -> String
}

/// Live provider backed by `StravaTokenStore` + the server-side refresh proxy.
final class StravaTokenProvider: StravaTokenProviding {
    private let store: StravaTokenStore
    private let session: URLSession
    private let refreshURL: URL

    init(
        store: StravaTokenStore = .shared,
        session: URLSession = .shared,
        refreshURL: URL = StravaConfig.refreshURL
    ) {
        self.store = store
        self.session = session
        self.refreshURL = refreshURL
    }

    func validAccessToken() async throws -> String {
        guard let tokens = store.tokens else { throw StravaError.notConnected }
        if !tokens.isExpired() {
            return tokens.accessToken
        }
        return try await refresh(using: tokens.refreshToken)
    }

    private struct RefreshResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_at: Double
    }

    private func refresh(using refreshToken: String) async throws -> String {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StravaError.invalidResponse }

        // 400/401 from the proxy means Strava rejected the refresh token —
        // it's revoked or stale. Clear local state and ask for a reconnect.
        if http.statusCode == 400 || http.statusCode == 401 {
            store.clear()
            throw StravaError.needsReconnect
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StravaError.httpStatus(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw StravaError.invalidResponse
        }
        let expiresAt = Date(timeIntervalSince1970: decoded.expires_at)
        store.updateAfterRefresh(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: expiresAt
        )
        return decoded.access_token
    }
}
