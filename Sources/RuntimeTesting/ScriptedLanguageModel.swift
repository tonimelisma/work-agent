import Foundation
import FoundationModels

// REQ: deterministic scripted executors are first-class public API, not
// test-only internals — generalizes the ad hoc SemanticsModel/SemanticsExecutor
// pattern proven in the pre-pivot Foundation Models POC (see `git log`) into a
// reusable double any consumer of this package can script against.
//
// `LanguageModelExecutor.init(configuration:)` is called by Apple's session
// machinery from just a `Hashable & Sendable` configuration value — it cannot
// carry a closure directly. The behavior closure is looked up by id from this
// lock-protected registry at `respond(to:)` time instead.
public struct ScriptedLanguageModel: LanguageModel {
    public typealias Executor = ScriptedExecutor

    public let capabilities: LanguageModelCapabilities
    public let executorConfiguration: ScriptedExecutor.Configuration

    public init(
        capabilities: LanguageModelCapabilities = LanguageModelCapabilities([.reasoning, .toolCalling]),
        respond: @escaping ScriptedExecutor.Respond
    ) {
        self.capabilities = capabilities
        let id = UUID()
        ScriptedExecutorRegistry.shared.register(id: id, respond: respond)
        executorConfiguration = .init(id: id)
    }
}

public struct ScriptedExecutor: LanguageModelExecutor {
    public typealias Respond = @Sendable (
        LanguageModelExecutorGenerationRequest,
        LanguageModelExecutorGenerationChannel
    ) async throws -> Void

    public struct Configuration: Hashable, Sendable {
        let id: UUID
    }

    public typealias Model = ScriptedLanguageModel
    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let respond = try ScriptedExecutorRegistry.shared.respond(for: configuration.id)
        try await respond(request, channel)
    }
}

enum ScriptedExecutorError: Error, Sendable {
    case unregisteredScript
}

final class ScriptedExecutorRegistry: @unchecked Sendable {
    static let shared = ScriptedExecutorRegistry()
    private let lock = NSLock()
    private var scripts: [UUID: ScriptedExecutor.Respond] = [:]

    func register(id: UUID, respond: @escaping ScriptedExecutor.Respond) {
        lock.lock()
        defer { lock.unlock() }
        scripts[id] = respond
    }

    func respond(for id: UUID) throws -> ScriptedExecutor.Respond {
        lock.lock()
        defer { lock.unlock() }
        guard let respond = scripts[id] else { throw ScriptedExecutorError.unregisteredScript }
        return respond
    }
}
