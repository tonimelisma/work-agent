import Foundation
import Testing
@testable import FoundationModelsPOC

@Test func durableTranscriptStripsForeignProviderMetadata() {
    let transcript = DurableTranscript(entries: [.init(id: "1", kind: .reasoning, text: "r", metadata: ["deepseek.reasoning_content": "x", "neutral.id": "1", "anthropic.signature": "y"])])
    #expect(transcript.replay(for: "anthropic").entries[0].metadata == ["neutral.id": "1", "anthropic.signature": "y"])
}

@Test func openAIParserPreservesPartialToolArguments() throws {
    let events = try OpenAICompatibleFixtureParser.events(from: [#"data: {"choices":[{"delta":{"tool_calls":[{"id":"call_1","function":{"name":"read_fixture","arguments":"{\"path\":\""}}]}}]}"#])
    #expect(events == [.toolCall(id: "call_1", name: "read_fixture", argumentsFragment: "{\"path\":\"", metadata: [:])])
}

@Test func schemaBridgeRejectsLossyKeywordsWithPath() {
    #expect(throws: SchemaBridgeError.unsupported(keyword: "anyOf", path: "$.properties.mode")) {
        try SchemaBridge.parse(["anyOf": []], path: "$.properties.mode")
    }
}

@available(macOS 27.0, *)
@Test func foundationModelsProviderSurfaceLinks() {
    #expect(FoundationModelsSurface.requiredCapabilities.contains(.toolCalling))
}
