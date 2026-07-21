import Foundation

// REQ: FR-072, FR-073 — the status a durable run can be in across an app restart.
public enum RunStatus: Codable, Sendable, Equatable {
    case running
    case pausedAwaitingResume(reason: RunPauseReason)
    case completed
    case failed(reason: String)
}

/// The durable position a run can be recovered from: the last committed transcript
/// archive, which executor produced it, and what state the run is in.
public struct RunCheckpoint: Codable, Sendable {
    public var runID: RunID
    public var status: RunStatus
    public var archive: TranscriptArchive
    public var executorID: String
    public var updatedAt: Date

    public init(
        runID: RunID,
        status: RunStatus,
        archive: TranscriptArchive,
        executorID: String,
        updatedAt: Date = Date()
    ) {
        self.runID = runID
        self.status = status
        self.archive = archive
        self.executorID = executorID
        self.updatedAt = updatedAt
    }
}
