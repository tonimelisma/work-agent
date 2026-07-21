import Foundation
import Testing
@testable import ToolKitWeb

// REQ: FR-083 — web_search live against the real Brave Search API. Gated on
// `BRAVE_API_KEY` so plain `swift test` skips this silently; source `.env` first to
// run it: `set -a; source .env; set +a; swift test --filter WebSearchLiveTests`.

@Suite("web_search (Brave-backed), live")
struct WebSearchLiveTests {
    @Test(
        "A real query against the Brave Search API returns titled, linked results",
        .enabled(if: ProcessInfo.processInfo.environment["BRAVE_API_KEY"]?.isEmpty == false)
    )
    func liveSearchReturnsResults() async throws {
        let apiKey = ProcessInfo.processInfo.environment["BRAVE_API_KEY"] ?? ""
        let tool = BraveWebSearchTool(apiKey: apiKey)
        let output = try await tool.call(arguments: .init(query: "Swift Foundation Models framework"))

        #expect(output != "[No results]")
        #expect(output.contains("https://"))
    }
}
