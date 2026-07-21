import Foundation
import ToolVocabulary

// REQ: the append-only run journal is execution
// truth. Each case here is a fact the journal records; nothing here is inferred
// from UI state.
public enum RunEvent: Codable, Sendable, Equatable {
    case attemptStarted(RunID, AttemptID, executor: String)
    case attemptCommitted(RunID, AttemptID, inputTokens: Int, outputTokens: Int)
    case toolRegistered(RunID, ToolInvocationID, name: String, effect: ToolEffect)
    case toolStarted(RunID, ToolInvocationID)
    case toolCompleted(RunID, ToolInvocationID, succeeded: Bool)
    case checkpointCommitted(RunID, AttemptID)
    case runFailedOver(RunID, from: String, to: String)
    case runPaused(RunID, reason: RunPauseReason)
    case runCompleted(RunID)
    case runFailed(RunID, reason: String)
}

// Why a run paused rather than resuming automatically.
public enum RunPauseReason: String, Codable, Sendable, Equatable {
    case appQuit
    case policyLimitReached
}
