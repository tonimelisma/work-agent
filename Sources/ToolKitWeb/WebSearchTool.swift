import Foundation
import FoundationModels

// REQ: FR-083 — web_search: the provider's own hosted search where offered, else a
// neutral Brave-backed search ("Both." — tool-architecture.md §3/§6). This type is
// the neutral fallback; hosted search is the executor's job (agent-loop-implementation.md
// §4's provider-extension tiers), not this tool.
public enum WebSearchError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case httpFailure(Int)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No Brave Search API key is configured."
        case let .httpFailure(status): "Brave Search returned HTTP \(status)."
        case .badResponse: "Brave Search returned something unexpected."
        }
    }
}

@Generable
public struct WebSearchArguments: Sendable {
    @Guide(description: "The search query")
    public var query: String
    @Guide(description: "Maximum results to return (default 10, max 20)")
    public var count: Int?

    public init(query: String, count: Int? = nil) {
        self.query = query
        self.count = count
    }
}

/// A neutral, provider-independent web search backed by the Brave Search API.
/// Registered for models whose provider has no hosted search tool of its own
/// (the registry rule: exactly one `web_search` tool per model, hosted preferred).
public struct BraveWebSearchTool: Tool, Sendable {
    public let name = "web_search"
    public let description = "Search the web. Returns titles, URLs, and snippets."

    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.search.brave.com/res/v1/web/search")!

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func call(arguments: WebSearchArguments) async throws -> String {
        guard !apiKey.isEmpty else { throw WebSearchError.missingAPIKey }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "q", value: arguments.query),
            .init(name: "count", value: String(min(max(arguments.count ?? 10, 1), 20))),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebSearchError.badResponse }
        guard (200 ..< 300).contains(http.statusCode) else { throw WebSearchError.httpFailure(http.statusCode) }

        let decoded = try JSONDecoder().decode(BraveSearchResponse.self, from: data)
        guard let results = decoded.web?.results, !results.isEmpty else { return "[No results]" }
        return results.map { result in
            "\(result.title)\n\(result.url)\n\(result.description ?? "")"
        }.joined(separator: "\n\n")
    }
}

struct BraveSearchResponse: Decodable {
    struct Web: Decodable {
        struct Result: Decodable {
            let title: String
            let url: String
            let description: String?
        }

        let results: [Result]
    }

    let web: Web?
}
