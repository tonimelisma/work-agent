import Foundation
import Testing
@testable import ToolKitWeb

// REQ: FR-082 — fetch_url: HTML to paged Markdown, no network needed via a stub.

final class WebStubURLProtocol: URLProtocol, @unchecked Sendable {
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

private func stubbedSession(
    handler: @escaping @Sendable (URLRequest) -> (Int, [String: String], Data)
) -> URLSession {
    WebStubURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [WebStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func stubbedSession(status: Int = 200, body: String) -> URLSession {
    stubbedSession { _ in (status, [:], Data(body.utf8)) }
}

/// Thread-safe recorder for assertions across a `@Sendable` stub/host-check closure.
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func record(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        values.append(value)
    }
    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

@Suite("fetch_url", .serialized)
struct FetchURLToolTests {
    @Test("Renders headings, links, and list items as Markdown")
    func rendersMarkdown() async throws {
        let html = "<html><body><h1>Title</h1><p>Hello world</p><ul><li>one</li><li>two</li></ul></body></html>"
        let tool = FetchURLTool(session: stubbedSession(body: html), assertPublicHost: { _ in })
        let output = try await tool.call(arguments: .init(url: "https://example.test/page"))
        #expect(output.contains("# Title"))
        #expect(output.contains("Hello world"))
        #expect(output.contains("- one"))
        #expect(output.contains("- two"))
    }

    @Test("An HTTP failure status throws a typed error")
    func httpFailure() async throws {
        let tool = FetchURLTool(session: stubbedSession(status: 404, body: ""), assertPublicHost: { _ in })
        await #expect(throws: FetchURLError.httpFailure(404)) {
            _ = try await tool.call(arguments: .init(url: "https://example.test/missing"))
        }
    }

    @Test("A cross-host redirect throws without ever fetching the second host")
    func crossHostRedirectReported() async throws {
        let requestedHosts = CallLog()
        let session = stubbedSession { request in
            requestedHosts.record(request.url!.host!)
            if request.url!.host == "example.test" {
                return (302, ["Location": "https://attacker.test/"], Data())
            }
            return (200, [:], Data("should never be fetched".utf8))
        }
        let tool = FetchURLTool(session: session, assertPublicHost: { _ in })
        await #expect(throws: FetchURLError.crossHostRedirect(from: "example.test", to: "attacker.test")) {
            _ = try await tool.call(arguments: .init(url: "https://example.test/page"))
        }
        #expect(requestedHosts.all == ["example.test"])
    }

    @Test("A same-host redirect is followed, re-validating the host on every hop")
    func sameHostRedirectFollowed() async throws {
        let session = stubbedSession { request in
            if request.url!.path == "/page" {
                return (302, ["Location": "/moved"], Data())
            }
            return (200, [:], Data("<p>moved content</p>".utf8))
        }
        let validatedHosts = CallLog()
        let tool = FetchURLTool(session: session, assertPublicHost: { host in validatedHosts.record(host) })
        let output = try await tool.call(arguments: .init(url: "https://example.test/page"))
        #expect(output.contains("moved content"))
        #expect(validatedHosts.all == ["example.test", "example.test"])
    }

    @Test("A redirect with a missing Location header is a typed HTTP failure")
    func missingLocationHeader() async throws {
        let tool = FetchURLTool(
            session: stubbedSession(status: 302, body: ""), assertPublicHost: { _ in }
        )
        await #expect(throws: FetchURLError.httpFailure(302)) {
            _ = try await tool.call(arguments: .init(url: "https://example.test/page"))
        }
    }

    @Test("A response streaming past the byte cap throws without buffering the whole body")
    func responseTooLargeWhileStreaming() async throws {
        let oversized = String(repeating: "a", count: 100)
        let session = stubbedSession(body: oversized)
        let tool = FetchURLTool(
            session: session, maximumResponseBytes: 10, assertPublicHost: { _ in }
        )
        await #expect(throws: FetchURLError.responseTooLarge) {
            _ = try await tool.call(arguments: .init(url: "https://example.test/big"))
        }
    }

    @Test("Content longer than one page is split, with a page marker")
    func pagesLongContent() async throws {
        let paragraphs = (1 ... 5).map { "<p>line \($0)</p>" }.joined()
        let tool = FetchURLTool(session: stubbedSession(body: "<html><body>\(paragraphs)</body></html>"), linesPerPage: 2, assertPublicHost: { _ in })
        let page1 = try await tool.call(arguments: .init(url: "https://example.test/page", page: 1))
        #expect(page1.contains("line 1"))
        #expect(page1.contains("Page 1 of"))
        let page2 = try await tool.call(arguments: .init(url: "https://example.test/page", page: 2))
        #expect(page2.contains("line 3"))
    }

    @Test("http is upgraded to https")
    func upgradesToHTTPS() async throws {
        let tool = FetchURLTool(session: stubbedSession(body: "<p>ok</p>"), assertPublicHost: { _ in })
        let output = try await tool.call(arguments: .init(url: "http://example.test/page"))
        #expect(output.contains("ok"))
    }
}
