import Foundation

// REQ: agent-loop-implementation.md §5 — TaskCoordinator is an actor above
// LanguageModelSession, not a replacement session. It owns durable identity,
// checkpointing, and FR-006 automatic failover; it does not know about
// LanguageModel/Tool types — those are erased into the two async closures the
// caller supplies (built with `runSessionAttempt`), so the coordinator itself has
// no FoundationModels import and can be tested with plain scripted closures.

/// One provider attempt, erased to a plain async function: given the archive to
/// resume from (nil for a fresh run), produce the resulting archive or throw.
public typealias RunAttemptExecutor = @Sendable (TranscriptArchive?) async throws -> RunAttemptResult

public struct RunHandle: Sendable {
    public let id: RunID
    public let events: AsyncThrowingStream<RunEvent, Error>
    private let task: Task<Void, Never>

    init(id: RunID, events: AsyncThrowingStream<RunEvent, Error>, task: Task<Void, Never>) {
        self.id = id
        self.events = events
        self.task = task
    }

    public func cancel() {
        task.cancel()
    }
}

public actor TaskCoordinator {
    private let journal: any RunJournal
    private let checkpoints: any CheckpointStore

    public init(journal: any RunJournal, checkpoints: any CheckpointStore) {
        self.journal = journal
        self.checkpoints = checkpoints
    }

    /// Starts a new durable run against `primary`, falling back automatically to
    /// `fallback` (FR-006) if the primary attempt throws. `resumingFrom` carries
    /// prior turns of an ongoing conversation (not a paused run — that's
    /// `resume(_:)`) forward, so a fallback triggered mid-conversation still
    /// replays from real history instead of an empty transcript.
    public func start(
        resumingFrom archive: TranscriptArchive? = nil,
        primaryID: String,
        primary: @escaping RunAttemptExecutor,
        fallbackID: String? = nil,
        fallback: RunAttemptExecutor? = nil
    ) -> RunHandle {
        run(runID: RunID(), resumeFrom: archive,
            primaryID: primaryID, primary: primary,
            fallbackID: fallbackID, fallback: fallback)
    }

    /// Resumes a paused/interrupted run from its last checkpoint (FR-072, FR-073).
    public func resume(
        _ checkpoint: RunCheckpoint,
        primaryID: String,
        primary: @escaping RunAttemptExecutor,
        fallbackID: String? = nil,
        fallback: RunAttemptExecutor? = nil
    ) -> RunHandle {
        run(runID: checkpoint.runID, resumeFrom: checkpoint.archive,
            primaryID: primaryID, primary: primary,
            fallbackID: fallbackID, fallback: fallback)
    }

    private func run(
        runID: RunID,
        resumeFrom: TranscriptArchive?,
        primaryID: String,
        primary: @escaping RunAttemptExecutor,
        fallbackID: String?,
        fallback: RunAttemptExecutor?
    ) -> RunHandle {
        let (stream, continuation) = AsyncThrowingStream<RunEvent, Error>.makeStream(of: RunEvent.self)
        let journal = journal
        let checkpoints = checkpoints
        let task = Task {
            await Self.execute(
                runID: runID, resumeFrom: resumeFrom,
                primaryID: primaryID, primary: primary,
                fallbackID: fallbackID, fallback: fallback,
                journal: journal, checkpoints: checkpoints,
                continuation: continuation
            )
        }
        return RunHandle(id: runID, events: stream, task: task)
    }

    private static func execute(
        runID: RunID,
        resumeFrom: TranscriptArchive?,
        primaryID: String,
        primary: @escaping RunAttemptExecutor,
        fallbackID: String?,
        fallback: RunAttemptExecutor?,
        journal: any RunJournal,
        checkpoints: any CheckpointStore,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async {
        let primaryOutcome = await attempt(
            runID: runID, executorID: primaryID, executor: primary, resumeFrom: resumeFrom,
            journal: journal, checkpoints: checkpoints, continuation: continuation
        )
        guard case let .failed(primaryError) = primaryOutcome else { return }

        guard let fallback, let fallbackID else {
            continuation.finish(throwing: primaryError)
            return
        }

        try? await journal.append(.runFailedOver(runID, from: primaryID, to: fallbackID), for: runID)
        continuation.yield(.runFailedOver(runID, from: primaryID, to: fallbackID))

        let checkpoint = try? await checkpoints.load(runID)
        let replaySource = resumeFrom ?? checkpoint?.archive
        let replay = try? replaySource?.replay(to: fallbackID)

        let fallbackOutcome = await attempt(
            runID: runID, executorID: fallbackID, executor: fallback, resumeFrom: replay,
            journal: journal, checkpoints: checkpoints, continuation: continuation
        )
        if case let .failed(fallbackError) = fallbackOutcome {
            try? await journal.append(.runFailed(runID, reason: String(describing: fallbackError)), for: runID)
            continuation.yield(.runFailed(runID, reason: String(describing: fallbackError)))
            continuation.finish(throwing: fallbackError)
        }
    }

    private enum AttemptOutcome {
        case finished
        case failed(Error)
    }

    /// Runs one attempt to completion, yielding its events. `.failed` means the
    /// caller should try a fallback (or give up if there isn't one); every other
    /// case has already finished the continuation.
    private static func attempt(
        runID: RunID,
        executorID: String,
        executor: RunAttemptExecutor,
        resumeFrom: TranscriptArchive?,
        journal: any RunJournal,
        checkpoints: any CheckpointStore,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async -> AttemptOutcome {
        let attemptID = AttemptID()
        try? await journal.append(.attemptStarted(runID, attemptID, executor: executorID), for: runID)
        continuation.yield(.attemptStarted(runID, attemptID, executor: executorID))

        do {
            let result = try await executor(resumeFrom)

            try? await journal.append(
                .attemptCommitted(runID, attemptID, inputTokens: 0, outputTokens: 0), for: runID
            )
            continuation.yield(.attemptCommitted(runID, attemptID, inputTokens: 0, outputTokens: 0))

            let checkpoint = RunCheckpoint(
                runID: runID, status: .completed, archive: result.archive, executorID: executorID
            )
            try? await checkpoints.save(checkpoint)
            try? await journal.append(.checkpointCommitted(runID, attemptID), for: runID)
            continuation.yield(.checkpointCommitted(runID, attemptID))

            try? await journal.append(.runCompleted(runID), for: runID)
            continuation.yield(.runCompleted(runID))
            continuation.finish()
            return .finished
        } catch is CancellationError {
            let checkpoint = RunCheckpoint(
                runID: runID,
                status: .pausedAwaitingResume(reason: .appQuit),
                archive: resumeFrom ?? TranscriptArchive(transcript: .init(entries: [])),
                executorID: executorID
            )
            try? await checkpoints.save(checkpoint)
            try? await journal.append(.runPaused(runID, reason: .appQuit), for: runID)
            continuation.yield(.runPaused(runID, reason: .appQuit))
            continuation.finish()
            return .finished
        } catch {
            return .failed(error)
        }
    }
}
