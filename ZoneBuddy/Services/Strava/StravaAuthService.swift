import Foundation
import AuthenticationServices
import UIKit

/// Runs the Strava OAuth authorize step and persists the resulting tokens.
protocol StravaAuthenticating {
    func connect() async throws
    func disconnect()
}

/// Live implementation backed by `ASWebAuthenticationSession`.
///
/// Flow: open Strava's authorize page → user approves → Strava redirects to the
/// proxy callback → proxy exchanges the code (using the secret) and 302s to
/// `zonebuddy://strava/connected#…` → this session captures that URL and reads
/// the tokens from its fragment. The `state` value is generated here and
/// verified on return to defend against forged callbacks.
final class StravaAuthService: NSObject, StravaAuthenticating {
    static let shared = StravaAuthService()

    private let store: StravaTokenStore
    /// Retained for the lifetime of the authorization so it isn't deallocated
    /// mid-flight while we await the callback.
    private var currentSession: ASWebAuthenticationSession?

    init(store: StravaTokenStore = .shared) {
        self.store = store
        super.init()
    }

    func connect() async throws {
        let state = UUID().uuidString
        var components = URLComponents(url: StravaConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: StravaConfig.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = components.url else { throw StravaError.invalidResponse }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: StravaConfig.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? StravaError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            if !session.start() {
                continuation.resume(throwing: StravaError.invalidResponse)
            }
        }
        currentSession = nil
        try handleCallback(callbackURL, expectedState: state)
    }

    func disconnect() {
        store.clear()
    }

    /// Parse the `zonebuddy://…#…` fragment into tokens and persist them.
    private func handleCallback(_ url: URL, expectedState: String) throws {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            throw StravaError.invalidResponse
        }
        var parser = URLComponents()
        parser.percentEncodedQuery = fragment
        var params: [String: String] = [:]
        for item in parser.queryItems ?? [] {
            params[item.name] = item.value
        }

        // Reject a callback whose state doesn't match the request we started.
        guard params["state"] == expectedState else { throw StravaError.invalidResponse }

        if let error = params["error"], !error.isEmpty {
            throw StravaError.processingFailed("Strava authorization failed (\(error)).")
        }
        guard let access = params["access_token"],
              let refresh = params["refresh_token"],
              let expiresStr = params["expires_at"],
              let expiresSeconds = Double(expiresStr)
        else { throw StravaError.invalidResponse }

        // URLSearchParams encodes spaces as "+"; restore them in the name.
        let athleteName = params["athlete_name"]?.replacingOccurrences(of: "+", with: " ")
        let tokens = StravaTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: expiresSeconds),
            athleteID: params["athlete_id"].flatMap { Int($0) },
            athleteName: athleteName
        )
        store.store(tokens)
    }
}

extension StravaAuthService: ASWebAuthenticationPresentationContextProviding {
    // AuthenticationServices invokes this on the main thread. Marked
    // `nonisolated` so it witnesses the protocol requirement regardless of how
    // the SDK annotates it under this project's default-MainActor isolation;
    // `assumeIsolated` is safe given the documented main-thread call.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
