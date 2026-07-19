import Foundation
import Testing
@testable import Executors

// REQ: agent-loop-implementation.md §4, §8 — the conformance corpus covers both
// wire formats. Migrated from
// Experiments/FoundationModelsPOC/Tests/FoundationModelsPOCTests/FoundationModelsPOCTests.swift.

@Test("OpenAI-compatible fixtures preserve partial tool arguments and usage")
func openAIParserPreservesPartialToolArguments() throws {
    let events = try parserEvents(from: fixtureLines("openai-tool-stream"), parser: OpenAICompatibleStreamParser())
    #expect(events.contains(.toolCall(
        index: 0, id: "call_1", name: "read_fixture",
        argumentsFragment: #"{"path":""#, metadata: [:]
    )))
    #expect(events.contains(.toolCall(
        index: 0, id: "call_1", name: "read_fixture",
        argumentsFragment: #"answer.txt"}"#, metadata: [:]
    )))
    #expect(events.contains(.usage(input: 17, output: 8)))
    #expect(events.contains(.finish(reason: "tool_calls")))
}

@Test("Google thought signatures survive their nested provider field")
func googleParserPreservesThoughtSignature() throws {
    let events = try parserEvents(
        from: fixtureLines("google-reasoning-stream"), parser: OpenAICompatibleStreamParser()
    )
    #expect(events.contains(.reasoning(
        text: "I should read the fixture.",
        signature: "Z29vZ2xlLXNpZw==",
        metadata: ["google.thought_signature": "Z29vZ2xlLXNpZw=="]
    )))
}

@Test("Anthropic block starts supply identity to later argument fragments")
func anthropicParserPreservesToolIdentity() throws {
    let events = try parserEvents(from: fixtureLines("anthropic-tool-stream"), parser: AnthropicStreamParser())
    let toolFragments = events.compactMap { event -> (String, String, String)? in
        guard case let .toolCall(_, id, name, fragment, _) = event else { return nil }
        return (id, name, fragment)
    }
    #expect(toolFragments.count == 2)
    #expect(toolFragments.allSatisfy { $0.0 == "toolu_1" && $0.1 == "read_fixture" })
    #expect(toolFragments.map(\.2).joined() == #"{"path":"answer.txt"}"#)
    #expect(events.contains(.reasoning(
        text: "",
        signature: "YW50aHJvcGljLXNpZw==",
        metadata: ["anthropic.signature": "YW50aHJvcGljLXNpZw=="]
    )))
    #expect(events.contains(.usage(input: 19, output: 13)))
}

@Test("Anthropic argument fragments without a block start fail precisely")
func anthropicParserRejectsMissingToolIdentity() {
    let line = #"data: {"type":"content_block_delta","index":3,"delta":{"type":"input_json_delta","partial_json":"{}"}}"#
    #expect(throws: StreamParseError.missingToolBlock(index: 3, line: 1)) {
        var parser = AnthropicStreamParser()
        _ = try parser.consume(line, lineNumber: 1)
    }
}

@Test("Anthropic HTTP-200 stream errors propagate as typed failures")
func anthropicParserPropagatesStreamErrors() {
    let line = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
    #expect(throws: ProviderStreamError.event(
        provider: "anthropic", type: "overloaded_error", message: "Overloaded"
    )) {
        var parser = AnthropicStreamParser()
        _ = try parser.consume(line, lineNumber: 1)
    }
}

private func parserEvents(
    from lines: [String],
    parser: OpenAICompatibleStreamParser
) throws -> [ExecutorEvent] {
    var parser = parser
    var events: [ExecutorEvent] = []
    for (offset, line) in lines.enumerated() {
        events.append(contentsOf: try parser.consume(line, lineNumber: offset + 1))
    }
    return events
}

private func parserEvents(from lines: [String], parser: AnthropicStreamParser) throws -> [ExecutorEvent] {
    var parser = parser
    var events: [ExecutorEvent] = []
    for (offset, line) in lines.enumerated() {
        events.append(contentsOf: try parser.consume(line, lineNumber: offset + 1))
    }
    return events
}

private func fixtureLines(_ name: String) throws -> [String] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "sse"))
    return try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
}
