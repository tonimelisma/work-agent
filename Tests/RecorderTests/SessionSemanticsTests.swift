import Foundation
import FoundationModels
import Testing
@testable import Recorder
import RuntimeTesting

// REQ: agent-loop-implementation.md §3, §8 — the durability guarantees Recorder
// is built on top of (cancellation, revert-on-failure, tool-call ordering) are
// Apple's session semantics, not Recorder's own code. Migrated from
// Experiments/FoundationModelsPOC/Tests/FoundationModelsPOCTests/SessionSemanticsTests.swift
// onto the reusable `ScriptedLanguageModel` (RuntimeTesting) instead of an ad hoc
// per-test executor, so the assumption keeps being checked after the POC is deleted.

private actor Flag {
    private var value = false
    func set(_ newValue: Bool) { value = newValue }
    var current: Bool { value }

    func waitUntilTrue(timeout: Duration = .seconds(2)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !value {
            guard clock.now < deadline else { throw SemanticsTimeout.timedOut }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

private enum SemanticsTimeout: Error { case timedOut }
private enum SemanticsError: Error, Equatable { case partialStreamFailure, toolFailure }

@Generable
private struct SemanticsArguments: Sendable {
    @Guide(description: "path")
    var path: String
}

@Test("Cancellation reaches a running provider executor")
func executorCancellation() async throws {
    let started = Flag()
    let cancelled = Flag()
    let model = ScriptedLanguageModel { _, _ in
        await started.set(true)
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            await cancelled.set(true)
            throw error
        }
    }
    let session = LanguageModelSession(model: model)
    let response = Task { _ = try await session.respond(to: "Wait") }

    try await started.waitUntilTrue()
    response.cancel()

    await #expect(throws: CancellationError.self) { try await response.value }
    #expect(await cancelled.current)
}

@Test("Cancellation reaches a running tool task")
func toolCancellation() async throws {
    let toolStarted = Flag()
    let toolCancelled = Flag()
    let tool = SemanticsTool(behavior: .block, started: toolStarted, cancelled: toolCancelled)

    let model = ScriptedLanguageModel { request, channel in
        if request.transcript.toolOutputIDs.isEmpty {
            await channel.send(.toolCalls(
                entryID: "calls",
                action: .toolCall(
                    id: "call-blocked", name: "semantics_tool",
                    action: .appendArguments(#"{"path":"blocked"}"#, tokenCount: 2)
                )
            ))
        } else {
            await channel.send(.response(entryID: "response", action: .appendText("unexpected", tokenCount: 1)))
        }
    }
    let session = LanguageModelSession(model: model, tools: [tool])
    let response = Task {
        _ = try await session.respond(to: "Use the tool", options: GenerationOptions(toolCallingMode: .required))
    }

    try await toolStarted.waitUntilTrue()
    response.cancel()

    do {
        try await response.value
        Issue.record("Expected cancellation to terminate the response")
    } catch let error as LanguageModelSession.ToolCallError {
        #expect(error.underlyingError is CancellationError)
    } catch {
        Issue.record("Expected ToolCallError wrapping CancellationError, got \(error)")
    }
    #expect(await toolCancelled.current)
}

@Test("Revert policy makes a failed streaming attempt retryable without duplicate content")
func failedAttemptCanBeRetriedAtomically() async throws {
    let requestCount = Counter()
    let model = ScriptedLanguageModel { _, channel in
        let attempt = await requestCount.increment()
        if attempt == 1 {
            await channel.send(.response(entryID: "partial", action: .appendText("discard-me", tokenCount: 2)))
            throw SemanticsError.partialStreamFailure
        }
        await channel.send(.response(entryID: "recovered", action: .appendText("recovered", tokenCount: 1)))
    }
    let session = LanguageModelSession(model: model)
    session.transcriptErrorHandlingPolicy = .revertTranscript

    await #expect(throws: SemanticsError.partialStreamFailure) {
        try await session.respond(to: "First attempt")
    }
    #expect(!session.transcript.containsResponseText("discard-me"))

    let response = try await session.respond(to: "Retry")
    #expect(response.content == "recovered")
    #expect(!session.transcript.containsResponseText("discard-me"))
    #expect(session.transcript.responseTexts == ["recovered"])
    #expect(await requestCount.current == 2)
}

@Test("Thrown tool errors terminate the session instead of becoming model-visible correction output")
func thrownToolErrorsAreNotSelfCorrected() async throws {
    let toolStarted = Flag()
    let tool = SemanticsTool(behavior: .fail, started: toolStarted, cancelled: Flag())
    let model = ScriptedLanguageModel { _, channel in
        await channel.send(.toolCalls(
            entryID: "calls",
            action: .toolCall(
                id: "call-failure", name: "semantics_tool",
                action: .appendArguments(#"{"path":"failure"}"#, tokenCount: 2)
            )
        ))
    }
    let session = LanguageModelSession(model: model, tools: [tool])
    session.transcriptErrorHandlingPolicy = .preserveTranscript

    do {
        _ = try await session.respond(to: "Use the tool", options: GenerationOptions(toolCallingMode: .required))
        Issue.record("Expected the failing tool to terminate the response")
    } catch {
        #expect(error is LanguageModelSession.ToolCallError)
    }
    #expect(session.transcript.toolOutputIDs.isEmpty)
}

@Test("Apple runs independent tool calls concurrently and commits outputs in source order")
func concurrentToolScheduling() async throws {
    let tool = SemanticsTool(behavior: .timed, started: Flag(), cancelled: Flag())
    let model = ScriptedLanguageModel { request, channel in
        if request.transcript.toolOutputIDs.count == 2 {
            await channel.send(.response(entryID: "response", action: .appendText("both-complete", tokenCount: 2)))
        } else {
            await channel.send(.toolCalls(
                entryID: "calls",
                action: .toolCall(
                    id: "call-slow", name: "semantics_tool",
                    action: .appendArguments(#"{"path":"slow"}"#, tokenCount: 2)
                )
            ))
            await channel.send(.toolCalls(
                entryID: "calls",
                action: .toolCall(
                    id: "call-fast", name: "semantics_tool",
                    action: .appendArguments(#"{"path":"fast"}"#, tokenCount: 2)
                )
            ))
        }
    }
    let session = LanguageModelSession(model: model, tools: [tool])
    let response = try await session.respond(
        to: "Use both tools", options: GenerationOptions(toolCallingMode: .required)
    )
    #expect(response.content == "both-complete")
    #expect(session.transcript.toolOutputIDs == ["call-slow", "call-fast"])
}

@Test("A filtered archived transcript can reconstruct a session on another provider")
func reconstructedSessionSwitchesProvider() async throws {
    let first = ScriptedLanguageModel { _, channel in
        await sendSigned(provider: "alpha", to: channel)
    }
    let firstSession = LanguageModelSession(model: first)
    _ = try await firstSession.respond(to: "First")

    let replay = try TranscriptArchive(transcript: firstSession.transcript).replay(to: "beta")

    let receivedTranscripts = TranscriptBox()
    let second = ScriptedLanguageModel { request, channel in
        await receivedTranscripts.append(request.transcript)
        await sendSigned(provider: "beta", to: channel)
    }
    let secondSession = LanguageModelSession(model: second, transcript: replay.transcript)
    let response = try await secondSession.respond(to: "Second")

    #expect(response.content == "beta-response")
    let received = await receivedTranscripts.all
    #expect(received.count == 1)
    #expect(!received[0].containsProviderMetadata("alpha"))
    #expect(!received[0].containsReasoningSignature)
}

private func sendSigned(provider: String, to channel: LanguageModelExecutorGenerationChannel) async {
    await channel.send(.reasoning(entryID: "reasoning-\(provider)", action: .appendText("private", tokenCount: 1)))
    await channel.send(.reasoning(
        entryID: "reasoning-\(provider)",
        action: .updateSignature(Data("\(provider)-signature".utf8), tokenCount: 1)
    ))
    await channel.send(.reasoning(
        entryID: "reasoning-\(provider)",
        action: .updateMetadata([
            "\(provider).signature": "opaque",
            TranscriptArchive.signatureProviderMetadataKey: provider,
        ])
    ))
    await channel.send(.response(entryID: "response-\(provider)", action: .appendText("\(provider)-response", tokenCount: 1)))
}

private actor Counter {
    private var value = 0
    func increment() -> Int { value += 1; return value }
    var current: Int { value }
}

private enum SemanticsToolBehavior: Sendable { case block, fail, timed }

private struct SemanticsTool: Tool, Sendable {
    let name = "semantics_tool"
    let description = "A deterministic session-semantics fixture."
    let behavior: SemanticsToolBehavior
    let started: Flag
    let cancelled: Flag

    func call(arguments: SemanticsArguments) async throws -> String {
        let value = arguments.path
        await started.set(true)
        do {
            switch behavior {
            case .block:
                try await Task.sleep(for: .seconds(60))
            case .fail:
                throw SemanticsError.toolFailure
            case .timed:
                try await Task.sleep(for: value == "slow" ? .milliseconds(50) : .milliseconds(5))
            }
            return "\(value)-output"
        } catch is CancellationError {
            await cancelled.set(true)
            throw CancellationError()
        }
    }
}

private actor TranscriptBox {
    private var transcripts: [Transcript] = []
    func append(_ transcript: Transcript) { transcripts.append(transcript) }
    var all: [Transcript] { transcripts }
}

private extension Transcript {
    var responseTexts: [String] {
        compactMap { entry in
            guard case let .response(response) = entry else { return nil }
            return response.segments.compactMap { segment in
                guard case let .text(text) = segment else { return nil }
                return text.content
            }.joined()
        }
    }

    var toolOutputIDs: [String] {
        compactMap { entry in
            guard case let .toolOutput(output) = entry else { return nil }
            return output.id
        }
    }

    var containsReasoningSignature: Bool {
        contains { entry in
            guard case let .reasoning(reasoning) = entry else { return false }
            return reasoning.signature != nil
        }
    }

    func containsResponseText(_ text: String) -> Bool {
        responseTexts.contains { $0.contains(text) }
    }

    func containsProviderMetadata(_ provider: String) -> Bool {
        contains { entry in
            switch entry {
            case let .prompt(prompt):
                prompt.metadata.keys.contains { $0.hasPrefix("\(provider).") }
            case let .reasoning(reasoning):
                reasoning.metadata.keys.contains { $0.hasPrefix("\(provider).") }
            case let .toolCalls(calls):
                calls.contains { call in call.metadata.keys.contains { $0.hasPrefix("\(provider).") } }
            case let .response(response):
                response.metadata.keys.contains { $0.hasPrefix("\(provider).") }
            case .instructions, .toolOutput:
                false
            @unknown default:
                false
            }
        }
    }
}
