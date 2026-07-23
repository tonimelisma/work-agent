import Foundation
import FoundationModels
import Testing
import ToolVocabulary
@testable import Executors

// REQ: Anthropic's `output_config.effort` follows `ContextOptions.reasoningLevel`
// instead of being hard-coded to max on every request — the encoder is pure, so
// this is tested directly with no network stub.

private func request(reasoningLevel: ContextOptions.ReasoningLevel?) -> LanguageModelExecutorGenerationRequest {
    LanguageModelExecutorGenerationRequest(
        id: UUID(),
        transcript: Transcript(entries: []),
        enabledTools: [],
        generationOptions: GenerationOptions(),
        contextOptions: ContextOptions(reasoningLevel: reasoningLevel),
        metadata: [:]
    )
}

@Suite("Anthropic request body: reasoning-level effort mapping")
struct AnthropicRequestBodyTests {
    @Test("Thinking Machines uses its documented Anthropic-compatible Inkling preset")
    func thinkingMachinesPreset() {
        let endpoint = URL(
            string: "https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api/v1/messages"
        )!
        let model = AnthropicModel(
            model: "thinkingmachines/Inkling",
            apiKey: "test-key",
            endpoint: endpoint,
            providerID: "thinkingmachines"
        )

        #expect(model.executorConfiguration.model == "thinkingmachines/Inkling")
        #expect(model.executorConfiguration.endpoint == endpoint)
        #expect(model.executorConfiguration.providerID == "thinkingmachines")
    }

    @Test("An Anthropic-compatible provider replays only its own signed reasoning")
    func compatibleProviderOwnsReasoning() throws {
        let transcript = Transcript(entries: [
            .reasoning(Transcript.Reasoning(
                id: "reasoning-1",
                metadata: [TranscriptMetadataKeys.signatureProvider: "thinkingmachines"],
                segments: [.text(.init(content: "provider thought"))],
                signature: Data("provider-signature".utf8)
            )),
        ])

        let encoded = try ExecutorRequestEncoding.anthropicMessages(
            from: transcript, providerID: "thinkingmachines"
        )
        guard let content = encoded.messages.first?["content"] as? [[String: Any]],
              let firstBlock = content.first
        else {
            Issue.record("expected an assistant thinking block")
            return
        }
        #expect(firstBlock["type"] as? String == "thinking")
        #expect(firstBlock["thinking"] as? String == "provider thought")
    }

    @Test("No reasoning level omits output_config entirely (provider default)")
    func noLevelOmitsOutputConfig() throws {
        let body = try AnthropicExecutor.requestBody(model: "claude-x", request: request(reasoningLevel: nil))
        #expect(body["output_config"] == nil)
        #expect((body["thinking"] as? [String: String])?["type"] == "adaptive")
    }

    @Test(".light maps to low effort")
    func lightMapsToLow() throws {
        let body = try AnthropicExecutor.requestBody(model: "claude-x", request: request(reasoningLevel: .light))
        #expect((body["output_config"] as? [String: String])?["effort"] == "low")
    }

    @Test(".moderate maps to medium effort")
    func moderateMapsToMedium() throws {
        let body = try AnthropicExecutor.requestBody(model: "claude-x", request: request(reasoningLevel: .moderate))
        #expect((body["output_config"] as? [String: String])?["effort"] == "medium")
    }

    @Test(".deep maps to high effort")
    func deepMapsToHigh() throws {
        let body = try AnthropicExecutor.requestBody(model: "claude-x", request: request(reasoningLevel: .deep))
        #expect((body["output_config"] as? [String: String])?["effort"] == "high")
    }

    @Test("A custom level passes its raw value straight through")
    func customPassesThrough() throws {
        let body = try AnthropicExecutor.requestBody(
            model: "claude-x", request: request(reasoningLevel: .custom("ultrathink"))
        )
        #expect((body["output_config"] as? [String: String])?["effort"] == "ultrathink")
    }

    @Test("thinking stays adaptive regardless of effort level")
    func thinkingAlwaysAdaptive() throws {
        for level: ContextOptions.ReasoningLevel? in [nil, .light, .moderate, .deep, .custom("x")] {
            let body = try AnthropicExecutor.requestBody(model: "claude-x", request: request(reasoningLevel: level))
            #expect((body["thinking"] as? [String: String])?["type"] == "adaptive")
        }
    }
}
