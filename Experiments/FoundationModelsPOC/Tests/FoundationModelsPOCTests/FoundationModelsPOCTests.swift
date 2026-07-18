import Foundation
import FoundationModels
import Testing
@testable import FoundationModelsPOC

@available(macOS 27.0, *)
@Test("Apple Transcript has a canonical Codable round trip for standard entries")
func transcriptArchiveRoundTrips() throws {
    let transcript = Transcript(entries: [
        .prompt(
            Transcript.Prompt(
                id: "prompt-1",
                metadata: ["neutral.request": "one", "deepseek.state": "opaque"],
                segments: [.text(.init(id: "prompt-text", content: "Read a fixture."))]
            )
        ),
        .reasoning(
            Transcript.Reasoning(
                id: "reasoning-1",
                metadata: ["google.thought_signature": "signature"],
                segments: [.text(.init(id: "reasoning-text", content: "I should use the tool."))],
                signature: Data("signature".utf8)
            )
        ),
        .toolCalls(
            Transcript.ToolCalls(
                id: "calls-1",
                [
                    Transcript.ToolCall(
                        id: "call-1",
                        metadata: ["anthropic.signature": "opaque"],
                        toolName: "read_fixture",
                        arguments: try GeneratedContent(json: #"{"path":"answer.txt"}"#)
                    ),
                ]
            )
        ),
        .toolOutput(
            Transcript.ToolOutput(
                id: "call-1",
                toolName: "read_fixture",
                segments: [.text(.init(id: "output-text", content: "42"))]
            )
        ),
        .response(
            Transcript.Response(
                id: "response-1",
                metadata: ["neutral.finish": "stop"],
                segments: [.text(.init(id: "response-text", content: "The answer is 42."))]
            )
        ),
    ])

    let archive = TranscriptArchive(transcript: transcript)
    let encoded = try archive.encoded()
    let decoded = try TranscriptArchive.decode(encoded)
    let reencoded = try decoded.encoded()
    #expect(encoded == reencoded)
    // Xcode 27 beta 1 decodes metadata through internal type erasure, so Transcript's
    // Equatable conformance is not stable across this otherwise canonical round trip.
    #expect(decoded.transcript != archive.transcript)
}

@available(macOS 27.0, *)
@Test("Provider switching strips only foreign metadata")
func transcriptArchiveStripsForeignProviderMetadata() throws {
    let transcript = Transcript(entries: [
        .reasoning(
            Transcript.Reasoning(
                id: "reasoning-1",
                metadata: [
                    "deepseek.reasoning_content": "x",
                    "neutral.id": "1",
                    "anthropic.signature": "y",
                ],
                segments: [.text(.init(content: "reasoning"))],
                signature: Data("signature".utf8)
            )
        ),
    ])

    let replayed = try TranscriptArchive(transcript: transcript).replay(for: "anthropic")
    guard case let .reasoning(reasoning) = replayed.transcript[0] else {
        Issue.record("Expected a reasoning entry")
        return
    }
    #expect(Set(reasoning.metadata.keys) == Set(["neutral.id", "anthropic.signature"]))
    #expect(reasoning.signature == Data("signature".utf8))
}

@Test("OpenAI-compatible fixtures preserve partial tool arguments and usage")
func openAIParserPreservesPartialToolArguments() throws {
    let events = try OpenAICompatibleFixtureParser.events(from: fixtureLines("openai-tool-stream"))
    #expect(events.contains(.toolCall(
        index: 0,
        id: "call_1",
        name: "read_fixture",
        argumentsFragment: #"{"path":""#,
        metadata: [:]
    )))
    #expect(events.contains(.toolCall(
        index: 0,
        id: "call_1",
        name: "read_fixture",
        argumentsFragment: #"answer.txt"}"#,
        metadata: [:]
    )))
    #expect(events.contains(.usage(input: 17, output: 8)))
    #expect(events.contains(.finish(reason: "tool_calls")))
}

