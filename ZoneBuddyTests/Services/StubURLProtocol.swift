import Foundation

/// A `URLProtocol` that intercepts requests in tests and returns canned
/// responses, so the Strava networking code can be driven without hitting the
/// real API. Suites using it must be `.serialized` — the handler is a shared
/// static, so concurrent tests would race on it.
///
/// Overrides are `nonisolated`: `URLProtocol` invokes them off the main actor,
/// and the project's default-MainActor isolation would otherwise mis-annotate
/// them.
final class StubURLProtocol: URLProtocol {
    /// Inspect the request and return the `(response, body)` to deliver, or
    /// throw to simulate a transport failure.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }

    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override nonisolated func startLoading() {
        guard let handler = StubURLProtocol.handler else {
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

    /// A `URLSession` wired to use this stub protocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Convenience: a 200 response carrying a JSON object body.
    static func jsonResponse(for request: URLRequest, _ object: [String: Any], status: Int = 200) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, data)
    }
}
