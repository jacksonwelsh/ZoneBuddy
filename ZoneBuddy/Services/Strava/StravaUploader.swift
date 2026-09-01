import Foundation

enum StravaUploadFormat: String {
    case fit
    case tcx

    var fileExtension: String { rawValue }
}

/// Parameters describing one ride to push to Strava.
struct StravaUploadRequest {
    let fileData: Data
    let format: StravaUploadFormat
    let name: String
    let description: String?
    /// Session UUID string. Sent as Strava's `external_id` so retries dedupe to
    /// the same activity instead of creating duplicates.
    let externalID: String
}

/// Uploads a finished ride file to Strava and returns the created activity id.
protocol StravaUploading {
    func upload(_ request: StravaUploadRequest) async throws -> Int
}

/// Live uploader: `POST /uploads` (multipart) with `sport_type=VirtualRide` →
/// poll `GET /uploads/{id}` until Strava finishes processing. Authorization
/// tokens come from the injected `StravaTokenProviding`; the `URLSession` and
/// poll cadence are injectable so the whole flow is testable against a stubbed
/// `URLProtocol`.
final class StravaUploader: StravaUploading {
    private let tokenProvider: StravaTokenProviding
    private let session: URLSession
    private let apiBaseURL: URL
    private let pollInterval: Duration
    private let maxPolls: Int

    init(
        tokenProvider: StravaTokenProviding,
        session: URLSession = .shared,
        apiBaseURL: URL = StravaConfig.apiBaseURL,
        pollInterval: Duration = .seconds(2),
        maxPolls: Int = 30
    ) {
        self.tokenProvider = tokenProvider
        self.session = session
        self.apiBaseURL = apiBaseURL
        self.pollInterval = pollInterval
        self.maxPolls = maxPolls
    }

    func upload(_ request: StravaUploadRequest) async throws -> Int {
        let token = try await tokenProvider.validAccessToken()
        switch try await postUpload(request, token: token) {
        case .resolved(let id):
            // Strava resolved (or deduped) on the first response.
            return id
        case .pending(let uploadID):
            return try await pollForActivity(uploadID: uploadID, token: token)
        }
    }

    /// Outcome of the initial upload POST: either Strava already resolved the
    /// activity (or deduped it), or it queued processing under an upload id.
    private enum UploadOutcome {
        case resolved(Int)
        case pending(uploadID: Int)
    }

    // MARK: - POST /uploads

    private struct UploadResponse: Decodable {
        let id: Int
        let error: String?
        let activity_id: Int?
        let status: String?
    }

    private func postUpload(_ request: StravaUploadRequest, token: String) async throws -> UploadOutcome {
        let boundary = "ZoneBuddyBoundary-\(request.externalID)"
        var urlRequest = URLRequest(url: apiBaseURL.appendingPathComponent("uploads"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields: [String: String] = [
            "data_type": request.format.rawValue,
            "name": request.name,
            "external_id": request.externalID,
            // All ZoneBuddy rides come from an indoor smart trainer.
            "trainer": "1",
            "sport_type": "VirtualRide",
        ]
        if let description = request.description {
            fields["description"] = description
        }

        urlRequest.httpBody = multipartBody(
            boundary: boundary,
            fields: fields,
            fileField: "file",
            fileName: "\(request.externalID).\(request.format.fileExtension)",
            fileData: request.fileData,
            fileContentType: "application/octet-stream"
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw StravaError.invalidResponse }
        if http.statusCode == 401 { throw StravaError.needsReconnect }
        guard (200..<300).contains(http.statusCode) else { throw StravaError.httpStatus(http.statusCode) }

        guard let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
            throw StravaError.invalidResponse
        }
        if let activityID = try resolveImmediate(decoded) {
            // Strava occasionally resolves (or rejects as duplicate) on the
            // first response; short-circuit the poll loop.
            return .resolved(activityID)
        }
        return .pending(uploadID: decoded.id)
    }

    // MARK: - Poll GET /uploads/{id}

    private func pollForActivity(uploadID: Int, token: String) async throws -> Int {
        var attempts = 0
        while attempts < maxPolls {
            attempts += 1
            var request = URLRequest(url: apiBaseURL.appendingPathComponent("uploads/\(uploadID)"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw StravaError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw StravaError.httpStatus(http.statusCode) }
            guard let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
                throw StravaError.invalidResponse
            }
            if let activityID = try resolveImmediate(decoded) {
                return activityID
            }
            try await Task.sleep(for: pollInterval)
        }
        throw StravaError.timedOut
    }

    /// Inspect an upload-status payload: returns the activity id when ready,
    /// nil when still processing, or throws on a terminal error. A "duplicate"
    /// error is treated as success — the activity already exists, and its id is
    /// embedded in Strava's error string.
    private func resolveImmediate(_ response: UploadResponse) throws -> Int? {
        if let activityID = response.activity_id {
            return activityID
        }
        if let error = response.error, !error.isEmpty {
            if let duplicateID = Self.duplicateActivityID(in: error) {
                return duplicateID
            }
            throw StravaError.processingFailed(error)
        }
        return nil
    }

    /// Strava signals duplicates with messages like
    /// "duplicate of activity 1234567890". Pull the id back out so a re-upload
    /// of the same ride resolves to the existing activity rather than failing.
    static func duplicateActivityID(in error: String) -> Int? {
        guard error.lowercased().contains("duplicate") else { return nil }
        // The activity id is the last run of digits in the message.
        var digits = ""
        for ch in error.reversed() {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        guard !digits.isEmpty else { return nil }
        return Int(String(digits.reversed()))
    }

    // MARK: - Multipart

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        fileName: String,
        fileData: Data,
        fileContentType: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        // Deterministic field order keeps the body stable for testing.
        for key in fields.keys.sorted() {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(fields[key]!)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(fileContentType)\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }
}
