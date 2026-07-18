import Foundation
import FoundationModels
import FoundationModelsPOC

@available(macOS 27.0, *)
private struct ScriptedLanguageModel: LanguageModel {
    typealias Executor = ScriptedExecutor

    let capabilities = LanguageModelCapabilities(
        capabilities: [.reasoning, .toolCalling, .guidedGeneration]
    )
    let executorConfiguration = ScriptedExecutor.Configuration()
}

@available(macOS 27.0, *)
private struct ScriptedExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {}

    typealias Model = ScriptedLanguageModel

    init(configuration: Configuration) throws {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let hasToolOutput = request.transcript.contains { entry in
            if case .toolOutput = entry { return true }
            return false
        }

        if hasToolOutput {
            let response: LanguageModelExecutorGenerationChannel.Response = .response(
                entryID: "response-2",
                action: .appendText("The tool completed successfully.", tokenCount: 5)
            )
            await channel.send(response)
            let usage: LanguageModelExecutorGenerationChannel.Response = .response(
                entryID: "response-2",
                action: .updateUsage(
                    input: .init(totalTokenCount: 31, cachedTokenCount: 7),
                    output: .init(totalTokenCount: 5, reasoningTokenCount: 0)
                )
            )
            await channel.send(usage)
            return
        }

        let reasoning: LanguageModelExecutorGenerationChannel.Reasoning = .reasoning(
            entryID: "reasoning-1",
            action: .appendText("I should inspect the fixture.", tokenCount: 6)
        )
        await channel.send(reasoning)
        let signature: LanguageModelExecutorGenerationChannel.Reasoning = .reasoning(
            entryID: "reasoning-1",
            action: .updateSignature(Data("scripted-signature".utf8), tokenCount: 1)
        )
        await channel.send(signature)
        let metadata: LanguageModelExecutorGenerationChannel.Reasoning = .reasoning(
            entryID: "reasoning-1",
            action: .updateMetadata(["scripted.signature": "scripted-signature"])
        )
        await channel.send(metadata)

        let toolCall: LanguageModelExecutorGenerationChannel.ToolCalls = .toolCalls(
            entryID: "tool-calls-1",
            action: .toolCall(
                id: "call-1",
                name: "read_fixture",
                action: .appendArguments(#"{"path":"answer.txt"}"#, tokenCount: 5)
            )
        )
        await channel.send(toolCall)
    }
}

private struct ProbeResult: Codable {
    var status: String
    var response: String
    var requestCount: Int
    var toolCallCount: Int
    var toolOutputCount: Int
    var reasoningCount: Int
    var reasoningSignatureRoundTripped: Bool
    var transcriptArchiveRoundTripped: Bool
    var totalTokenCount: Int
}

@available(macOS 27.0, *)
private func run(fixtureRoot: URL) async throws -> ProbeResult {
    let tool = FoundationModelsReadFixtureTool(root: fixtureRoot)
    let session = LanguageModelSession(
        model: ScriptedLanguageModel(),
        tools: [tool],
        instructions: "Use the fixture tool before answering."
    )
    let response = try await session.respond(
        to: "Read answer.txt and confirm completion.",
        options: GenerationOptions(toolCallingMode: .required)
    )

    let transcript = session.transcript
    let archive = TranscriptArchive(transcript: transcript)
    let encodedArchive = try archive.encoded()
    let decoded = try TranscriptArchive.decode(encodedArchive)
    let reencodedArchive = try decoded.encoded()

    var toolCallCount = 0
    var toolOutputCount = 0
    var reasoningCount = 0
    var signatureRoundTripped = false
    var responseCount = 0
    for entry in transcript {
        switch entry {
        case let .toolCalls(calls):
            toolCallCount += calls.count
        case .toolOutput:
            toolOutputCount += 1
        case let .reasoning(reasoning):
            reasoningCount += 1
            signatureRoundTripped = reasoning.signature == Data("scripted-signature".utf8)
        case .response:
            responseCount += 1
        case .instructions, .prompt:
            break
        @unknown default:
            break
        }
    }

    return ProbeResult(
        status: "passed",
        response: response.content,
        requestCount: responseCount + toolCallCount,
        toolCallCount: toolCallCount,
        toolOutputCount: toolOutputCount,
        reasoningCount: reasoningCount,
        reasoningSignatureRoundTripped: signatureRoundTripped,
        transcriptArchiveRoundTripped: encodedArchive == reencodedArchive,
        totalTokenCount: session.usage.totalTokenCount
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--help" || arguments.count != 2 || arguments.first != "--fixture-root" {
    print("Usage: foundation-models-session-probe --fixture-root <directory>")
    exit(arguments.first == "--help" ? EXIT_SUCCESS : EXIT_FAILURE)
}

guard #available(macOS 27.0, *) else {
    print("Foundation Models provider execution requires macOS 27 or later.")
    exit(EXIT_FAILURE)
}

do {
    let result = try await run(fixtureRoot: URL(fileURLWithPath: arguments[1], isDirectory: true))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(result), as: UTF8.self))
} catch {
    let payload = ["status": "failed", "error": String(reflecting: error)]
    let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
    exit(EXIT_FAILURE)
}
