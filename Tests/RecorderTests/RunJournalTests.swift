import Foundation
import Testing
@testable import Recorder
import ToolVocabulary

// REQ: the append-only run journal is execution
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

@Test("A torn tail (partial line, no trailing newline) returns everything decoded before it")
func fileRunJournalTolersTornTail() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let runID = RunID()
    let attemptID = AttemptID()
    let journal = try FileRunJournal(directory: directory)
    try await journal.append(.attemptStarted(runID, attemptID, executor: "deepseek"), for: runID)

    // Simulate a crash mid-append: garbage bytes with no trailing newline, appended
    // directly to the file underneath the journal (not through `append`, which always
    // completes a full line).
    let url = directory.appendingPathComponent("\(runID.rawValue.uuidString).jsonl")
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{\"incomplete".utf8))
    try handle.close()

    let events = try await journal.events(for: runID)
    #expect(events == [.attemptStarted(runID, attemptID, executor: "deepseek")])
}

@Test("Corruption before the last line still throws, with the right line number")
func fileRunJournalThrowsOnMidFileCorruption() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let runID = RunID()
    let attemptID = AttemptID()
    let journal = try FileRunJournal(directory: directory)
    try await journal.append(.attemptStarted(runID, attemptID, executor: "deepseek"), for: runID)

    let url = directory.appendingPathComponent("\(runID.rawValue.uuidString).jsonl")
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    // A corrupt line followed by a valid one: corruption is no longer the tail.
    try handle.write(contentsOf: Data("not json at all\n".utf8))
    let validLine = try JSONEncoder().encode(RunEvent.runCompleted(runID))
    try handle.write(contentsOf: validLine)
    try handle.write(contentsOf: Data("\n".utf8))
    try handle.close()

    await #expect(throws: RunJournalError.corruptEntry(runID: runID, line: 2)) {
        _ = try await journal.events(for: runID)
    }
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
