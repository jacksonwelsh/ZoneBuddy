import Testing
import Foundation
@testable import ZoneBuddy

@Suite(.serialized)
struct StravaUploaderTests {
    private struct FakeTokenProvider: StravaTokenProviding {
        func validAccessToken() async throws -> String { "test-token" }
    }

    private let apiBase = URL(string: "https://api.example.com")!

    private func makeUploader() -> StravaUploader {
        StravaUploader(
            tokenProvider: FakeTokenProvider(),
            session: StubURLProtocol.makeSession(),
            apiBaseURL: apiBase,
            pollInterval: .zero,
            maxPolls: 5
        )
    }

    private func request(virtual: Bool = false) -> StravaUploadRequest {
        StravaUploadRequest(
            tcx: Data("<tcx/>".utf8),
            name: "Morning Ride",
            description: "Recorded with ZoneBuddy",
            externalID: "abc-123",
            isVirtual: virtual
        )
    }

    @Test
    func uploadsThenPollsForActivityID() async throws {
        StubURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            if request.httpMethod == "POST", url.hasSuffix("/uploads") {
                // Queued: no activity_id yet.
                return try StubURLProtocol.jsonResponse(for: request, ["id": 999, "status": "processing"])
            }
            if url.hasSuffix("/uploads/999") {
                return try StubURLProtocol.jsonResponse(for: request, ["id": 999, "activity_id": 424242])
            }
            throw URLError(.unsupportedURL)
        }

        let activityID = try await makeUploader().upload(request())
        #expect(activityID == 424242)
    }

    @Test
    func resolvesImmediatelyWhenActivityReturnedOnPost() async throws {
        StubURLProtocol.handler = { request in
            try StubURLProtocol.jsonResponse(for: request, ["id": 1, "activity_id": 777])
        }
        let activityID = try await makeUploader().upload(request())
        #expect(activityID == 777)
    }

    @Test
    func treatsDuplicateAsSuccess() async throws {
        StubURLProtocol.handler = { request in
            try StubURLProtocol.jsonResponse(for: request, [
                "id": 2,
                "error": "duplicate of activity 555",
            ])
        }
        let activityID = try await makeUploader().upload(request())
        #expect(activityID == 555)
    }

    @Test
    func virtualRidesIssueSportTypePut() async throws {
        var sawVirtualPut = false
        StubURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            if request.httpMethod == "POST", url.hasSuffix("/uploads") {
                return try StubURLProtocol.jsonResponse(for: request, ["id": 3, "activity_id": 888])
            }
            if request.httpMethod == "PUT", url.hasSuffix("/activities/888") {
                sawVirtualPut = true
                return try StubURLProtocol.jsonResponse(for: request, ["id": 888])
            }
            throw URLError(.unsupportedURL)
        }
        let activityID = try await makeUploader().upload(request(virtual: true))
        #expect(activityID == 888)
        #expect(sawVirtualPut)
    }

    @Test
    func processingErrorThrows() async {
        StubURLProtocol.handler = { request in
            try StubURLProtocol.jsonResponse(for: request, [
                "id": 4,
                "error": "Empty file uploaded",
            ])
        }
        await #expect(throws: StravaError.processingFailed("Empty file uploaded")) {
            try await makeUploader().upload(request())
        }
    }

    @Test
    func parsesDuplicateActivityID() {
        #expect(StravaUploader.duplicateActivityID(in: "duplicate of activity 1234567") == 1234567)
        #expect(StravaUploader.duplicateActivityID(in: "There was an error: duplicate of <1234>") == 1234)
        #expect(StravaUploader.duplicateActivityID(in: "some other error") == nil)
    }
}
