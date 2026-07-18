import Foundation
import FoundationModels

public enum FixtureReadError: LocalizedError, Equatable, Sendable {
    case outsideRoot(path: String)

    public var errorDescription: String? {
        switch self {
        case let .outsideRoot(path):
            "Fixture path escapes the allowed root: \(path)"
        }
    }
}

public struct ReadFixtureTool: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func call(path: String) throws -> String {
        let url = root
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else {
            throw FixtureReadError.outsideRoot(path: path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

public struct FixtureToolTraceEvent: Codable, Equatable, Sendable {
    public var path: String
    public var rawOutput: String?
    public var modelOutput: String?
    public var error: String?
}

/// POC runner proving that host tracing and output policy remain outside Apple's Tool.
public actor FixtureToolRunner {
    private let implementation: ReadFixtureTool
    private let maximumModelCharacters: Int
    private var events: [FixtureToolTraceEvent] = []

    public init(root: URL, maximumModelCharacters: Int = 4_096) {
        implementation = ReadFixtureTool(root: root)
        self.maximumModelCharacters = maximumModelCharacters
    }

    public func run(path: String) throws -> String {
        do {
            let rawOutput = try implementation.call(path: path)
            let modelOutput: String
            if rawOutput.count > maximumModelCharacters {
                modelOutput = String(rawOutput.prefix(maximumModelCharacters))
                    + "\n[Output truncated; full value is retained in the tool trace.]"
            } else {
                modelOutput = rawOutput
            }
            events.append(
                FixtureToolTraceEvent(
                    path: path,
                    rawOutput: rawOutput,
                    modelOutput: modelOutput,
                    error: nil
                )
            )
            return modelOutput
        } catch {
            events.append(
                FixtureToolTraceEvent(
                    path: path,
                    rawOutput: nil,
                    modelOutput: nil,
                    error: String(reflecting: error)
                )
            )
            throw error
        }
    }

    public func trace() -> [FixtureToolTraceEvent] {
        events
    }
}

@available(macOS 27.0, *)
@Generable
public struct ReadFixtureArguments: Sendable {
    @Guide(description: "Path relative to the fixture root")
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

/// A real Foundation Models tool adapter around the host-owned implementation.
@available(macOS 27.0, *)
public struct FoundationModelsReadFixtureTool: Tool, Sendable {
    public let name = "read_fixture"
    public let description = "Read a UTF-8 text fixture from the allowed fixture root."
    private let runner: FixtureToolRunner

    public init(root: URL, maximumModelCharacters: Int = 4_096) {
        runner = FixtureToolRunner(
            root: root,
            maximumModelCharacters: maximumModelCharacters
        )
    }

    public func call(arguments: ReadFixtureArguments) async throws -> String {
        try await runner.run(path: arguments.path)
    }

    public func trace() async -> [FixtureToolTraceEvent] {
        await runner.trace()
    }
}
