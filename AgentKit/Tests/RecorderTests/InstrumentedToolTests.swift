import Foundation
import FoundationModels
import Testing
@testable import Recorder

// REQ: agent-loop-implementation.md §6 — InstrumentedTool registers/starts/commits
// every call durably, in that order, regardless of whether the base tool succeeds.

@Generable
private struct EchoArguments: Sendable {
    @Guide(description: "Text to echo")
    var text: String
}

private struct EchoTool: Tool, Sendable {
    let name = "echo"
    let description = "Echoes its input."
    func call(arguments: EchoArguments) async throws -> String { arguments.text }
}

private enum ToolFailure: Error, Sendable { case boom }

private struct FailingTool: Tool, Sendable {
    let name = "failing"
    let description = "Always throws."
    func call(arguments: EchoArguments) async throws -> String { throw ToolFailure.boom }
}

@Test("A successful call journals registered → started → completed(true) and returns output")
func instrumentedToolJournalsSuccess() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try FileRunJournal(directory: directory)
    let runID = RunID()

    let wrapped = InstrumentedTool(EchoTool(), runID: runID, journal: journal)
    let output = try await wrapped.call(arguments: EchoArguments(text: "hi"))
    #expect(output == "hi")

    let events = try await journal.events(for: runID)
    #expect(events.count == 3)
    guard case let .toolRegistered(_, id1, name, effect) = events[0] else {
        Issue.record("Expected toolRegistered first, got \(events[0])")
        return
    }
    #expect(name == "echo")
    #expect(effect == .consequential)
    guard case let .toolStarted(_, id2) = events[1] else {
        Issue.record("Expected toolStarted second, got \(events[1])")
        return
    }
    #expect(id1 == id2)
    guard case let .toolCompleted(_, id3, succeeded) = events[2] else {
        Issue.record("Expected toolCompleted third, got \(events[2])")
        return
    }
    #expect(id1 == id3)
    #expect(succeeded)
}

@Test("A thrown call still journals completed(false) and rethrows the original error")
func instrumentedToolJournalsFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try FileRunJournal(directory: directory)
    let runID = RunID()

    let wrapped = InstrumentedTool(FailingTool(), runID: runID, journal: journal)
    await #expect(throws: ToolFailure.boom) {
        _ = try await wrapped.call(arguments: EchoArguments(text: "hi"))
    }

    let events = try await journal.events(for: runID)
    guard case let .toolCompleted(_, _, succeeded) = events.last else {
        Issue.record("Expected a toolCompleted event")
        return
    }
    #expect(!succeeded)
}
