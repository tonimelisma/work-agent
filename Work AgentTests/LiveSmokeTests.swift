//
//  LiveSmokeTests.swift
//  Work AgentTests
//
//  Real network. Each test runs ONLY when its provider key is present in the
//  environment (as TEST_RUNNER_<VAR>), so normal runs skip them entirely.
//
//  Run e.g.:
//    TEST_RUNNER_DEEPSEEK_API_KEY=$DEEPSEEK_API_KEY xcodebuild test \
//      -only-testing:"Work AgentTests/LiveSmoke" ...
//

import Foundation
import Testing
@testable import Work_Agent

private func key(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
}

private func loadRegistry() throws -> ModelRegistry {
    let url = try #require(
        Bundle(for: LiveAnchor.self).url(forResource: "models-dev-snapshot", withExtension: "json")
            ?? Bundle.main.url(forResource: "models-dev-snapshot", withExtension: "json")
    )
    return try JSONDecoder().decode(ModelRegistry.self, from: try Data(contentsOf: url))
}

/// Streams a one-word prompt and returns the assembled reply, or throws.
private func smoke(providerID: String, modelID: String, apiKey: String) async throws -> String {
    let registry = try loadRegistry()
    let provider = try #require(registry.provider(id: providerID))
    let adapter = try #require(ChatProviderFactory.provider(for: provider))
    var text = ""
    for try await chunk in adapter.stream(
        messages: [ChatMessage(role: .user, text: "Reply with exactly one word: ready")],
        model: modelID, apiKey: apiKey
    ) {
        if case .text(let t) = chunk { text += t }
    }
    return text
}

@Suite("LiveSmoke", .serialized)
struct LiveSmokeTests {

    @Test("FR-070: DeepSeek streams a real reply", .enabled(if: key("DEEPSEEK_API_KEY") != nil))
    func deepseek() async throws {
        let reply = try await smoke(providerID: "deepseek", modelID: "deepseek-v4-pro", apiKey: key("DEEPSEEK_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Anthropic streams a real reply", .enabled(if: key("ANTHROPIC_API_KEY") != nil))
    func anthropic() async throws {
        let reply = try await smoke(providerID: "anthropic", modelID: "claude-sonnet-5", apiKey: key("ANTHROPIC_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Google streams a real reply", .enabled(if: key("GOOGLE_API_KEY") != nil))
    func google() async throws {
        let reply = try await smoke(providerID: "google", modelID: "gemini-3.5-flash", apiKey: key("GOOGLE_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Moonshot streams a real reply", .enabled(if: key("MOONSHOT_API_KEY") != nil))
    func moonshot() async throws {
        let reply = try await smoke(providerID: "moonshotai", modelID: "kimi-k3", apiKey: key("MOONSHOT_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Alibaba streams a real reply", .enabled(if: key("DASHSCOPE_API_KEY") != nil))
    func alibaba() async throws {
        let reply = try await smoke(providerID: "alibaba", modelID: "qwen3.7-max", apiKey: key("DASHSCOPE_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private final class LiveAnchor {}
