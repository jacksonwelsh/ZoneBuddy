import CoreLocation
import Foundation
import Testing
@testable import ZoneBuddy

@Suite(.serialized)
@MainActor
struct CycloneExportTests {
    private let activityID = UUID(uuidString: "018f7798-1234-7abc-8123-123456789abc")!

    @Test
    func liveRouteRideRetainsCanonicalStreamsAndVirtualRoute() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSession(
            name: "Alpine loop",
            completedAt: start.addingTimeInterval(60),
            totalDuration: 60,
            avgPower: 180,
            maxPower: 260,
            totalDistance: 600,
            modality: .routeRide(routeID: UUID(), routeName: "Alpine", totalElevationGainMeters: 50)
        )
        let samples = [
            BikeDataSample(timestamp: start, power: 150, cadence: 80, heartRate: 120, speed: 36, distance: 0, calories: 0),
            BikeDataSample(timestamp: start.addingTimeInterval(1), power: 210, cadence: 90, heartRate: 130, speed: 18, distance: 10, calories: 1),
        ]
        let route = [
            CLLocation(coordinate: .init(latitude: 37, longitude: -122), altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start),
            CLLocation(coordinate: .init(latitude: 37.001, longitude: -122.001), altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start.addingTimeInterval(1)),
        ]

        let envelope = CycloneEnvelopeBuilder.live(session: session, samples: samples, heartRateSamples: [], locations: route)

        #expect(envelope.source.id == session.id.uuidString)
        #expect(envelope.type == "indoor_ride")
        #expect(envelope.virtual)
        #expect(envelope.route.count == 2)
        #expect(envelope.streams.first(where: { $0.metric == "speed" })?.samples[0][1] == 10)
        let retained = try #require(CycloneEnvelopeBuilder.compressed(envelope))
        session.cycloneExportData = retained
        #expect(CycloneEnvelopeBuilder.retainedOrLegacy(session: session) == envelope)
    }

    @Test
    func uploaderUsesV1ImportContractAndOmitsMissingMetrics() async throws {
        let credential = credential()
        let session = WorkoutSession(name: "Recovery", totalDuration: 900)
        let envelope = try #require(CycloneEnvelopeBuilder.retainedOrLegacy(session: session))
        CycloneURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://cyclone.example/v1/manage/imports")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            let data = try CycloneURLProtocol.bodyData(for: request)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let source = try #require(object["source"] as? [String: Any])
            let metrics = try #require(object["metrics"] as? [String: Any])
            #expect(source["namespace"] as? String == "zonebuddy")
            #expect(source["id"] as? String == session.id.uuidString)
            #expect(metrics["duration_seconds"] as? Int == 900)
            #expect(metrics["maximum_speed_mps"] == nil)
            #expect(!data.contains(Data("null".utf8)))
            return try CycloneURLProtocol.jsonResponse(for: request, ["id": self.activityID.uuidString], status: 201)
        }

        let uploader = CycloneUploader(session: CycloneURLProtocol.makeSession())
        #expect(try await uploader.importDraft(envelope, credential: credential) == activityID)
    }

    @Test
    func exportRetriesSameSourceAndOpensExistingDraft() async {
        let uploader = FakeCycloneUploader(activityID: activityID)
        let store = CycloneCredentialStore(loadFromKeychain: false, credential: credential())
        var opened: [URL] = []
        let service = CycloneService(credentialStore: store, uploader: uploader) { url in
            opened.append(url)
            return true
        }
        let session = WorkoutSession(name: "Intervals", totalDuration: 1200)

        await service.export(session)
        await service.export(session)

        #expect(session.cycloneExportState == .exported)
        #expect(session.cycloneActivityID == activityID)
        #expect(uploader.sourceIDs == [session.id.uuidString, session.id.uuidString])
        #expect(opened == [
            URL(string: "cyclone://activities/018f7798-1234-7abc-8123-123456789abc")!,
            URL(string: "cyclone://activities/018f7798-1234-7abc-8123-123456789abc")!,
        ])
    }

    @Test
    func exportReplacesDeletedDraftWithNewActivity() async {
        let replacementID = UUID(uuidString: "018f7798-1234-7abc-8123-123456789abd")!
        let uploader = FakeCycloneUploader(activityIDs: [activityID, replacementID])
        let store = CycloneCredentialStore(loadFromKeychain: false, credential: credential())
        let service = CycloneService(credentialStore: store, uploader: uploader)
        let session = WorkoutSession(name: "Intervals", totalDuration: 1200)

        await service.export(session)
        await service.export(session)

        #expect(session.cycloneExportState == .exported)
        #expect(session.cycloneActivityID == replacementID)
        #expect(uploader.sourceIDs == [session.id.uuidString, session.id.uuidString])
    }

    @Test
    func enrollmentNormalizesServerToV1() async throws {
        let uploader = FakeCycloneUploader(activityID: activityID)
        let store = CycloneCredentialStore(loadFromKeychain: false)
        let service = CycloneService(credentialStore: store, uploader: uploader)

        try await service.enroll(server: "https://cyclone.example", code: "one-time", deviceName: "Phone")

        #expect(uploader.enrollmentURL == URL(string: "https://cyclone.example/v1/"))
        #expect(service.isConnected)
        await #expect(throws: CycloneError.invalidServer) {
            try await service.enroll(server: "ftp://localhost", code: "one-time", deviceName: "Phone")
        }
    }

    private func credential() -> CycloneCredential {
        CycloneCredential(
            serverURL: URL(string: "https://cyclone.example/v1/")!,
            token: "secret",
            deviceID: UUID()
        )
    }
}

private final class CycloneURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override nonisolated func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override nonisolated func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CycloneURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func bodyData(for request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static func jsonResponse(for request: URLRequest, _ object: [String: Any], status: Int) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, try JSONSerialization.data(withJSONObject: object))
    }
}

@MainActor
private final class FakeCycloneUploader: CycloneUploading {
    private var activityIDs: [UUID]
    private(set) var sourceIDs: [String] = []
    private(set) var enrollmentURL: URL?

    convenience init(activityID: UUID) { self.init(activityIDs: [activityID]) }

    init(activityIDs: [UUID]) { self.activityIDs = activityIDs }

    func enroll(serverURL: URL, code: String, deviceName: String) async throws -> CycloneCredential {
        enrollmentURL = serverURL
        return CycloneCredential(serverURL: serverURL, token: "enrolled", deviceID: UUID())
    }

    func importDraft(_ envelope: CycloneExportEnvelope, credential: CycloneCredential) async throws -> UUID {
        sourceIDs.append(envelope.source.id)
        guard !activityIDs.isEmpty else { throw CycloneError.invalidResponse }
        if activityIDs.count == 1 { return activityIDs[0] }
        return activityIDs.removeFirst()
    }
}
