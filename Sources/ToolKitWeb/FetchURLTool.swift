import Foundation
import FoundationModels
import SwiftSoup

// REQ: FR-082 — fetch_url: a web page as paged Markdown, no extraction model call
// ("no extraction model, no second model call" — tool-architecture.md §3).
public enum FetchURLError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case disallowedHost(String)
    case crossHostRedirect(from: String, to: String)
    case responseTooLarge
    case httpFailure(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "'\(url)' isn't a valid HTTPS URL."
        case let .disallowedHost(host):
            "\(host) resolves to a private or link-local address and can't be fetched."
        case let .crossHostRedirect(from, to):
            "\(from) redirected to a different host (\(to)); not followed automatically."
        case .responseTooLarge:
            "The response exceeded the 5 MB limit."
        case let .httpFailure(status):
            "The page returned HTTP \(status)."
        }
    }
}

@Generable
public struct FetchURLArguments: Sendable {
    @Guide(description: "The page to fetch. Must be HTTP or HTTPS.")
    public var url: String
    @Guide(description: "1-based page of the rendered content to return (2,000 lines per page)")
    public var page: Int?

    public init(url: String, page: Int? = nil) {
        self.url = url
        self.page = page
    }
}

public struct FetchURLTool: Tool, Sendable {
    public let name = "fetch_url"
    public let description = """
    Fetch a web page and return it as paged Markdown (page defaults to 1, 2,000 \
    lines per page). HTTPS is upgraded automatically; cross-host redirects are \
    reported rather than followed; responses over 5 MB are rejected.
    """

    private let session: URLSession
    private let linesPerPage: Int
    private let maximumResponseBytes: Int
    private let assertPublicHost: @Sendable (String) async throws -> Void

    public init(
        session: URLSession = .shared,
        linesPerPage: Int = 2_000,
        maximumResponseBytes: Int = 5_000_000,
        assertPublicHost: @escaping @Sendable (String) async throws -> Void = NetworkSafety.assertPublicHost
    ) {
        self.session = session
        self.linesPerPage = linesPerPage
        self.maximumResponseBytes = maximumResponseBytes
        self.assertPublicHost = assertPublicHost
    }

    public func call(arguments: FetchURLArguments) async throws -> String {
        guard var components = URLComponents(string: arguments.url) else {
            throw FetchURLError.invalidURL(arguments.url)
        }
        if components.scheme == "http" { components.scheme = "https" }
        guard components.scheme == "https", let url = components.url, let host = url.host else {
            throw FetchURLError.invalidURL(arguments.url)
        }
        try await assertPublicHost(host)

        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchURLError.invalidURL(arguments.url) }
        if let finalHost = http.url?.host, finalHost != host {
            throw FetchURLError.crossHostRedirect(from: host, to: finalHost)
        }
        guard (200 ..< 300).contains(http.statusCode) else { throw FetchURLError.httpFailure(http.statusCode) }
        guard data.count <= maximumResponseBytes else { throw FetchURLError.responseTooLarge }

        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let markdown = try HTMLToMarkdown.convert(html)

        let lines = markdown.components(separatedBy: .newlines)
        let page = max(1, arguments.page ?? 1)
        let start = (page - 1) * linesPerPage
        guard start < lines.count else {
            return "[Page \(page) is past the end of the content (\(lines.count) lines total)]"
        }
        let end = min(lines.count, start + linesPerPage)
        let body = lines[start ..< end].joined(separator: "\n")
        if end < lines.count {
            let totalPages = Int(ceil(Double(lines.count) / Double(linesPerPage)))
            return body + "\n\n[Page \(page) of \(totalPages).]"
        }
        return body
    }
}

enum HTMLToMarkdown {
    static func convert(_ html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        try document.select("script, style, noscript").remove()
        var lines: [String] = []
        try walk(document.body() ?? document, into: &lines)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func walk(_ node: Element, into lines: inout [String]) throws {
        for child in node.children() {
            switch child.tagName() {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(child.tagName().dropFirst()) ?? 1
                let text = try child.text()
                if !text.isEmpty { lines.append(String(repeating: "#", count: level) + " " + text) }
            case "li":
                let text = try child.text()
                if !text.isEmpty { lines.append("- " + text) }
            case "a":
                let text = try child.text()
                let href = try child.attr("href")
                if !text.isEmpty { lines.append(href.isEmpty ? text : "[\(text)](\(href))") }
            case "br":
                lines.append("")
            default:
                if child.children().isEmpty() {
                    let text = try child.text()
                    if !text.isEmpty { lines.append(text) }
                } else {
                    try walk(child, into: &lines)
                }
            }
        }
    }
}
