import Foundation
import FoundationModels
import ToolVocabulary

// REQ: see ENGINEERING.md "Tool tracing" — a host wraps a plain
// `FoundationModels.Tool` in `InstrumentedTool<Base>` to get tracing-before-budget
// and durable invocation identity, with no second tool protocol to conform to.
public enum ToolInstrumentationError: LocalizedError, Sendable {
    case journalUnavailable(underlyingDescription: String)

    public var errorDescription: String? {
        switch self {
        case let .journalUnavailable(underlyingDescription):
            "Could not record this tool call before running it: \(underlyingDescription)"
        }
    }
}

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
        // Registration is the registered-before-execute guarantee itself: if the
        // journal can't record it, the base tool must never run unrecorded, so this
        // failure propagates rather than being swallowed with `try?`.
        do {
            try await journal.append(
                .toolRegistered(runID, invocationID, name: name, effect: annotations.effect),
                for: runID
            )
        } catch {
            throw ToolInstrumentationError.journalUnavailable(underlyingDescription: error.localizedDescription)
        }
        try? await journal.append(.toolStarted(runID, invocationID), for: runID)
        do {
            let output = try await base.call(arguments: arguments)
            // Best-effort, deliberately: a write failure here must not destroy an
            // already-successful result, and a registered-without-outcome entry already
            // reads as "unknown, ask" on the next resume — the guard working as intended.
            try? await journal.append(.toolCompleted(runID, invocationID, succeeded: true), for: runID)
            return output
        } catch {
            try? await journal.append(.toolCompleted(runID, invocationID, succeeded: false), for: runID)
            throw error
        }
    }
}
