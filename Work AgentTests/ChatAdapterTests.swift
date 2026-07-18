//
//  ChatAdapterTests.swift
//  Work AgentTests
//
//  SSE-parsing tests for the two chat adapters, no network (StubURLProtocol).
//

import Foundation
import Testing
@testable import Work_Agent

/// A stub dedicated to the chat adapters, so it doesn't share static state with
/// ProviderVerifierTests' StubURLProtocol. The streaming suites below are `.serialized`
/// under one parent so they never race on this handler.
final class ChatStubURLProtocol: URLProtocol, @unchecked Sendable {
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

private func session(status: Int, body: String) -> URLSession {
    ChatStubURLProtocol.handler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        return (response, Data(body.utf8))
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ChatStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func collect(_ stream: AsyncThrowingStream<ChatChunk, Error>) async -> (text: String, reasoning: String, error: Error?) {
    var text = "", reasoning = ""
    do {
        for try await chunk in stream {
            switch chunk {
            case .text(let t): text += t
            case .reasoning(let r): reasoning += r
            }
        }
        return (text, reasoning, nil)
    } catch {
        return (text, reasoning, error)
    }
}

private let base = URL(string: "https://example.test/v1")!

// One serialized parent so the two network suites never race on the shared stub handler.
@Suite("Streaming chat adapters", .serialized)
struct StreamingChatAdapters {

@Suite("OpenAI-compatible adapter")
struct OpenAICompatibleChatProviderTests {

    @Test("FR-070: content deltas assemble into the reply")
    func assemblesContent() async throws {
        let sse = """
        data: {"choices":[{"delta":{"role":"assistant","content":"Hel"}}]}

        data: {"choices":[{"delta":{"content":"lo"}}]}

        data: {"choices":[{"delta":{"content":"!"}}]}

        data: [DONE]

        """
        let provider = OpenAICompatibleChatProvider(baseURL: base, session: session(status: 200, body: sse))
        let out = await collect(provider.stream(messages: [ChatMessage(role: .user, text: "hi")], model: "m", apiKey: "k"))
        #expect(out.text == "Hello!")
        #expect(out.error == nil)
    }

    @Test("FR-065: reasoning_content is surfaced as reasoning, separate from text")
    func separatesReasoning() async throws {
        let sse = """
        data: {"choices":[{"delta":{"reasoning_content":"thinking…"}}]}

        data: {"choices":[{"delta":{"content":"answer"}}]}

        data: [DONE]

        """
        let provider = OpenAICompatibleChatProvider(baseURL: base, session: session(status: 200, body: sse))
        let out = await collect(provider.stream(messages: [], model: "m", apiKey: "k"))
        #expect(out.text == "answer")
        #expect(out.reasoning == "thinking…")
    }

    @Test("FR-040: an auth failure throws a jargon-free ChatError")
    func authFailureIsFriendly() async throws {
        let provider = OpenAICompatibleChatProvider(baseURL: base, session: session(status: 401, body: ""))
        let out = await collect(provider.stream(messages: [], model: "m", apiKey: "bad"))
        #expect(out.error as? ChatError == .rejected)
    }

    @Test("A 402 maps to out-of-credit, not a bad key")
    func outOfCredit() async throws {
        let provider = OpenAICompatibleChatProvider(baseURL: base, session: session(status: 402, body: ""))
        let out = await collect(provider.stream(messages: [], model: "m", apiKey: "k"))
        #expect(out.error as? ChatError == .outOfCredit)
    }
}

@Suite("Anthropic adapter")
struct AnthropicChatProviderTests {

    @Test("FR-070: text_delta events assemble into the reply")
    func assemblesText() async throws {
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"role":"assistant"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let provider = AnthropicChatProvider(baseURL: URL(string: "https://api.anthropic.test")!,
                                             session: session(status: 200, body: sse))
        let out = await collect(provider.stream(messages: [ChatMessage(role: .user, text: "hi")], model: "claude", apiKey: "k"))
        #expect(out.text == "Hi there")
        #expect(out.error == nil)
    }

    @Test("FR-065: thinking_delta is surfaced as reasoning")
    func separatesThinking() async throws {
        let sse = """
        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}

        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"done"}}

        """
        let provider = AnthropicChatProvider(baseURL: URL(string: "https://api.anthropic.test")!,
                                             session: session(status: 200, body: sse))
        let out = await collect(provider.stream(messages: [], model: "claude", apiKey: "k"))
        #expect(out.text == "done")
        #expect(out.reasoning == "hmm")
    }
}

}  // StreamingChatAdapters

@Suite("Chat provider routing")
struct ChatProviderFactoryTests {

    private func provider(id: String, api: String? = nil) throws -> RegistryProvider {
        let apiField = api.map { "\"api\": \"\($0)\"," } ?? ""
        let json = """
        {"\(id)": {"id": "\(id)", "name": "\(id)", "env": [], \(apiField)
                   "models": {"m": {"id": "m", "name": "M", "tool_call": true}}}}
        """
        return try #require(try JSONDecoder().decode(ModelRegistry.self, from: Data(json.utf8)).providers.first)
    }

    @Test("NFR-001: Anthropic routes to the Anthropic adapter, others to OpenAI-compatible")
    func routing() throws {
        #expect(ChatProviderFactory.provider(for: try provider(id: "anthropic")) is AnthropicChatProvider)
        #expect(ChatProviderFactory.provider(for: try provider(id: "openai")) is OpenAICompatibleChatProvider)
        #expect(ChatProviderFactory.provider(for: try provider(id: "deepseek", api: "https://api.deepseek.com")) is OpenAICompatibleChatProvider)
    }

    @Test("FR-001: google and minimax get OpenAI-compatible chat base overrides")
    func chatBaseOverrides() throws {
        let google = try provider(id: "google")
        #expect(ProviderCatalog.chatBaseURL(for: google)?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai")
        let minimax = try provider(id: "minimax", api: "https://api.minimax.io/anthropic/v1")
        #expect(ProviderCatalog.chatBaseURL(for: minimax)?.absoluteString == "https://api.minimax.io/v1")
    }
}

@Suite("Curated catalog")
struct CuratedCatalogTests {

    @Test("FR-061/FR-062: the curated set is 11 first-party providers")
    func curatedShape() {
        #expect(CuratedCatalog.providerOrder.count == 11)
        #expect(CuratedCatalog.isCurated(providerID: "openai", modelID: "gpt-5.6"))
        #expect(!CuratedCatalog.isCurated(providerID: "openai", modelID: "gpt-3.5"))
        #expect(!CuratedCatalog.isCurated(providerID: "openrouter"))  // a reseller
    }

    @Test("FR-061: curated models resolve against the bundled snapshot")
    func resolvesAgainstSnapshot() throws {
        let url = try #require(Bundle(for: SnapshotAnchor.self).url(forResource: "models-dev-snapshot", withExtension: "json")
            ?? Bundle.main.url(forResource: "models-dev-snapshot", withExtension: "json"))
        let registry = try JSONDecoder().decode(ModelRegistry.self, from: try Data(contentsOf: url))

        // Every curated provider resolves to at least its first model.
        for id in CuratedCatalog.providerOrder {
            let models = registry.curatedModels(for: id)
            #expect(!models.isEmpty, "curated provider \(id) resolved no models")
        }
        #expect(registry.curatedProviders().count == 11)
    }
}

private final class SnapshotAnchor {}
