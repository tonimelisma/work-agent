import Foundation
import FoundationModels

// REQ: FR-080 — ask_user: suspend the turn to ask the user 1-4 questions, resume on
// answer (tool-architecture.md §3). The presenter protocol is the app-injected seam
// (this ToolKit product has no dependency on Recorder or the app's UI).
//
// Scope note (increment-4 DOR item): this suspends the in-memory call — it does not
// yet persist the suspension durably across an app restart. Full crash-safe
// interrupts are runtime-api.md's "Interrupts, approvals, checkpoints" row, which
// belongs to a later increment once real use shows what it needs to survive.
public enum InteractionToolError: LocalizedError, Equatable, Sendable {
    case invalidQuestionCount(Int)
    case invalidOptionCount(question: String, count: Int)
    case invalidPlan(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidQuestionCount(count):
            "ask_user takes 1-4 questions; got \(count)."
        case let .invalidOptionCount(question, count):
            "\"\(question)\" needs 2-4 options; got \(count)."
        case let .invalidPlan(message):
            message
        }
    }
}

@Generable
public struct AskUserQuestion: Sendable {
    @Guide(description: "The question text")
    public var question: String
    @Guide(description: "2-4 answer options; the user may also answer with free text")
    public var options: [String]

    public init(question: String, options: [String]) {
        self.question = question
        self.options = options
    }
}

@Generable
public struct AskUserArguments: Sendable {
    @Guide(description: "1-4 questions to ask the user")
    public var questions: [AskUserQuestion]

    public init(questions: [AskUserQuestion]) {
        self.questions = questions
    }
}

/// The app-injected seam: render a question card and return the user's answers,
/// one per question, in order.
public protocol AskUserPresenter: Sendable {
    func ask(_ questions: [AskUserQuestion]) async throws -> [String]
}

public struct AskUserTool: Tool, Sendable {
    public let name = "ask_user"
    public let description = """
    Ask the user 1-4 questions, each with 2-4 options (the user can also answer \
    with free text). Suspends this turn until the user answers.
    """

    private let presenter: any AskUserPresenter

    public init(presenter: any AskUserPresenter) {
        self.presenter = presenter
    }

    public func call(arguments: AskUserArguments) async throws -> String {
        guard (1 ... 4).contains(arguments.questions.count) else {
            throw InteractionToolError.invalidQuestionCount(arguments.questions.count)
        }
        for question in arguments.questions {
            guard (2 ... 4).contains(question.options.count) else {
                throw InteractionToolError.invalidOptionCount(
                    question: question.question, count: question.options.count
                )
            }
        }
        let answers = try await presenter.ask(arguments.questions)
        return zip(arguments.questions, answers)
            .map { "\($0.question) → \($1)" }
            .joined(separator: "\n")
    }
}
