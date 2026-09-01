import Foundation
import Observation
import SwiftData
import UIKit

@Observable
final class CycloneService {
    static let shared = CycloneService(
        credentialStore: .shared,
        uploader: CycloneUploader(),
        openURL: { await UIApplication.shared.open($0) }
    )

    private let credentialStore: CycloneCredentialStore
    private let uploader: CycloneUploading
    private let openURL: (URL) async -> Bool

    init(
        credentialStore: CycloneCredentialStore,
        uploader: CycloneUploading,
        openURL: @escaping (URL) async -> Bool = { _ in true }
    ) {
        self.credentialStore = credentialStore
        self.uploader = uploader
        self.openURL = openURL
    }

    var isConnected: Bool { credentialStore.isConnected }
    var serverName: String? { credentialStore.credential?.serverURL.host }

    func enroll(server: String, code: String, deviceName: String) async throws {
        guard var components = URLComponents(string: server),
              components.scheme == "https" || (components.scheme == "http" && components.host == "localhost") else {
            throw CycloneError.invalidServer
        }
        let pathComponents = components.path.split(separator: "/").joined(separator: "/")
        let basePath = pathComponents.isEmpty ? "" : "/" + pathComponents
        components.path = basePath.hasSuffix("/v1") ? basePath + "/" : basePath + "/v1/"
        guard let url = components.url else { throw CycloneError.invalidServer }
        credentialStore.store(try await uploader.enroll(serverURL: url, code: code, deviceName: deviceName))
    }

    func disconnect() { credentialStore.clear() }

    /// Creates or finds the same private draft on every retry. The activity ID
    /// is persisted before opening Cyclone, so switching apps cannot lose it.
    func export(_ session: WorkoutSession) async {
        guard let credential = credentialStore.credential else {
            mark(session, state: .failed, error: CycloneError.notConnected.userMessage)
            return
        }
        guard let envelope = CycloneEnvelopeBuilder.retainedOrLegacy(session: session) else {
            mark(session, state: .failed, error: CycloneError.noRideData.userMessage)
            return
        }

        mark(session, state: .exporting, error: nil)
        do {
            let activityID = try await uploader.importDraft(envelope, credential: credential)
            session.cycloneActivityID = activityID
            mark(session, state: .exported, error: nil)
            if let url = URL(string: "cyclone://activities/\(activityID.uuidString.lowercased())") {
                _ = await openURL(url)
            }
        } catch let error as CycloneError {
            mark(session, state: .failed, error: error.userMessage)
        } catch {
            mark(session, state: .failed, error: error.localizedDescription)
        }
    }

    func openDraft(_ id: UUID) async {
        guard let url = URL(string: "cyclone://activities/\(id.uuidString.lowercased())") else { return }
        _ = await openURL(url)
    }

    private func mark(_ session: WorkoutSession, state: CycloneExportState, error: String?) {
        session.cycloneExportState = state
        session.cycloneExportError = error
        try? session.modelContext?.save()
    }
}
