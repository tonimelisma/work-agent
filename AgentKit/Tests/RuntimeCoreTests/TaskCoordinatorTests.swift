import Foundation
import FoundationModels
import Testing
@testable import RuntimeCore

// REQ: FR-006, FR-073, agent-loop-implementation.md §5 — the coordinator's actual
// job: durable journaling/checkpointing and automatic cross-provider failover,
// exercised here against plain scripted RunAttemptExecutor closures (no network,
// no FoundationModels executor needed — that seam is exactly the point).

private func response(_ text: String) -> TranscriptArchive {
    TranscriptArchive(transcript: Transcript(entries: [
        .response(Transcript.Response(id: "r", segments: [.text(.init(content: text))])),
    ]))
}

private enum AttemptFailure: Error, Equatable { case providerDown }

@Test("A successful primary attempt completes and checkpoints without touching the fallback")
func coordinatorCompletesOnPrimary() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try FileRunJournal(directory: directory.appendingPathComponent("journal"))
    let checkpoints = try FileCheckpointStore(directory: directory.appendingPathComponent("checkpoints"))
    let coordinator = TaskCoordinator(journal: journal, checkpoints: checkpoints)

    let handle = await coordinator.start(
        primaryID: "deepseek",
        primary: { _ in RunAttemptResult(archive: response("hello")) }
    )

    var events: [RunEvent] = []
    for try await event in handle.events { events.append(event) }

    #expect(events.contains { if case .runCompleted = $0 { true } else { false } })
    let checkpoint = try #require(await checkpoints.load(handle.id))
    #expect(checkpoint.status == .completed)
    #expect(checkpoint.executorID == "deepseek")
}

@Test("A failed primary attempt fails over to the fallback automatically (FR-006)")
func coordinatorFailsOverAutomatically() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try FileRunJournal(directory: directory.appendingPathComponent("journal"))
    let checkpoints = try FileCheckpointStore(directory: directory.appendingPathComponent("checkpoints"))
    let coordinator = TaskCoordinator(journal: journal, checkpoints: checkpoints)

    let handle = await coordinator.start(
        primaryID: "deepseek",
        primary: { _ in throw AttemptFailure.providerDown },
        fallbackID: "anthropic",
        fallback: { _ in RunAttemptResult(archive: response("recovered")) }
    )

    var events: [RunEvent] = []
    for try await event in handle.events { events.append(event) }

    #expect(events.contains(.runFailedOver(handle.id, from: "deepseek", to: "anthropic")))
    #expect(events.contains { if case .runCompleted = $0 { true } else { false } })
    let checkpoint = try #require(await checkpoints.load(handle.id))
    #expect(checkpoint.executorID == "anthropic")
}

@Test("When both the primary and fallback fail, the run surfaces the fallback's error")
func coordinatorSurfacesFallbackFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try FileRunJournal(directory: directory.appendingPathComponent("journal"))
    let checkpoints = try FileCheckpointStore(directory: directory.appendingPathComponent("checkpoints"))
    let coordinator = TaskCoordinator(journal: journal, checkpoints: checkpoints)

    let handle = await coordinator.start(
        primaryID: "deepseek",
        primary: { _ in throw AttemptFailure.providerDown },
        fallbackID: "anthropic",
        fallback: { _ in throw AttemptFailure.providerDown }
    )

    await #expect(throws: AttemptFailure.providerDown) {
        for try await _ in handle.events {}
    }
    #expect(try await checkpoints.load(handle.id) == nil)
}

@Test("A fresh run's fallback still replays prior conversation turns, stripped of foreign metadata")
func coordinatorStartWithPriorTurnsFailsOverWithReplay() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try FileRunJournal(directory: directory.appendingPathComponent("journal"))
    let checkpoints = try FileCheckpointStore(directory: directory.appendingPathComponent("checkpoints"))
    let coordinator = TaskCoordinator(journal: journal, checkpoints: checkpoints)

    let priorTurns = TranscriptArchive(transcript: Transcript(entries: [
        .reasoning(Transcript.Reasoning(
            id: "reasoning-1",
            metadata: [
                "deepseek.private": "x",
                TranscriptArchive.signatureProviderMetadataKey: "deepseek",
            ],
            segments: [.text(.init(content: "thinking"))],
            signature: Data("sig".utf8)
        )),
    ]))

    let handle = await coordinator.start(
        resumingFrom: priorTurns,
        primaryID: "deepseek",
        primary: { _ in throw AttemptFailure.providerDown },
        fallbackID: "anthropic",
        fallback: { resumed in
            let entries = resumed?.transcript.map { $0 } ?? []
            guard case let .reasoning(reasoning) = entries.first else {
                Issue.record("Expected the prior turn's reasoning entry to be replayed to the fallback")
                return RunAttemptResult(archive: response("unexpected"))
            }
            #expect(!reasoning.metadata.keys.contains("deepseek.private"))
            #expect(reasoning.signature == nil)
            return RunAttemptResult(archive: response("recovered"))
        }
    )

    var sawRunCompleted = false
    for try await event in handle.events {
        if case .runCompleted = event { sawRunCompleted = true }
    }
    #expect(sawRunCompleted)
}

@Test("Resuming a checkpoint replays it to the executor stripped of foreign metadata")
func coordinatorResumeReplaysToNewExecutor() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try FileRunJournal(directory: directory.appendingPathComponent("journal"))
    let checkpoints = try FileCheckpointStore(directory: directory.appendingPathComponent("checkpoints"))
    let coordinator = TaskCoordinator(journal: journal, checkpoints: checkpoints)

    let taggedArchive = TranscriptArchive(transcript: Transcript(entries: [
        .reasoning(Transcript.Reasoning(
            id: "reasoning-1",
            metadata: [
                "deepseek.private": "x",
                TranscriptArchive.signatureProviderMetadataKey: "deepseek",
            ],
            segments: [.text(.init(content: "thinking"))],
            signature: Data("sig".utf8)
        )),
    ]))
    let checkpoint = RunCheckpoint(
        runID: RunID(),
        status: .pausedAwaitingResume(reason: .appQuit),
        archive: taggedArchive,
        executorID: "deepseek"
    )
    try await checkpoints.save(checkpoint)

    let handle = await coordinator.resume(
        checkpoint,
        primaryID: "deepseek",
        primary: { _ in throw AttemptFailure.providerDown },
        fallbackID: "anthropic",
        fallback: { resumed in
            let entries = resumed?.transcript.map { $0 } ?? []
            guard case let .reasoning(reasoning) = entries.first else {
                Issue.record("Expected a reasoning entry to resume from")
                return RunAttemptResult(archive: response("unexpected"))
            }
            #expect(!reasoning.metadata.keys.contains("deepseek.private"))
            #expect(reasoning.signature == nil)
            return RunAttemptResult(archive: response("resumed"))
        }
    )

    var sawRunCompleted = false
    for try await event in handle.events {
        if case .runCompleted = event { sawRunCompleted = true }
    }
    #expect(sawRunCompleted)
}
