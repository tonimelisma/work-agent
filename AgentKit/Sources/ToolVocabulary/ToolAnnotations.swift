import Foundation

// REQ: agent-loop-implementation.md §6 — effect/idempotency/budget metadata is
// runtime policy data, not a second tool protocol. This is the only shared
// language between RuntimeCore and ToolKit; neither imports the other.

/// What kind of side effect a tool call can have.
public enum ToolEffect: String, Sendable, Equatable, Codable {
    /// Never changes state observable outside the call. Safe to run without approval.
    case readOnly
    /// Changes state, but calling it again with the same arguments is a no-op.
    case idempotent
    /// Changes state, and calling it again can compound the effect.
    case consequential
}

/// How a tool's output is bounded before it reaches the model.
public struct ToolOutputBudget: Sendable, Equatable, Codable {
    /// Maximum characters of output sent to the model; the full output is still journaled.
    public var maximumModelCharacters: Int

    public init(maximumModelCharacters: Int = 4_096) {
        self.maximumModelCharacters = maximumModelCharacters
    }

    public static let `default` = ToolOutputBudget()
}

/// Runtime policy metadata for one tool, supplied by precedence (run-policy table →
/// `.annotations(...)` modifier → optional refinement conformance → MCP hints →
/// conservative default). Increment 4 only needs the conservative default and the
/// output budget; the full precedence chain lands with the increment-5 tool host.
public struct ToolAnnotations: Sendable, Equatable, Codable {
    public var effect: ToolEffect
    public var requiresApproval: Bool
    public var outputBudget: ToolOutputBudget

    public init(
        effect: ToolEffect = .consequential,
        requiresApproval: Bool = true,
        outputBudget: ToolOutputBudget = .default
    ) {
        self.effect = effect
        self.requiresApproval = requiresApproval
        self.outputBudget = outputBudget
    }

    /// Unannotated tools default to the safest assumption: consequential, approval-gated.
    public static let conservativeDefault = ToolAnnotations()
}
