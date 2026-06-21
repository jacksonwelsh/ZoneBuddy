import Foundation
import Observation

/// The OAuth token bundle persisted for a connected Strava account.
struct StravaTokens: Codable, Equatable {
    var accessToken: String
    /// Strava rotates refresh tokens — always persist whatever a refresh returns.
    var refreshToken: String
    var expiresAt: Date
    var athleteID: Int?
    var athleteName: String?

    /// Treat the token as expired a few minutes early so an in-flight upload
    /// never races the hard expiry boundary.
    func isExpired(asOf now: Date = .now, buffer: TimeInterval = 300) -> Bool {
        now.addingTimeInterval(buffer) >= expiresAt
    }
}

/// Persists `StravaTokens` in the Keychain and exposes connection state to the
/// UI. `@Observable` so SwiftUI views (Settings, history detail) react to
/// connect/disconnect without manual notification plumbing.
@Observable
final class StravaTokenStore {
    static let shared = StravaTokenStore()

    private static let account = "tokens"

    private(set) var tokens: StravaTokens?

    var isConnected: Bool { tokens != nil }
    var athleteName: String? { tokens?.athleteName }

    init(loadFromKeychain: Bool = true) {
        guard loadFromKeychain,
              let data = KeychainStore.read(account: Self.account),
              let decoded = try? JSONDecoder().decode(StravaTokens.self, from: data)
        else { return }
        tokens = decoded
    }

    func store(_ tokens: StravaTokens) {
        self.tokens = tokens
        if let data = try? JSONEncoder().encode(tokens) {
            KeychainStore.save(data, account: Self.account)
        }
    }

    /// Apply a refreshed access/refresh/expiry triple while preserving athlete
    /// identity (the refresh response doesn't echo the athlete).
    func updateAfterRefresh(accessToken: String, refreshToken: String, expiresAt: Date) {
        guard var current = tokens else { return }
        current.accessToken = accessToken
        current.refreshToken = refreshToken
        current.expiresAt = expiresAt
        store(current)
    }

    func clear() {
        tokens = nil
        KeychainStore.delete(account: Self.account)
    }
}
