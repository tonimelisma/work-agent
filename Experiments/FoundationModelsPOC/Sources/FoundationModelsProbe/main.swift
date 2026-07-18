import Foundation
import FoundationModelsPOC

private enum ProviderCase: String, CaseIterable, Codable {
    case deepseek
    case google
    case anthropic

    var fixtureName: String {
        switch self {
        case .deepseek: "openai-tool-stream.sse"
        case .google: "google-reasoning-stream.sse"
        case .anthropic: "anthropic-tool-stream.sse"
        }
    }
}

private struct ProbeResult: Codable {
    var provider: ProviderCase
    var fixture: String
    var fixtureParsed: Bool
    var toolIdentityPreserved: Bool
    var argumentsReassembled: Bool
    var reasoningSignaturePreserved: Bool
    var usageObserved: Bool
    var stopObserved: Bool
    var executorRuntime: String
    var passed: Bool
}

private func run(_ provider: ProviderCase, fixtureRoot: URL) throws -> ProbeResult {
    let url = fixtureRoot.appendingPathComponent(provider.fixtureName)
    let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
    let events: [ExecutorEvent]
    switch provider {
    case .deepseek, .google:
        events = try OpenAICompatibleFixtureParser.events(from: lines)
    case .anthropic:
        events = try AnthropicFixtureParser.events(from: lines)
    }

    let calls = events.compactMap { event -> (String, String, String)? in
        guard case let .toolCall(_, id, name, fragment, _) = event else { return nil }
        return (id, name, fragment)
    }
    let expectedID = switch provider {
    case .deepseek: "call_1"
    case .google: "google_call_1"
    case .anthropic: "toolu_1"
    }
    let expectedSignature = provider != .deepseek

    let fixtureParsed = !events.isEmpty
    let toolIdentityPreserved = !calls.isEmpty && calls.allSatisfy {
        $0.0 == expectedID && $0.1 == "read_fixture"
    }
    let argumentsReassembled = calls.map(\.2).joined() == #"{"path":"answer.txt"}"#
    let reasoningSignaturePreserved = !expectedSignature || events.contains { event in
        guard case let .reasoning(_, signature, _) = event else { return false }
        return !(signature ?? "").isEmpty
    }
    let usageObserved = events.contains { event in
        if case .usage = event { return true }
        return false
    }
    let stopObserved = events.contains { event in
        if case .finish = event { return true }
        return false
    }

    return ProbeResult(
        provider: provider,
        fixture: provider.fixtureName,
        fixtureParsed: fixtureParsed,
        toolIdentityPreserved: toolIdentityPreserved,
        argumentsReassembled: argumentsReassembled,
        reasoningSignaturePreserved: reasoningSignaturePreserved,
        usageObserved: usageObserved,
        stopObserved: stopObserved,
        executorRuntime: "not exercised; run foundation-models-session-probe",
        passed: fixtureParsed
            && toolIdentityPreserved
            && argumentsReassembled
            && reasoningSignaturePreserved
            && usageObserved
            && stopObserved
    )
}

private func printHelp() {
    print("Usage: foundation-models-probe <deepseek|google|anthropic|all> [--fixtures <directory>]")
    print("Replays scrubbed structural fixtures without reading provider credentials.")
    print("Run foundation-models-session-probe separately to test Apple's executor/session runtime.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first, first != "--help" else {
    printHelp()
    exit(EXIT_SUCCESS)
}

let defaultFixtureRoot = URL(
    fileURLWithPath: "Experiments/FoundationModelsPOC/Tests/FoundationModelsPOCTests/Fixtures",
    isDirectory: true
)
let fixtureRoot: URL
if let fixtureFlag = arguments.firstIndex(of: "--fixtures"), arguments.indices.contains(fixtureFlag + 1) {
    fixtureRoot = URL(fileURLWithPath: arguments[fixtureFlag + 1], isDirectory: true)
} else {
    fixtureRoot = defaultFixtureRoot
}

private let providers: [ProviderCase]
if first == "all" {
    providers = ProviderCase.allCases
} else if let provider = ProviderCase(rawValue: first) {
    providers = [provider]
} else {
    printHelp()
    exit(EXIT_FAILURE)
}

do {
    let results = try providers.map { try run($0, fixtureRoot: fixtureRoot) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(results), as: UTF8.self))
    exit(results.allSatisfy(\.passed) ? EXIT_SUCCESS : EXIT_FAILURE)
} catch {
    let payload = ["status": "failed", "error": String(reflecting: error)]
    let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
    exit(EXIT_FAILURE)
}
