import Foundation
import FoundationModels
import Testing
@testable import Executors

// REQ: FR-085 — the Responses wire shape, fixture-tested against the exact frames
// captured live from `gpt-5.6` on 2026-07-21 (research/provider-chat-endpoints.md
// "The OpenAI Responses API"). The live cycle itself is in ExecutorsLiveTests.

private let signatureProviderKey = "neutral.signature_provider"

@Suite("OpenAI Responses: stream parsing")
struct OpenAIResponsesStreamParserTests {
    private func events(_ lines: [String]) throws -> [ExecutorEvent] {
        var parser = OpenAIResponsesStreamParser()
        var collected: [ExecutorEvent] = []
        for (offset, line) in lines.enumerated() {
            collected += try parser.consume(line, lineNumber: offset + 1)
        }
        return collected
    }

    @Test("FR-085: a function_call item plus its argument deltas assemble one tool call")
    func toolCallAssembly() throws {
        let parsed = try events([
            #"data: {"type":"response.output_item.added","item":{"id":"fc_1","type":"function_call","status":"in_progress","arguments":"","call_id":"call_abc","name":"sentinel_tool"},"output_index":1}"#,
            #"data: {"type":"response.function_call_arguments.delta","delta":"{\"note\"","item_id":"fc_1"}"#,
            #"data: {"type":"response.function_call_arguments.delta","delta":":\"hi\"}","item_id":"fc_1"}"#,
        ])
        let fragments = parsed.compactMap { event -> String? in
            guard case let .toolCall(_, id, name, fragment, _) = event else { return nil }
            #expect(id == "call_abc")
            #expect(name == "sentinel_tool")
            return fragment
        }
        #expect(fragments.joined() == #"{"note":"hi"}"#)
    }

    @Test("FR-085: reasoning is captured from output_item.done, whose encrypted_content differs from .added")
    func reasoningItemComesFromDone() throws {
        let parsed = try events([
            #"data: {"type":"response.output_item.added","item":{"id":"rs_1","type":"reasoning","content":[],"encrypted_content":"STALE"}}"#,
            #"data: {"type":"response.output_item.done","item":{"id":"rs_1","type":"reasoning","content":[],"encrypted_content":"FINAL"}}"#,
        ])
        #expect(parsed.count == 1)
        guard case let .reasoning(_, _, metadata) = parsed[0] else {
            Issue.record("expected a reasoning event")
            return
        }
        let item = try #require(metadata["openai.reasoning_item"])
        #expect(item.contains("FINAL"))
        #expect(!item.contains("STALE"))
    }

    @Test("FR-085: output_text deltas become response text; response.completed carries usage")
    func textAndUsage() throws {
        let parsed = try events([
            #"data: {"type":"response.output_text.delta","delta":"WORK","item_id":"msg_1"}"#,
            #"data: {"type":"response.output_text.delta","delta":"KIT","item_id":"msg_1"}"#,
            #"data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":108,"output_tokens":16}}}"#,
        ])
        let text = parsed.compactMap { if case let .response(value) = $0 { value } else { nil } }.joined()
        #expect(text == "WORKKIT")
        #expect(parsed.contains(.usage(input: 108, output: 16)))
        #expect(parsed.contains(.finish(reason: "completed")))
    }

    @Test("FR-085: a response.failed frame throws with the provider's own message")
    func failureFrameThrows() {
        #expect {
            _ = try events([
                #"data: {"type":"response.failed","response":{"error":{"code":"server_error","message":"boom"}}}"#,
            ])
        } throws: { error in
            guard case let ProviderStreamError.event(provider, type, message) = error else { return false }
            return provider == "openai" && type == "server_error" && message == "boom"
        }
    }
}

