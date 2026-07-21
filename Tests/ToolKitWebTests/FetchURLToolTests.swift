import Foundation
import Testing
@testable import ToolKitWeb

// REQ: FR-082 — fetch_url: HTML to paged Markdown, no network needed via a stub.

final class WebStubURLProtocol: URLProtocol, @unchecked Sendable {
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

private func stubbedSession(status: Int = 200, body: String, finalURL: URL? = nil) -> URLSession {
    WebStubURLProtocol.handler = { request in
        let response = HTTPURLResponse(
            url: finalURL ?? request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: nil
        )!
        return (response, Data(body.utf8))
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [WebStubURLProtocol.self]
    return URLSession(configuration: config)
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

    @Test("A cross-host redirect is reported, not followed")
    func crossHostRedirectReported() async throws {
        let tool = FetchURLTool(session: stubbedSession(
            body: "<p>moved</p>", finalURL: URL(string: "https://attacker.test/")!
        ), assertPublicHost: { _ in })
        await #expect(throws: FetchURLError.crossHostRedirect(from: "example.test", to: "attacker.test")) {
            _ = try await tool.call(arguments: .init(url: "https://example.test/page"))
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
