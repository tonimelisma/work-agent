import Foundation
import FoundationModels
import Testing
@testable import Executors

// REQ: FR-001 (2026-07-20 review errata, carried over from PR #12) — Anthropic
// redacted_thinking blocks must round-trip through the transcript's reasoning
// metadata instead of being silently dropped by the stream parser.
//
// A replay-strips-this-key test is deliberately not duplicated here:
// `TranscriptArchiveTests.transcriptArchiveStripsForeignProviderMetadata`
// (RecorderTests) already proves the prefix filter is key-name-agnostic —
// "anthropic.redacted_thinking" gets stripped by the exact same mechanism
// already locked down for "anthropic.signature".

private let signatureProviderKey = "neutral.signature_provider"

@Suite("Redacted thinking: bridge accumulation")
struct RedactedThinkingBridgeTests {
    @Test("Two redacted blocks accumulate as a JSON array, in order")
    func accumulatesInOrder() throws {
        let (afterFirst, jsonFirst) = ExecutorChannelBridge.accumulatedRedactedThinkingJSON(
            appending: "blob-1", to: []
        )
        #expect(afterFirst == ["blob-1"])
        #expect(try JSONDecoder().decode([String].self, from: Data(jsonFirst.utf8)) == ["blob-1"])

        let (afterSecond, jsonSecond) = ExecutorChannelBridge.accumulatedRedactedThinkingJSON(
            appending: "blob-2", to: afterFirst
        )
        #expect(afterSecond == ["blob-1", "blob-2"])
        #expect(try JSONDecoder().decode([String].self, from: Data(jsonSecond.utf8)) == ["blob-1", "blob-2"])
    }
}

@Suite("Redacted thinking: encoder round-trip")
struct RedactedThinkingEncoderTests {
    @Test("Two redacted blocks plus a signed thinking segment encode in order, redacted first")
    func encodesRedactedBeforeThinking() throws {
        let redactedJSON = String(decoding: try JSONEncoder().encode(["blob-1", "blob-2"]), as: UTF8.self)
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "hi"))])),
            .reasoning(Transcript.Reasoning(
                id: "r1",
                metadata: [
                    signatureProviderKey: "anthropic",
                    "anthropic.redacted_thinking": redactedJSON,
                ],
                segments: [.text(.init(content: "visible thinking"))],
                signature: Data("sig".utf8)
            )),
        ])
        let encoded = try ExecutorRequestEncoding.anthropicMessages(from: transcript)
        let assistantMessage = try #require(encoded.messages.first { $0["role"] as? String == "assistant" })
        let blocks = try #require(assistantMessage["content"] as? [[String: Any]])
        #expect(blocks.count == 3)
        #expect(blocks[0]["type"] as? String == "redacted_thinking")
        #expect(blocks[0]["data"] as? String == "blob-1")
        #expect(blocks[1]["type"] as? String == "redacted_thinking")
        #expect(blocks[1]["data"] as? String == "blob-2")
        #expect(blocks[2]["type"] as? String == "thinking")
        #expect(blocks[2]["thinking"] as? String == "visible thinking")
        #expect(blocks[2]["signature"] as? String == "sig")
    }

    @Test("A redacted-only reasoning entry (no signature) still encodes its blocks")
    func encodesRedactedWithoutSignature() throws {
        let redactedJSON = String(decoding: try JSONEncoder().encode(["only-blob"]), as: UTF8.self)
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "hi"))])),
            .reasoning(Transcript.Reasoning(
                id: "r1",
                metadata: [
                    signatureProviderKey: "anthropic",
                    "anthropic.redacted_thinking": redactedJSON,
                ],
                segments: [],
                signature: nil
            )),
        ])
        let encoded = try ExecutorRequestEncoding.anthropicMessages(from: transcript)
        let assistantMessage = try #require(encoded.messages.first { $0["role"] as? String == "assistant" })
        let blocks = try #require(assistantMessage["content"] as? [[String: Any]])
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "redacted_thinking")
        #expect(blocks[0]["data"] as? String == "only-blob")
    }
}

@Test("A non-Anthropic-owned reasoning entry with a redacted key (defensive) is ignored by the OpenAI encoder")
func openAIEncoderIgnoresRedactedMetadata() throws {
    let redactedJSON = String(decoding: try JSONEncoder().encode(["blob-1"]), as: UTF8.self)
    let transcript = Transcript(entries: [
        .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "hi"))])),
        .reasoning(Transcript.Reasoning(
            id: "r1",
            metadata: [
                signatureProviderKey: "anthropic",
                "anthropic.redacted_thinking": redactedJSON,
            ],
            segments: [],
            signature: nil
        )),
        .response(Transcript.Response(id: "resp1", segments: [.text(.init(content: "done"))])),
    ])
    let messages = try ExecutorRequestEncoding.openAIMessages(from: transcript, providerID: "deepseek")
    #expect(!messages.contains { ($0["content"] as? String)?.contains("blob-1") == true })
}
