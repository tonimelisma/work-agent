//
//  LiveSmokeTests.swift
//  Work AgentTests
//
//  Real network, through the production AgentKit executors (not the deleted
//  POC) — this is increment 4's gated live-provider proof (agent-loop-implementation.md
//  §8/§9). Each test runs ONLY when its provider key is present in the
//  environment (as TEST_RUNNER_<VAR>), so normal runs skip them entirely.
//
//  Run e.g.:
//    TEST_RUNNER_DEEPSEEK_API_KEY=$DEEPSEEK_API_KEY xcodebuild test \
//      -only-testing:"Work AgentTests/LiveSmoke" ...
//

import Foundation
import FoundationModels
import Testing
import Recorder
import Executors
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

/// Runs one real attempt through AgentKit's production executor and returns the reply.
private func smokeOpenAICompatible(providerID: String, modelID: String, apiKey: String) async throws -> String {
    let registry = try loadRegistry()
    let provider = try #require(registry.provider(id: providerID))
    let base = try #require(ProviderCatalog.chatBaseURL(for: provider))
    let model = OpenAICompatibleModel(
        providerID: providerID, model: modelID,
        endpoint: base.appendingPathComponent("chat/completions"), apiKey: apiKey
    )
    let result = try await runSessionAttempt(
        model: model, tools: [], instructions: "Reply concisely.",
        resuming: nil, prompt: "Reply with exactly one word: ready"
    )
    return responseText(in: result.archive)
}

private func smokeAnthropic(modelID: String, apiKey: String) async throws -> String {
    let model = AnthropicModel(model: modelID, apiKey: apiKey)
    let result = try await runSessionAttempt(
        model: model, tools: [], instructions: "Reply concisely.",
        resuming: nil, prompt: "Reply with exactly one word: ready"
    )
    return responseText(in: result.archive)
}

private func responseText(in archive: TranscriptArchive) -> String {
    var text = ""
    for entry in archive.transcript {
        guard case let .response(response) = entry else { continue }
        for segment in response.segments {
            guard case let .text(textSegment) = segment else { continue }
            text += textSegment.content
        }
    }
    return text
}

@Suite("LiveSmoke", .serialized)
struct LiveSmokeTests {

    @Test("FR-070: DeepSeek streams a real reply through the production executor", .enabled(if: key("DEEPSEEK_API_KEY") != nil))
    func deepseek() async throws {
        let reply = try await smokeOpenAICompatible(providerID: "deepseek", modelID: "deepseek-v4-pro", apiKey: key("DEEPSEEK_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Anthropic streams a real reply through the production executor", .enabled(if: key("ANTHROPIC_API_KEY") != nil))
    func anthropic() async throws {
        let reply = try await smokeAnthropic(modelID: "claude-sonnet-5", apiKey: key("ANTHROPIC_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Google streams a real reply through the production executor", .enabled(if: key("GOOGLE_API_KEY") != nil))
    func google() async throws {
        let reply = try await smokeOpenAICompatible(providerID: "google", modelID: "gemini-3.5-flash", apiKey: key("GOOGLE_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Moonshot streams a real reply through the production executor", .enabled(if: key("MOONSHOT_API_KEY") != nil))
    func moonshot() async throws {
        let reply = try await smokeOpenAICompatible(providerID: "moonshotai", modelID: "kimi-k3", apiKey: key("MOONSHOT_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("FR-070: Alibaba streams a real reply through the production executor", .enabled(if: key("DASHSCOPE_API_KEY") != nil))
    func alibaba() async throws {
        let reply = try await smokeOpenAICompatible(providerID: "alibaba", modelID: "qwen3.7-max", apiKey: key("DASHSCOPE_API_KEY")!)
        #expect(!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private final class LiveAnchor {}
