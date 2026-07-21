import Foundation
import FoundationModels
@testable import Recorder
import Testing
import ToolKitFiles

// REQ: NFR-010 — accepts any `LanguageModel`, on-device inference included; proven
// live here rather than only by protocol conformance. Gated on device availability
// rather than an env var: a device with no eligible hardware or disabled Apple
// Intelligence is not a failure, and the skip reason names exactly which of those it is.

@Suite("Apple on-device model: package path")
struct AppleOnDeviceLiveTests {
    private static func availabilityComment() -> Comment {
        switch SystemLanguageModel.default.availability {
        case .available:
            "SystemLanguageModel.default is available on this Mac"
        case let .unavailable(reason):
            "SystemLanguageModel.default is unavailable: \(reason)"
        }
    }

    @Test(
        "read_file through SystemLanguageModel.default, instrumented like any other LanguageModel",
        .enabled(if: SystemLanguageModel.default.availability == .available, AppleOnDeviceLiveTests.availabilityComment())
    )
    func appleOnDeviceRoundtrip() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let marker = "WORKKIT-APPLE-ONDEVICE-FIXTURE-\(Int.random(in: 100_000 ... 999_999))"
        try marker.write(
            to: tempDirectory.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8
        )

        let journal = try FileRunJournal(directory: tempDirectory.appendingPathComponent("journal"))
        let runID = RunID()
        // Instrumented, not the bare tool — proving the package's durable tool-tracing
        // treats Apple's own model like any other `LanguageModel`, not a special case.
        let tool = InstrumentedTool(
            ReadFileTool(root: tempDirectory, ledger: FileReadLedger()), runID: runID, journal: journal
        )

        let session = LanguageModelSession(model: SystemLanguageModel.default, tools: [tool])
        let response = try await session.respond(
            to: "Read the file fixture.txt and report its exact contents, verbatim."
        )

        #expect(
            response.content.contains(marker),
            "on-device model did not echo the file's contents: \(response.content)"
        )
        let events = try await journal.events(for: runID)
        #expect(events.contains { if case .toolRegistered = $0 { true } else { false } })
        #expect(events.contains { if case .toolCompleted(_, _, succeeded: true) = $0 { true } else { false } })
    }
}
