import Foundation
import Testing
@testable import ToolKitWeb

// REQ: FR-083 — the neutral Brave-backed web_search path, no network needed via a stub.
// A dedicated stub protocol, so this suite's static handler never races
// FetchURLToolTests' WebStubURLProtocol when suites run concurrently.

final class BraveStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedSession(status: Int = 200, body: String) -> URLSession {
    BraveStubURLProtocol.handler = { request in
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        return (response, Data(body.utf8))
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BraveStubURLProtocol.self]
    return URLSession(configuration: config)
}

@Suite("web_search (Brave-backed)", .serialized)
struct WebSearchToolTests {
    @Test("Formats results as title/url/snippet")
    func formatsResults() async throws {
        let body = """
        {"web": {"results": [
            {"title": "Example", "url": "https://example.test", "description": "A test result"}
        ]}}
        """
        let tool = BraveWebSearchTool(apiKey: "test-key", session: stubbedSession(body: body))
        let output = try await tool.call(arguments: .init(query: "test"))
        #expect(output.contains("Example"))
        #expect(output.contains("https://example.test"))
        #expect(output.contains("A test result"))
    }

    @Test("No results reads as an explicit notice")
    func noResults() async throws {
        let tool = BraveWebSearchTool(apiKey: "test-key", session: stubbedSession(body: #"{"web": {"results": []}}"#))
        let output = try await tool.call(arguments: .init(query: "nothing"))
        #expect(output == "[No results]")
    }

    @Test("A missing API key fails before any request")
    func missingAPIKey() async throws {
        let tool = BraveWebSearchTool(apiKey: "", session: stubbedSession(body: "{}"))
        await #expect(throws: WebSearchError.missingAPIKey) {
            _ = try await tool.call(arguments: .init(query: "test"))
        }
    }

    @Test("An HTTP failure throws a typed error")
    func httpFailure() async throws {
        let tool = BraveWebSearchTool(apiKey: "test-key", session: stubbedSession(status: 401, body: ""))
        await #expect(throws: WebSearchError.httpFailure(401)) {
            _ = try await tool.call(arguments: .init(query: "test"))
        }
    }
}
