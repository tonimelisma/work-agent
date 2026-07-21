import Foundation
import FoundationModels
import Testing

// REQ: ROADMAP item 2 — every provider claim becomes a verified fact. This target
// hits real provider APIs and is gated per-test on the relevant `.env` key being
// present, so plain `swift test` (no keys sourced) skips every test here silently.
//
// Run with keys sourced:
//   set -a; source .env; set +a
//   swift test --filter ExecutorsLiveTests

enum LiveEnv {
    /// `nil` for both an unset variable and an empty one, so an accidentally-blank
    /// `.env` line reads as "not configured" rather than as a live probe with an
    /// empty bearer token.
    static func key(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }
}

@Generable
struct SentinelArguments: Sendable {
    @Guide(description: "Not used; call with no meaningful input")
    var note: String?
}

actor CallRecorder {
    private(set) var wasCalled = false
    func markCalled() { wasCalled = true }
}

/// One deterministic tool every provider probe calls, proving the full two-request
/// cycle — including provider-owned state replayed on the second request (DeepSeek's
/// mandatory `reasoning_content` echo, Anthropic's signed thinking blocks, Google's
/// thought signatures) — rather than only the first request succeeding.
struct SentinelTool: Tool, Sendable {
    let name = "sentinel_tool"
    let description = """
    A test probe tool. Call it with no meaningful arguments, then reply with only \
    the exact string it returns, verbatim.
    """
    let sentinelValue: String
    let recorder: CallRecorder

    func call(arguments _: SentinelArguments) async throws -> String {
        await recorder.markCalled()
        return sentinelValue
    }
}

enum LiveProviderProbe {
    static let sentinelValue = "WORKKIT-LIVE-SENTINEL-93f1"

    struct Result {
        let toolWasCalled: Bool
        let finalResponse: String
    }

    static func run(model: some LanguageModel) async throws -> Result {
        let recorder = CallRecorder()
        let tool = SentinelTool(sentinelValue: sentinelValue, recorder: recorder)
        let session = LanguageModelSession(model: model, tools: [tool])
        let response = try await session.respond(
            to: "Call the sentinel_tool tool now, then reply with only the exact string it returned."
        )
        return Result(toolWasCalled: await recorder.wasCalled, finalResponse: response.content)
    }

    /// The shared harness assertion: the tool was actually invoked, and the final
    /// response is non-empty and echoes the sentinel — proving both the tool-call leg
    /// and the follow-up completion round-tripped through the provider intact.
    static func assertRoundtrip(model: some LanguageModel) async throws {
        let result = try await run(model: model)
        #expect(result.toolWasCalled, "provider never called the sentinel tool")
        #expect(!result.finalResponse.isEmpty, "provider returned an empty final response")
        #expect(
            result.finalResponse.contains(sentinelValue),
            "final response did not echo the sentinel value verbatim: \(result.finalResponse)"
        )
    }
}
