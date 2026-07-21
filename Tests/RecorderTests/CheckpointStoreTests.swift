import Foundation
import FoundationModels
import Testing
@testable import Recorder

// A checkpoint written by one process instance is readable by another, which is
// what "survives a host restart" means mechanically.

@Test("A saved checkpoint reloads from a fresh store instance with status intact")
func fileCheckpointStoreRoundTrips() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let runID = RunID()
    let archive = TranscriptArchive(transcript: Transcript(entries: [
        .response(Transcript.Response(id: "r1", segments: [.text(.init(content: "hi"))])),
    ]))
    let checkpoint = RunCheckpoint(
        runID: runID,
        status: .pausedAwaitingResume(reason: .appQuit),
        archive: archive,
        executorID: "deepseek"
    )

    do {
        let store = try FileCheckpointStore(directory: directory)
        try await store.save(checkpoint)
    }

    let reopened = try FileCheckpointStore(directory: directory)
    let loaded = try #require(await reopened.load(runID))
    #expect(loaded.status == .pausedAwaitingResume(reason: .appQuit))
    #expect(loaded.executorID == "deepseek")
}

@Test("Deleting a checkpoint removes it from loadAll")
func fileCheckpointStoreDeletes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try FileCheckpointStore(directory: directory)
    let runID = RunID()
    let archive = TranscriptArchive(transcript: Transcript(entries: []))
    try await store.save(RunCheckpoint(runID: runID, status: .completed, archive: archive, executorID: "x"))
    #expect(try await store.loadAll().count == 1)

    try await store.delete(runID)
    #expect(try await store.loadAll().isEmpty)
}
