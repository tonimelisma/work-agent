import Foundation
import FoundationModels
import Testing
@testable import FoundationModelsPOC

@Suite("Foundation Models session semantics", .serialized)
struct SessionSemanticsTests {
    @Test("Cancellation reaches a running provider executor")
    func executorCancellation() async throws {
        let fixture = try await SemanticsFixture(behavior: .blockExecutor)
        let session = LanguageModelSession(model: fixture.model)
        let response = Task {
            _ = try await session.respond(to: "Wait")
        }

        try await fixture.state.waitUntil { $0.executorStarted }
        response.cancel()

        await #expect(throws: CancellationError.self) {
            try await response.value
        }
        #expect(await fixture.state.snapshot.executorCancelled)
    }

    @Test("Cancellation reaches a running tool task")
    func toolCancellation() async throws {
        let fixture = try await SemanticsFixture(behavior: .callBlockingTool)
        let tool = SemanticsTool(state: fixture.state, behavior: .block)
        let session = LanguageModelSession(model: fixture.model, tools: [tool])
        let response = Task {
            _ = try await session.respond(
                to: "Use the tool",
                options: GenerationOptions(toolCallingMode: .required)
            )
        }

        try await fixture.state.waitUntil { $0.toolStarts == ["blocked"] }
        response.cancel()

        do {
            try await response.value
            Issue.record("Expected cancellation to terminate the response")
        } catch let error as LanguageModelSession.ToolCallError {
            #expect(error.underlyingError is CancellationError)
        } catch {
            Issue.record("Expected ToolCallError wrapping CancellationError, got \(error)")
        }
        #expect(await fixture.state.snapshot.toolCancellations == ["blocked"])
    }

    @Test("Revert policy makes a failed streaming attempt retryable without duplicate content")
    func failedAttemptCanBeRetriedAtomically() async throws {
        let fixture = try await SemanticsFixture(behavior: .failOnceAfterPartialResponse)
        let session = LanguageModelSession(model: fixture.model)
        session.transcriptErrorHandlingPolicy = .revertTranscript

        await #expect(throws: SemanticsError.partialStreamFailure) {
            try await session.respond(to: "First attempt")
        }
        #expect(!session.transcript.containsResponseText("discard-me"))

        let response = try await session.respond(to: "Retry")
        #expect(response.content == "recovered")
        #expect(!session.transcript.containsResponseText("discard-me"))
        #expect(session.transcript.responseTexts == ["recovered"])
        #expect(await fixture.state.snapshot.requestCount == 2)
    }

    @Test("Thrown tool errors terminate the session instead of becoming model-visible correction output")
    func thrownToolErrorsAreNotSelfCorrected() async throws {
        let fixture = try await SemanticsFixture(behavior: .callFailingTool)
        let tool = SemanticsTool(state: fixture.state, behavior: .fail)
        let session = LanguageModelSession(model: fixture.model, tools: [tool])
        session.transcriptErrorHandlingPolicy = .preserveTranscript

        do {
            _ = try await session.respond(
                to: "Use the tool",
                options: GenerationOptions(toolCallingMode: .required)
            )
            Issue.record("Expected the failing tool to terminate the response")
        } catch {
            #expect(error is LanguageModelSession.ToolCallError)
        }

        let snapshot = await fixture.state.snapshot
        #expect(snapshot.requestCount == 1)
        #expect(snapshot.toolStarts == ["failure"])
        #expect(session.transcript.toolOutputIDs.isEmpty)
    }

    @Test("Apple runs independent tool calls concurrently and commits outputs in source order")
    func concurrentToolScheduling() async throws {
        let fixture = try await SemanticsFixture(behavior: .callTwoTools)
        let tool = SemanticsTool(state: fixture.state, behavior: .timed)
        let session = LanguageModelSession(model: fixture.model, tools: [tool])

        let response = try await session.respond(
            to: "Use both tools",
            options: GenerationOptions(toolCallingMode: .required)
        )

        #expect(response.content == "both-complete")
        let snapshot = await fixture.state.snapshot
        #expect(snapshot.maximumActiveTools == 2)
        #expect(snapshot.toolCompletions == ["fast", "slow"])
        #expect(session.transcript.toolOutputIDs == ["call-slow", "call-fast"])
    }

    @Test("Session response snapshots expose final text and usage but may coalesce executor events")
    func responseSnapshotsCanCoalesceEvents() async throws {
        let fixture = try await SemanticsFixture(behavior: .streamResponse)
        let session = LanguageModelSession(model: fixture.model)
        let stream = session.streamResponse(to: "Stream")
        var contents: [String] = []
        var finalUsage = 0

        for try await snapshot in stream {
            contents.append(snapshot.content)
            finalUsage = snapshot.usage.totalTokenCount
        }

        #expect(contents.last == "first-second")
        #expect(!contents.isEmpty)
        #expect(contents.allSatisfy { $0 == "first" || $0 == "first-second" })
        #expect(finalUsage == 11)
    }

    @Test("A filtered archived transcript can reconstruct a session on another provider")
    func reconstructedSessionSwitchesProvider() async throws {
        let first = try await SemanticsFixture(behavior: .signedResponse(provider: "alpha"))
        let firstSession = LanguageModelSession(model: first.model)
        _ = try await firstSession.respond(to: "First")

        let replay = try TranscriptArchive(transcript: firstSession.transcript).replay(to: "beta")
        let second = try await SemanticsFixture(behavior: .signedResponse(provider: "beta"))
        let secondSession = LanguageModelSession(model: second.model, transcript: replay.transcript)
        let response = try await secondSession.respond(to: "Second")

        #expect(response.content == "beta-response")
        let received = await second.state.snapshot.requestTranscripts
        #expect(received.count == 1)
        #expect(!received[0].containsProviderMetadata("alpha"))
        #expect(!received[0].containsReasoningSignature)
    }
}

