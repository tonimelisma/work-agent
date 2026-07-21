import Foundation
import FoundationModels
import ToolVocabulary

// REQ: agent-loop-implementation.md §6, runtime-api.md §3 — the runtime hands the
// session `InstrumentedTool<Base>` wrappers so every plain `FoundationModels.Tool`
// gets tracing-before-budget and durable invocation identity just by running
// through the runtime, with no second tool protocol to conform to.
struct InstrumentedTool<Base: Tool>: Tool where Base.Arguments: Generable {
    typealias Arguments = Base.Arguments
    typealias Output = Base.Output

    var name: String { base.name }
    var description: String { base.description }

    private let base: Base
    private let annotations: ToolAnnotations
    private let runID: RunID
    private let journal: any RunJournal

    init(_ base: Base, annotations: ToolAnnotations = .conservativeDefault, runID: RunID, journal: any RunJournal) {
        self.base = base
        self.annotations = annotations
        self.runID = runID
        self.journal = journal
    }

    func call(arguments: Base.Arguments) async throws -> Base.Output {
        let invocationID = ToolInvocationID()
        try? await journal.append(
            .toolRegistered(runID, invocationID, name: name, effect: annotations.effect),
            for: runID
        )
        try? await journal.append(.toolStarted(runID, invocationID), for: runID)
        do {
            let output = try await base.call(arguments: arguments)
            try? await journal.append(.toolCompleted(runID, invocationID, succeeded: true), for: runID)
            return output
        } catch {
            try? await journal.append(.toolCompleted(runID, invocationID, succeeded: false), for: runID)
            throw error
        }
    }
}
