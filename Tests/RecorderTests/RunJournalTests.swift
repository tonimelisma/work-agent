import Foundation
import Testing
@testable import Recorder
import ToolVocabulary

// REQ: agent-loop-implementation.md §3 — the append-only run journal is execution
// truth; it must survive being read back from a fresh instance (crash/restart).

@Test("Appended events round-trip in order from a fresh journal instance")
func fileRunJournalRoundTrips() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let runID = RunID()
    let attemptID = AttemptID()
    do {
        let journal = try FileRunJournal(directory: directory)
        try await journal.append(.attemptStarted(runID, attemptID, executor: "deepseek"), for: runID)
        try await journal.append(
            .attemptCommitted(runID, attemptID, inputTokens: 10, outputTokens: 20), for: runID
        )
        try await journal.append(.runCompleted(runID), for: runID)
    }

    // A fresh instance (standing in for a relaunched process) reads the same events.
    let reopened = try FileRunJournal(directory: directory)
    let events = try await reopened.events(for: runID)
    #expect(events == [
        .attemptStarted(runID, attemptID, executor: "deepseek"),
        .attemptCommitted(runID, attemptID, inputTokens: 10, outputTokens: 20),
        .runCompleted(runID),
    ])
}

@Test("allRunIDs enumerates every run that has a journal file")
func fileRunJournalEnumeratesRuns() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let journal = try FileRunJournal(directory: directory)
    let first = RunID()
    let second = RunID()
    try await journal.append(.runCompleted(first), for: first)
    try await journal.append(.runCompleted(second), for: second)

    let ids = Set(try await journal.allRunIDs())
    #expect(ids == Set([first, second]))
}
