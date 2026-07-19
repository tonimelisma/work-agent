import Foundation
import FoundationModels
import Testing
@testable import RuntimeCore

// REQ: FR-006 — migrated from Experiments/FoundationModelsPOC's FoundationModelsPOCTests.swift.

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
}

@Test("Provider switching strips foreign metadata and typed reasoning signatures")
func transcriptArchiveStripsForeignProviderMetadata() throws {
    let transcript = Transcript(entries: [
        .reasoning(
            Transcript.Reasoning(
                id: "reasoning-1",
                metadata: [
                    "deepseek.reasoning_content": "x",
                    "google.thought_signature": "signature",
                    "neutral.id": "1",
                    TranscriptArchive.signatureProviderMetadataKey: "google",
                    "anthropic.signature": "y",
                ],
                segments: [.text(.init(content: "reasoning"))],
                signature: Data("signature".utf8)
            )
        ),
    ])

    let archive = TranscriptArchive(transcript: transcript)
    let replayed = try archive.replay(to: "anthropic")
    guard case let .reasoning(reasoning) = replayed.transcript[0] else {
        Issue.record("Expected a reasoning entry")
        return
    }
    #expect(Set(reasoning.metadata.keys) == Set(["neutral.id", "anthropic.signature"]))
    #expect(reasoning.signature == nil)

    let sameProvider = try archive.replay(to: "google")
    guard case let .reasoning(sameProviderReasoning) = sameProvider.transcript[0] else {
        Issue.record("Expected a reasoning entry")
        return
    }
    #expect(sameProviderReasoning.signature == Data("signature".utf8))
    #expect(Set(sameProviderReasoning.metadata.keys) == Set([
        "neutral.id", "neutral.signature_provider", "google.thought_signature",
    ]))
}
