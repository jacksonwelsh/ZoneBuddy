import Testing
import Foundation
@testable import ZoneBuddy

@Suite(.serialized)
struct StravaTokenProviderTests {
    private let refreshURL = URL(string: "https://example.com/refresh")!

    private func makeStore(_ tokens: StravaTokens) -> StravaTokenStore {
        // loadFromKeychain: false keeps the test off any persisted state; the
        // provider reads the in-memory `tokens`, so Keychain side effects don't
        // affect the assertions.
        let store = StravaTokenStore(loadFromKeychain: false)
        store.store(tokens)
        return store
    }

    @Test
    func returnsStoredTokenWhenStillValid() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.badServerResponse) } // must not be called
        let store = makeStore(StravaTokens(
            accessToken: "valid", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600)))
        let provider = StravaTokenProvider(store: store, session: StubURLProtocol.makeSession(), refreshURL: refreshURL)

        let token = try await provider.validAccessToken()
        #expect(token == "valid")
    }

    @Test
    func refreshesExpiredTokenAndPersistsRotatedRefreshToken() async throws {
        let newExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970
        StubURLProtocol.handler = { request in
            try StubURLProtocol.jsonResponse(for: request, [
                "access_token": "fresh",
                "refresh_token": "rotated",
                "expires_at": newExpiry,
            ])
        }
        let store = makeStore(StravaTokens(
            accessToken: "stale", refreshToken: "r1", expiresAt: Date().addingTimeInterval(-10)))
        let provider = StravaTokenProvider(store: store, session: StubURLProtocol.makeSession(), refreshURL: refreshURL)

        let token = try await provider.validAccessToken()
        #expect(token == "fresh")
        #expect(store.tokens?.refreshToken == "rotated")
    }

    @Test
    func rejectedRefreshClearsTokensAndSignalsReconnect() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        let store = makeStore(StravaTokens(
            accessToken: "stale", refreshToken: "r1", expiresAt: Date().addingTimeInterval(-10)))
        let provider = StravaTokenProvider(store: store, session: StubURLProtocol.makeSession(), refreshURL: refreshURL)

        await #expect(throws: StravaError.needsReconnect) {
            try await provider.validAccessToken()
        }
        #expect(store.tokens == nil)
    }

    @Test
    func throwsWhenNotConnected() async {
        let store = StravaTokenStore(loadFromKeychain: false)
        let provider = StravaTokenProvider(store: store, session: StubURLProtocol.makeSession(), refreshURL: refreshURL)
        await #expect(throws: StravaError.notConnected) {
            try await provider.validAccessToken()
        }
    }
}
