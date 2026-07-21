import Foundation

// REQ: docs/product/ROADMAP.md, cost display item — the Recorder's minimal public
// surface: a read/append façade over the run journal, so a host's cost display
// (and nothing else outside the package) can read what a run spent without
// depending on `FileRunJournal` directly.
public actor RecorderStore {
    private let journal: any RunJournal

    public init(journal: any RunJournal) {
        self.journal = journal
    }

    public func append(_ event: RunEvent, for run: RunID) async throws {
        try await journal.append(event, for: run)
    }

    public func events(forRun run: RunID) async throws -> [RunEvent] {
        try await journal.events(for: run)
    }

    public func allRuns() async throws -> [RunID] {
        try await journal.allRunIDs()
    }
}