@Test("Google thought signatures survive their nested provider field")
func googleParserPreservesThoughtSignature() throws {
    let events = try OpenAICompatibleFixtureParser.events(from: fixtureLines("google-reasoning-stream"))
    #expect(events.contains(.reasoning(
        text: "I should read the fixture.",
        signature: "Z29vZ2xlLXNpZw==",
        metadata: ["google.thought_signature": "Z29vZ2xlLXNpZw=="]
    )))
}

@Test("Anthropic block starts supply identity to later argument fragments")
func anthropicParserPreservesToolIdentity() throws {
    let events = try AnthropicFixtureParser.events(from: fixtureLines("anthropic-tool-stream"))
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
    #expect(throws: FixtureParserError.missingToolBlock(index: 3, line: 1)) {
        try AnthropicFixtureParser.events(from: [line])
    }
}

@available(macOS 27.0, *)
@Test("Representative MCP object schema converts to Apple's GenerationSchema")
func schemaBridgeBuildsGenerationSchema() throws {
    let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "path": ["type": "string"],
            "mode": ["type": "string", "enum": ["brief", "full"]],
            "limit": ["type": "integer"],
        ],
        "required": ["path"],
    ]
    let generationSchema = try SchemaBridge.generationSchema(named: "ReadFixture", from: schema)
    let encoded = try JSONEncoder().encode(generationSchema)
    #expect(!encoded.isEmpty)
}

@Test("Lossy schema keywords and mixed enums fail with their exact path")
func schemaBridgeRejectsLossySchemas() {
    #expect(throws: SchemaBridgeError.unsupported(keyword: "anyOf", path: "$.properties.mode")) {
        try SchemaBridge.parse(["anyOf": []], path: "$.properties.mode")
    }
    #expect(throws: SchemaBridgeError.invalid(
        keyword: "enum",
        path: "$.enum[1]",
        reason: "only string enum values are supported"
    )) {
        try SchemaBridge.parse(["type": "string", "enum": ["one", 2]])
    }
    #expect(throws: SchemaBridgeError.unsupported(keyword: "description", path: "$")) {
        try SchemaBridge.parse(["type": "string", "description": "Must not be discarded"])
    }
}

@Test("Fixture reads reject symlink escapes")
func fixtureToolRejectsSymlinkEscape() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = temporary.appendingPathComponent("root", isDirectory: true)
    let outside = temporary.appendingPathComponent("outside.txt")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "secret".write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("escape.txt"),
        withDestinationURL: outside
    )
    defer { try? FileManager.default.removeItem(at: temporary) }

    let tool = ReadFixtureTool(root: root)
    #expect(throws: FixtureReadError.outsideRoot(path: "escape.txt")) {
        try tool.call(path: "escape.txt")
    }
}

@Test("Tool output is traced in full before the model-facing budget is applied")
func fixtureToolTracesBeforeBudgeting() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "complete-output".write(
        to: root.appendingPathComponent("long.txt"),
        atomically: true,
        encoding: .utf8
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = FixtureToolRunner(root: root, maximumModelCharacters: 8)
    let modelOutput = try await runner.run(path: "long.txt")
    let trace = await runner.trace()

    #expect(modelOutput.hasPrefix("complete"))
    #expect(modelOutput.contains("Output truncated"))
    #expect(trace.first?.rawOutput == "complete-output")
    #expect(trace.first?.modelOutput == modelOutput)
}

@available(macOS 27.0, *)
@Test("The host fixture implementation bridges to a real Foundation Models Tool")
func foundationModelsToolBridgeConforms() {
    let root = Bundle.module.bundleURL
    let tools: [any Tool] = [FoundationModelsReadFixtureTool(root: root)]
    #expect(tools.first?.name == "read_fixture")
}

@available(macOS 27.0, *)
@Test("The Foundation Models provider surface links")
func foundationModelsProviderSurfaceLinks() {
    #expect(FoundationModelsSurface.requiredCapabilities.contains(.toolCalling))
}

private func fixtureLines(_ name: String) throws -> [String] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "sse"))
    return try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
}
