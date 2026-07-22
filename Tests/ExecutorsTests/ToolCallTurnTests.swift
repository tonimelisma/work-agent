import Foundation
import FoundationModels
import RuntimeTesting
import Testing
@testable import Executors

// REQ: FR-084, NFR-011 — a provider that narrates before calling a tool must still
// complete the tool cycle. Apple's session throws "Session ended without producing a
// response" whenever one generation yields both a Response entry and a ToolCalls
// entry (measured on OS 27 in both orders, and `replaceTextSegment("")` does not undo
// it — the channel has no entry-removal action). MiniMax streams its `<think>` block
// through `delta.content` and Meta a plain preamble, so both hard-failed until the
// bridge started withholding assistant text on a tool-call turn.
//
// These drive the real `ExecutorChannelBridge` through a real `LanguageModelSession`
// with a scripted transport, so they exercise the shipping code path offline — the
// bridge's own event values are un-introspectable, so behavior is asserted through
// the session, plus event counts at the bridge seam.

@Generable
struct SentinelProbeArguments: Sendable {
    @Guide(description: "Not used; call with no meaningful input")
    var note: String?
}

private struct SentinelProbeTool: Tool, Sendable {
    let name = "sentinel_probe"
    let description = "A probe tool. Call it, then reply with exactly what it returns."
    let recorder: CallCountBox

    func call(arguments _: SentinelProbeArguments) async throws -> String {
        recorder.increment()
        return "PROBE-SENTINEL"
    }
}

final class CallCountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        stored += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private final class TurnCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        stored += 1
        return stored
    }
}

/// Replays a scripted list of `ExecutorEvent`s per turn through the production
/// bridge, exactly as a live executor's stream loop does.
private func bridgedModel(
    firstTurn: [ExecutorEvent], secondTurn: [ExecutorEvent]
) -> ScriptedLanguageModel {
    let turns = TurnCounter()
    return ScriptedLanguageModel { request, channel in
        let events = turns.next() == 1 ? firstTurn : secondTurn
        var bridge = ExecutorChannelBridge(
            requestID: request.id, providerID: "scripted",
            toolCallsPossible: !request.enabledToolDefinitions.isEmpty
        )
        for event in events {
            for channelEvent in bridge.channelEvents(for: event) {
                await channel.send(channelEvent)
            }
        }
        for channelEvent in try bridge.completionEvents() {
            await channel.send(channelEvent)
        }
    }
}

private let toolCallEvent = ExecutorEvent.toolCall(
    index: 0, id: "call_1", name: "sentinel_probe", argumentsFragment: "{}", metadata: [:]
)
private let finalAnswer = [ExecutorEvent.response(text: "PROBE-SENTINEL"), .finish(reason: "stop")]

@Suite("Tool-call turns: assistant text never becomes a response entry")
struct ToolCallTurnTests {
    @Test("FR-084: a preamble before the tool call still completes the tool cycle")
    func preambleBeforeToolCall() async throws {
        let calls = CallCountBox()
        let model = bridgedModel(
            firstTurn: [
                .response(text: "<think>I should call the tool.</think>"),
                toolCallEvent,
                .usage(input: 10, output: 5),
                .finish(reason: "tool_calls"),
            ],
            secondTurn: finalAnswer
        )
        let session = LanguageModelSession(model: model, tools: [SentinelProbeTool(recorder: calls)])
        let response = try await session.respond(to: "go")
        #expect(calls.value == 1)
        #expect(response.content == "PROBE-SENTINEL")
    }

    @Test("FR-084: a preamble *after* the tool call is withheld too — order is irrelevant")
    func preambleAfterToolCall() async throws {
        let calls = CallCountBox()
        let model = bridgedModel(
            firstTurn: [
                toolCallEvent,
                .response(text: "Calling the tool now."),
                .finish(reason: "tool_calls"),
            ],
            secondTurn: finalAnswer
        )
        let session = LanguageModelSession(model: model, tools: [SentinelProbeTool(recorder: calls)])
        let response = try await session.respond(to: "go")
        #expect(calls.value == 1)
        #expect(response.content == "PROBE-SENTINEL")
    }

    @Test("FR-084: a tool-call turn with no text at all is unaffected")
    func toolCallWithoutText() async throws {
        let calls = CallCountBox()
        let model = bridgedModel(
            firstTurn: [toolCallEvent, .finish(reason: "tool_calls")], secondTurn: finalAnswer
        )
        let session = LanguageModelSession(model: model, tools: [SentinelProbeTool(recorder: calls)])
        let response = try await session.respond(to: "go")
        #expect(calls.value == 1)
        #expect(response.content == "PROBE-SENTINEL")
    }

    @Test("FR-084: a text-only turn with tools enabled still delivers its text")
    func textOnlyTurnWithToolsEnabled() async throws {
        let model = bridgedModel(
            firstTurn: [.response(text: "Just answering. "), .response(text: "No tool needed."),
                        .usage(input: 3, output: 4), .finish(reason: "stop")],
            secondTurn: finalAnswer
        )
        let session = LanguageModelSession(
            model: model, tools: [SentinelProbeTool(recorder: CallCountBox())]
        )
        let response = try await session.respond(to: "go")
        #expect(response.content == "Just answering. No tool needed.")
    }

    @Test("FR-084: with no tools enabled, text is not buffered — it streams as it arrives")
    func textStreamsWhenNoToolsAreEnabled() throws {
        var bridge = ExecutorChannelBridge(
            requestID: UUID(), providerID: "scripted", toolCallsPossible: false
        )
        #expect(bridge.channelEvents(for: .response(text: "hello")).count == 1)
        #expect(try bridge.completionEvents().isEmpty)
    }

    @Test("FR-084: with tools enabled, no response event is emitted before the stream ends")
    func textIsWithheldWhenToolsAreEnabled() throws {
        var bridge = ExecutorChannelBridge(
            requestID: UUID(), providerID: "scripted", toolCallsPossible: true
        )
        #expect(bridge.channelEvents(for: .response(text: "hello")).isEmpty)
        #expect(bridge.channelEvents(for: toolCallEvent).count == 1)
        // Only the usage event: the buffered preamble is dropped on a tool-call turn.
        #expect(bridge.channelEvents(for: .usage(input: 1, output: 2)).isEmpty)
        #expect(try bridge.completionEvents().count == 1)
    }

    @Test("NFR-011: a stream that produces nothing fails named, not as an opaque session error")
    func emptyGenerationIsNamed() throws {
        var bridge = ExecutorChannelBridge(
            requestID: UUID(), providerID: "acme", toolCallsPossible: true
        )
        #expect(bridge.channelEvents(for: .usage(input: 1, output: 0)).isEmpty)
        #expect(bridge.channelEvents(for: .finish(reason: "length")).isEmpty)
        #expect {
            try bridge.completionEvents()
        } throws: { error in
            guard case let ProviderStreamError.event(provider, type, message) = error else { return false }
            return provider == "acme" && type == "empty_generation"
                && message?.contains("length") == true
        }
    }
}
