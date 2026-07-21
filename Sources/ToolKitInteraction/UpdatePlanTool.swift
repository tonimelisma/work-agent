import Foundation
import FoundationModels

// REQ: FR-081 — update_plan: an ordered list of steps with exactly one in progress
// (Codex's shape — tool-architecture.md §3), the data source for a friendly
// "watch a task run" display (FR-065).
@Generable
public struct PlanStep: Sendable {
    @Guide(description: "One step of the plan, in the user's terms")
    public var step: String
    @Guide(description: "One of: pending, in_progress, completed")
    public var status: String

    public init(step: String, status: String) {
        self.step = step
        self.status = status
    }
}

@Generable
public struct UpdatePlanArguments: Sendable {
    @Guide(description: "The ordered list of steps; exactly one may be in_progress")
    public var steps: [PlanStep]

    public init(steps: [PlanStep]) {
        self.steps = steps
    }
}

/// The app-injected seam: record the plan for display.
public protocol PlanRecorder: Sendable {
    func record(_ steps: [PlanStep]) async
}

public struct UpdatePlanTool: Tool, Sendable {
    public let name = "update_plan"
    public let description = "Record the current plan as an ordered list of steps, with exactly one step in_progress at a time."

    private let recorder: any PlanRecorder

    public init(recorder: any PlanRecorder) {
        self.recorder = recorder
    }

    public func call(arguments: UpdatePlanArguments) async throws -> String {
        let inProgressCount = arguments.steps.filter { $0.status == "in_progress" }.count
        guard inProgressCount <= 1 else {
            throw InteractionToolError.invalidPlan(
                "Exactly one step can be in_progress; found \(inProgressCount)."
            )
        }
        await recorder.record(arguments.steps)
        return "Plan updated: \(arguments.steps.count) step(s)."
    }
}