private enum SemanticsBehavior: Hashable, Sendable {
    case blockExecutor
    case callBlockingTool
    case failOnceAfterPartialResponse
    case callFailingTool
    case callTwoTools
    case streamResponse
    case signedResponse(provider: String)
}

private enum SemanticsError: Error, Equatable, Sendable {
    case partialStreamFailure
    case toolFailure
}

private struct SemanticsModel: LanguageModel {
    typealias Executor = SemanticsExecutor

    let capabilities = LanguageModelCapabilities([.reasoning, .toolCalling])
    let executorConfiguration: SemanticsExecutor.Configuration
}

private struct SemanticsExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {
        let id: UUID
        let behavior: SemanticsBehavior
    }

    typealias Model = SemanticsModel
    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: SemanticsModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let state = try await SemanticsRegistry.shared.state(for: configuration.id)
        let attempt = await state.record(request: request.transcript)

        switch configuration.behavior {
        case .blockExecutor:
            await state.markExecutorStarted()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await state.markExecutorCancelled()
                throw error
            }

        case .callBlockingTool:
            if request.transcript.toolOutputIDs.isEmpty {
                await channel.send(.toolCalls(
                    entryID: "calls",
                    action: .toolCall(
                        id: "call-blocked",
                        name: "semantics_tool",
                        action: .appendArguments(#"{"path":"blocked"}"#, tokenCount: 2)
                    )
                ))
            } else {
                await channel.send(.response(
                    entryID: "response",
                    action: .appendText("unexpected", tokenCount: 1)
                ))
            }

        case .failOnceAfterPartialResponse:
            if attempt == 1 {
                await channel.send(.response(
                    entryID: "partial",
                    action: .appendText("discard-me", tokenCount: 2)
                ))
                throw SemanticsError.partialStreamFailure
            }
            await channel.send(.response(
                entryID: "recovered",
                action: .appendText("recovered", tokenCount: 1)
            ))

        case .callFailingTool:
            await channel.send(.toolCalls(
                entryID: "calls",
                action: .toolCall(
                    id: "call-failure",
                    name: "semantics_tool",
                    action: .appendArguments(#"{"path":"failure"}"#, tokenCount: 2)
                )
            ))

        case .callTwoTools:
            if request.transcript.toolOutputIDs.count == 2 {
                await channel.send(.response(
                    entryID: "response",
                    action: .appendText("both-complete", tokenCount: 2)
                ))
            } else {
                await channel.send(.toolCalls(
                    entryID: "calls",
                    action: .toolCall(
                        id: "call-slow",
                        name: "semantics_tool",
                        action: .appendArguments(#"{"path":"slow"}"#, tokenCount: 2)
                    )
                ))
                await channel.send(.toolCalls(
                    entryID: "calls",
                    action: .toolCall(
                        id: "call-fast",
                        name: "semantics_tool",
                        action: .appendArguments(#"{"path":"fast"}"#, tokenCount: 2)
                    )
                ))
            }

        case .streamResponse:
            await channel.send(.response(
                entryID: "stream",
                action: .appendText("first", tokenCount: 2)
            ))
            try await Task.sleep(for: .milliseconds(100))
            await channel.send(.response(
                entryID: "stream",
                action: .appendText("-second", tokenCount: 2)
            ))
            await channel.send(.response(
                entryID: "stream",
                action: .updateUsage(
                    input: .init(totalTokenCount: 7, cachedTokenCount: 0),
                    output: .init(totalTokenCount: 4, reasoningTokenCount: 0)
                )
            ))

        case let .signedResponse(provider):
            await channel.send(.reasoning(
                entryID: "reasoning-\(provider)",
                action: .appendText("private", tokenCount: 1)
            ))
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
            await channel.send(.response(
                entryID: "response-\(provider)",
                action: .appendText("\(provider)-response", tokenCount: 1)
            ))
        }
    }
}

private struct SemanticsFixture {
    let model: SemanticsModel
    let state: SemanticsState

    init(behavior: SemanticsBehavior) async throws {
        let id = UUID()
        let state = SemanticsState()
        try await SemanticsRegistry.shared.install(state, for: id)
        self.state = state
        model = SemanticsModel(
            executorConfiguration: .init(id: id, behavior: behavior)
        )
    }
}

private actor SemanticsRegistry {
    static let shared = SemanticsRegistry()
    private var states: [UUID: SemanticsState] = [:]

    func install(_ state: SemanticsState, for id: UUID) throws {
        states[id] = state
    }

    func state(for id: UUID) throws -> SemanticsState {
        guard let state = states[id] else { throw SemanticsRegistryError.missingState }
        return state
    }
}

private enum SemanticsRegistryError: Error {
    case missingState
}

private actor SemanticsState {
    struct Snapshot: Sendable {
        var requestCount = 0
        var requestTranscripts: [Transcript] = []
        var executorStarted = false
        var executorCancelled = false
        var toolStarts: [String] = []
        var toolCompletions: [String] = []
        var toolCancellations: [String] = []
        var activeTools = 0
        var maximumActiveTools = 0
    }

    private var value = Snapshot()

    var snapshot: Snapshot { value }

    func record(request: Transcript) -> Int {
        value.requestCount += 1
        value.requestTranscripts.append(request)
        return value.requestCount
    }

    func markExecutorStarted() {
        value.executorStarted = true
    }

    func markExecutorCancelled() {
        value.executorCancelled = true
    }

    func toolStarted(_ name: String) {
        value.toolStarts.append(name)
        value.activeTools += 1
        value.maximumActiveTools = max(value.maximumActiveTools, value.activeTools)
    }

    func toolCompleted(_ name: String) {
        value.toolCompletions.append(name)
        value.activeTools -= 1
    }

    func toolCancelled(_ name: String) {
        value.toolCancellations.append(name)
        value.activeTools -= 1
    }

    func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: @Sendable (Snapshot) -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !predicate(value) {
            guard clock.now < deadline else { throw SemanticsWaitError.timedOut }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

private enum SemanticsWaitError: Error {
    case timedOut
}

private enum SemanticsToolBehavior: Sendable {
    case block
    case fail
    case timed
}

private struct SemanticsTool: Tool, Sendable {
    let name = "semantics_tool"
    let description = "A deterministic session-semantics fixture."
    let state: SemanticsState
    let behavior: SemanticsToolBehavior

    func call(arguments: ReadFixtureArguments) async throws -> String {
        let value = arguments.path
        await state.toolStarted(value)

        do {
            switch behavior {
            case .block:
                try await Task.sleep(for: .seconds(60))
            case .fail:
                throw SemanticsError.toolFailure
            case .timed:
                try await Task.sleep(for: value == "slow" ? .milliseconds(50) : .milliseconds(5))
            }
            await state.toolCompleted(value)
            return "\(value)-output"
        } catch is CancellationError {
            await state.toolCancelled(value)
            throw CancellationError()
        } catch {
            await state.toolCompleted(value)
            throw error
        }
    }
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
                calls.contains { call in
                    call.metadata.keys.contains { $0.hasPrefix("\(provider).") }
                }
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