@Suite("OpenAI Responses: request encoding")
struct OpenAIResponsesEncodingTests {
    @Test("FR-085: tools are declared flat, not nested under a function object")
    func flatToolDeclaration() throws {
        let definitions = [Transcript.ToolDefinition(
            name: "sentinel_tool", description: "probe",
            parameters: GenerationSchema(type: SentinelProbeArguments.self, properties: [])
        )]
        let encoded = try ExecutorRequestEncoding.openAIResponsesTools(definitions)
        #expect(encoded.count == 1)
        #expect(encoded[0]["type"] as? String == "function")
        #expect(encoded[0]["name"] as? String == "sentinel_tool")
        #expect(encoded[0]["description"] as? String == "probe")
        #expect(encoded[0]["function"] == nil)
        #expect(encoded[0]["parameters"] != nil)
    }

    @Test("FR-085: a tool cycle encodes as function_call / function_call_output items")
    func toolCycleItems() throws {
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "i1", segments: [.text(.init(content: "Be brief."))], toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "go"))])),
            .reasoning(Transcript.Reasoning(
                id: "r1",
                metadata: [
                    signatureProviderKey: "openai",
                    "openai.reasoning_item": #"{"id":"rs_1","type":"reasoning","encrypted_content":"BLOB"}"#,
                ],
                segments: []
            )),
            .toolCalls(Transcript.ToolCalls([Transcript.ToolCall(
                id: "call_1", toolName: "sentinel_tool",
                arguments: try GeneratedContent(json: #"{"note":"hi"}"#)
            )])),
            .toolOutput(Transcript.ToolOutput(
                id: "call_1", toolName: "sentinel_tool",
                segments: [.text(.init(content: "PROBE"))]
            )),
        ])
        let encoded = try ExecutorRequestEncoding.openAIResponsesInput(from: transcript)

        #expect(encoded.instructions == "Be brief.")
        #expect(encoded.items.count == 4)
        #expect(encoded.items[0]["role"] as? String == "user")
        #expect(encoded.items[1]["type"] as? String == "reasoning")
        #expect(encoded.items[1]["encrypted_content"] as? String == "BLOB")
        #expect(encoded.items[2]["type"] as? String == "function_call")
        #expect(encoded.items[2]["call_id"] as? String == "call_1")
        // Apple's `GeneratedContent.jsonString` re-serializes with its own spacing;
        // what matters is that the value is intact, valid JSON, not byte-identical.
        let arguments = try #require(encoded.items[2]["arguments"] as? String)
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: String]
        )
        #expect(decoded == ["note": "hi"])
        #expect(encoded.items[3]["type"] as? String == "function_call_output")
        #expect(encoded.items[3]["call_id"] as? String == "call_1")
        #expect(encoded.items[3]["output"] as? String == "PROBE")
    }

    @Test("FR-085: another provider's reasoning entry is not replayed to OpenAI")
    func foreignReasoningIsIgnored() throws {
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "go"))])),
            .reasoning(Transcript.Reasoning(
                id: "r1",
                metadata: [
                    signatureProviderKey: "anthropic",
                    "openai.reasoning_item": #"{"id":"rs_1","type":"reasoning"}"#,
                ],
                segments: []
            )),
        ])
        let encoded = try ExecutorRequestEncoding.openAIResponsesInput(from: transcript)
        #expect(encoded.items.count == 1)
        #expect(encoded.items[0]["role"] as? String == "user")
    }

    @Test("FR-085: the body carries store:false and the encrypted-reasoning include")
    func bodyKeepsStateLocal() throws {
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(id: "p1", segments: [.text(.init(content: "go"))])),
        ])
        let request = LanguageModelExecutorGenerationRequest(
            id: UUID(), transcript: transcript, enabledTools: [],
            generationOptions: GenerationOptions(), contextOptions: ContextOptions(), metadata: [:]
        )
        let body = try OpenAIResponsesExecutor.requestBody(model: "gpt-5.6", request: request)
        #expect(body["store"] as? Bool == false)
        #expect(body["include"] as? [String] == ["reasoning.encrypted_content"])
        #expect(body["stream"] as? Bool == true)
        #expect(body["tool_choice"] as? String == "auto")
        #expect(body["model"] as? String == "gpt-5.6")
    }
}
