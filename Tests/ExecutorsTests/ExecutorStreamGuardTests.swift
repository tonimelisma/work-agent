import Foundation
import Testing
@testable import Executors

// REQ: a 200 response must not read as a silent empty reply, whether the body isn't
// SSE at all (wrong Content-Type) or is SSE-labeled but yields zero events.

private final class StreamStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let (status, headers, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Issues a real `bytes(for:)` call through a stub so `AsyncBytes` behaves like the
/// genuine article (chunking, `.lines`, etc.) without any network access.
private func stubbedBytes(
    status: Int = 200, headers: [String: String] = [:], body: String
) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
    StreamStubURLProtocol.handler = { _ in (status, headers, Data(body.utf8)) }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StreamStubURLProtocol.self]
    let session = URLSession(configuration: config)
    let (bytes, response) = try await session.bytes(for: URLRequest(url: URL(string: "https://example.test/stream")!))
    return (bytes, response as! HTTPURLResponse)
}

@Suite("Executor stream guards", .serialized)
struct ExecutorStreamGuardTests {
    @Test("A non-2xx response keeps the provider's error body in the diagnostic")
    func httpFailureKeepsErrorBody() async throws {
        let (bytes, response) = try await stubbedBytes(
            status: 429, body: #"{"error":{"message":"rate limited, retry in 30s"}}"#
        )
        await #expect(throws: LiveExecutorError.httpFailure(
            provider: "anthropic", status: 429,
            message: #"{"error":{"message":"rate limited, retry in 30s"}}"#
        )) {
            try await ExecutorRequestEncoding.validate(response: response, bytes: bytes, providerID: "anthropic")
        }
    }

    @Test("A 200 with a non-SSE Content-Type throws, carrying the body prefix")
    func nonSSEContentTypeThrows() async throws {
        let (bytes, response) = try await stubbedBytes(
            headers: ["Content-Type": "application/json"],
            body: #"{"error": "rate limited"}"#
        )
        await #expect(throws: ProviderStreamError.event(
            provider: "anthropic", type: "non_sse_response", message: #"{"error": "rate limited"}"#
        )) {
            try await ExecutorRequestEncoding.assertEventStream(response: response, bytes: bytes, providerID: "anthropic")
        }
    }

    @Test("A correctly-labeled SSE Content-Type passes the guard")
    func sseContentTypePasses() async throws {
        let (bytes, response) = try await stubbedBytes(
            headers: ["Content-Type": "text/event-stream"], body: "data: {}\n"
        )
        try await ExecutorRequestEncoding.assertEventStream(response: response, bytes: bytes, providerID: "anthropic")
    }

    @Test("A missing Content-Type is treated as non-SSE")
    func missingContentTypeThrows() async throws {
        let (bytes, response) = try await stubbedBytes(body: "whatever")
        await #expect(throws: ProviderStreamError.self) {
            try await ExecutorRequestEncoding.assertEventStream(response: response, bytes: bytes, providerID: "openai")
        }
    }

    @Test("A stream that parses zero events throws, even if labeled SSE")
    func zeroEventsThrows() async throws {
        let (bytes, _) = try await stubbedBytes(headers: ["Content-Type": "text/event-stream"], body: "\n\n\n")
        await #expect(throws: ProviderStreamError.event(
            provider: "anthropic", type: "non_sse_response", message: "empty stream"
        )) {
            try await ExecutorRequestEncoding.consumeEventStream(
                bytes: bytes, providerID: "anthropic",
                parseLine: { _, _ in [] },
                onEvent: { _ in }
            )
        }
    }

    @Test("A stream that parses at least one event does not throw")
    func atLeastOneEventPasses() async throws {
        let (bytes, _) = try await stubbedBytes(headers: ["Content-Type": "text/event-stream"], body: "data: hi\n")
        var received: [ExecutorEvent] = []
        try await ExecutorRequestEncoding.consumeEventStream(
            bytes: bytes, providerID: "anthropic",
            parseLine: { _, _ in [.response(text: "hi")] },
            onEvent: { received.append($0) }
        )
        #expect(received == [.response(text: "hi")])
    }
}
