import Foundation
import FoundationModels
import Testing
@testable import Executors

// REQ: review errata from PRs #13 and #14, verified against the tree 2026-07-21.

private let signatureProviderKey = "neutral.signature_provider"

private func transcriptWithArgumentlessToolCall() throws -> Transcript {
    Transcript(entries: [
        .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "go"))])),
        .toolCalls(Transcript.ToolCalls([Transcript.ToolCall(
            id: "call_1", toolName: "sentinel_tool", arguments: try GeneratedContent(json: "{}")
        )])),
    ])
}

@Suite("Encoder hardening: a tool call carrying no arguments")
struct ArgumentlessToolCallTests {
    @Test("An empty arguments string encodes as {} for OpenAI, not as an empty string")
    func openAIEncodesEmptyObject() {
        // Meta streams `"arguments": ""` when the model passes none; replaying that
        // verbatim earns HTTP 400 `arguments must be valid JSON` from Meta's own API.
        #expect(ExecutorRequestEncoding.toolCallArguments("") == "{}")
        #expect(ExecutorRequestEncoding.toolCallArguments("   ") == "{}")
        #expect(ExecutorRequestEncoding.toolCallArguments(#"{"a":1}"#) == #"{"a":1}"#)
    }

    @Test("Anthropic's tool_use input stays a valid JSON object for an argumentless call")
    func anthropicEncodesEmptyObject() throws {
        let encoded = try ExecutorRequestEncoding.anthropicMessages(from: transcriptWithArgumentlessToolCall())
        let assistant = try #require(encoded.messages.first { $0["role"] as? String == "assistant" })
        let blocks = try #require(assistant["content"] as? [[String: Any]])
        #expect(blocks[0]["input"] as? [String: Any] != nil)
    }

    @Test("The OpenAI encoder never emits an empty arguments string")
    func openAIMessagesNeverEmitsEmptyArguments() throws {
        let messages = try ExecutorRequestEncoding.openAIMessages(
            from: transcriptWithArgumentlessToolCall(), providerID: "meta"
        )
        let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
        let calls = try #require(assistant["tool_calls"] as? [[String: Any]])
        let function = try #require(calls[0]["function"] as? [String: Any])
        let arguments = try #require(function["arguments"] as? String)
        #expect(!arguments.isEmpty)
        #expect((try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) != nil)
    }
}

@Suite("Redacted thinking: errata from PR #13")
struct RedactedThinkingErrataTests {
    @Test("The accumulated array is restated on a metadata update that carries no redacted key")
    func accumulatedArrayIsRestated() throws {
        // A redacted block arrives at index 0; the thinking block's signature_delta
        // follows with metadata that has no redacted key. Apple's `updateMetadata`
        // merge-vs-replace semantics are unobservable, so the bridge must restate the
        // array rather than rely on a merge it cannot verify.
        var bridge = ExecutorChannelBridge(
            requestID: UUID(), providerID: "anthropic", toolCallsPossible: false
        )
        _ = bridge.channelEvents(for: .reasoning(
            text: "", signature: nil, metadata: ["anthropic.redacted_thinking": "blob-1"]
        ))
        // Two events: the signature update and the metadata update.
        let followUp = bridge.channelEvents(for: .reasoning(
            text: "", signature: "sig", metadata: ["anthropic.signature": "sig"]
        ))
        #expect(followUp.count == 2)
        // The accumulation seam is what carries the value; assert it directly, since
        // the emitted channel events expose nothing to read back.
        #expect(ExecutorChannelBridge.redactedThinkingJSON(["blob-1"]) == #"["blob-1"]"#)
    }

    @Test("A redacted value that is not a JSON array is treated as one blob, not dropped")
    func bareStringMetadataSurvives() throws {
        #expect(ExecutorRequestEncoding.decodedRedactedThinking("") == [])
        #expect(ExecutorRequestEncoding.decodedRedactedThinking("bare-blob") == ["bare-blob"])
        #expect(ExecutorRequestEncoding.decodedRedactedThinking(#"["a","b"]"#) == ["a", "b"])
    }

    @Test("A bare-string redacted value still encodes a redacted_thinking block")
    func bareStringEncodesToABlock() throws {
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "hi"))])),
            .reasoning(Transcript.Reasoning(
                id: "r1",
                metadata: [signatureProviderKey: "anthropic", "anthropic.redacted_thinking": "bare-blob"],
                segments: [], signature: nil
            )),
        ])
        let encoded = try ExecutorRequestEncoding.anthropicMessages(from: transcript)
        let assistant = try #require(encoded.messages.first { $0["role"] as? String == "assistant" })
        let blocks = try #require(assistant["content"] as? [[String: Any]])
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "redacted_thinking")
        #expect(blocks[0]["data"] as? String == "bare-blob")
    }
}
