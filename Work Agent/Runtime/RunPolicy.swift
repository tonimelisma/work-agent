import Foundation

// REQ: agent-loop-implementation.md §5 — RunPolicy composes run limits. Product
// defaults belong in the app; this is the composable primitive. Increment 4 only
// needs the attempt ceiling (retry/failover budget) — richer limits (token/cost/
// time/tool-call) are added when a real run demonstrates the need.
struct RunPolicy: Sendable, Equatable {
    /// Total attempts across the primary and any fallback executor before the run
    /// gives up rather than retrying again.
    var maximumAttempts: Int

    init(maximumAttempts: Int = 3) {
        self.maximumAttempts = maximumAttempts
    }

    static let `default` = RunPolicy()

    func maximumAttempts(_ value: Int) -> RunPolicy {
        var copy = self
        copy.maximumAttempts = value
        return copy
    }
}
