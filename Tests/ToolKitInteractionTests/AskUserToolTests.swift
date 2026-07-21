import Foundation
import Testing
@testable import ToolKitInteraction

// REQ: FR-080 — ask_user validates shape and defers to the host-injected presenter.

private struct FakePresenter: AskUserPresenter {
    let answers: [String]
    func ask(_ questions: [AskUserQuestion]) async throws -> [String] { answers }
}

@Test("A well-formed question set defers to the presenter and formats the answers")
func asksAndFormatsAnswers() async throws {
    let tool = AskUserTool(presenter: FakePresenter(answers: ["blue"]))
    let output = try await tool.call(arguments: .init(questions: [
        .init(question: "Favorite color?", options: ["red", "blue"]),
    ]))
    #expect(output == "Favorite color? → blue")
}

@Test("Zero questions is rejected")
func rejectsZeroQuestions() async throws {
    let tool = AskUserTool(presenter: FakePresenter(answers: []))
    await #expect(throws: InteractionToolError.invalidQuestionCount(0)) {
        _ = try await tool.call(arguments: .init(questions: []))
    }
}

@Test("Five questions is rejected (max 4)")
func rejectsTooManyQuestions() async throws {
    let questions = (1 ... 5).map { AskUserQuestion(question: "q\($0)", options: ["a", "b"]) }
    let tool = AskUserTool(presenter: FakePresenter(answers: Array(repeating: "a", count: 5)))
    await #expect(throws: InteractionToolError.invalidQuestionCount(5)) {
        _ = try await tool.call(arguments: .init(questions: questions))
    }
}

@Test("A question with only one option is rejected (min 2)")
func rejectsTooFewOptions() async throws {
    let tool = AskUserTool(presenter: FakePresenter(answers: ["x"]))
    await #expect(throws: InteractionToolError.invalidOptionCount(question: "q", count: 1)) {
        _ = try await tool.call(arguments: .init(questions: [.init(question: "q", options: ["only"])]))
    }
}
