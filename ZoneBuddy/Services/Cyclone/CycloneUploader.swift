import Foundation

protocol CycloneUploading {
    func enroll(serverURL: URL, code: String, deviceName: String) async throws -> CycloneCredential
    func importDraft(_ envelope: CycloneExportEnvelope, credential: CycloneCredential) async throws -> UUID
}

struct CycloneUploader: CycloneUploading {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func enroll(serverURL: URL, code: String, deviceName: String) async throws -> CycloneCredential {
        struct Body: Encodable { let code: String; let deviceName: String }
        struct Response: Decodable { let token: String; let deviceId: UUID }
        let response: Response = try await send(
            to: serverURL.appending(path: "auth/enroll"),
            method: "POST",
            body: Body(code: code, deviceName: deviceName),
            token: nil
        )
        return CycloneCredential(serverURL: serverURL, token: response.token, deviceID: response.deviceId)
    }

    func importDraft(_ envelope: CycloneExportEnvelope, credential: CycloneCredential) async throws -> UUID {
        struct Response: Decodable { let id: UUID }
        let response: Response = try await send(
            to: credential.serverURL.appending(path: "manage/imports"),
            method: "POST",
            body: envelope,
            token: credential.token
        )
        return response.id
    }

    private func send<Response: Decodable, Body: Encodable>(
        to url: URL,
        method: String,
        body: Body,
        token: String?
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try Self.encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CycloneError.invalidResponse }
        if http.statusCode == 401 { throw CycloneError.notConnected }
        guard (200..<300).contains(http.statusCode) else { throw CycloneError.httpStatus(http.statusCode) }
        guard let decoded = try? Self.decoder.decode(Response.self, from: data) else { throw CycloneError.invalidResponse }
        return decoded
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.keyEncodingStrategy = .convertToSnakeCase
        value.dateEncodingStrategy = .iso8601
        return value
    }()
    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.keyDecodingStrategy = .convertFromSnakeCase
        return value
    }()
}

enum CycloneError: Error, Equatable {
    case notConnected
    case noRideData
    case invalidServer
    case invalidResponse
    case httpStatus(Int)

    var userMessage: String {
        switch self {
        case .notConnected: "Enroll Cyclone in Settings."
        case .noRideData: "This ride does not contain enough data to export."
        case .invalidServer: "Enter the full Cyclone /v1 server URL."
        case .invalidResponse: "Cyclone returned an unexpected response."
        case .httpStatus(let status): "Cyclone returned an error (\(status))."
        }
    }
}
