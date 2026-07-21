import Foundation
import Testing
@testable import ToolKitInteraction

// REQ: FR-081 — update_plan enforces exactly one in_progress step.

private actor FakeRecorder: PlanRecorder {
    private(set) var recorded: [PlanStep]?
    func record(_ steps: [PlanStep]) async { recorded = steps }
}

@Test("A valid plan with one in_progress step is recorded")
func recordsValidPlan() async throws {
    let recorder = FakeRecorder()
    let tool = UpdatePlanTool(recorder: recorder)
    let result = try await tool.call(arguments: .init(steps: [
        .init(step: "Read the file", status: "completed"),
        .init(step: "Edit the file", status: "in_progress"),
        .init(step: "Verify", status: "pending"),
    ]))
    #expect(result.contains("3 step"))
    #expect(await recorder.recorded?.count == 3)
}

@Test("Two in_progress steps is rejected")
func rejectsMultipleInProgress() async throws {
    let recorder = FakeRecorder()
    let tool = UpdatePlanTool(recorder: recorder)
    await #expect(throws: InteractionToolError.invalidPlan("Exactly one step can be in_progress; found 2.")) {
        _ = try await tool.call(arguments: .init(steps: [
            .init(step: "A", status: "in_progress"),
            .init(step: "B", status: "in_progress"),
        ]))
    }
}
