import Foundation

// REQ: the append-only run journal is execution
// truth, storage-protocol first so a host can choose the concrete store (this
// package ships a file-backed implementation; a host's own persistence choice
// does not have to be this protocol's backing).
public protocol RunJournal: Sendable {
    func append(_ event: RunEvent, for run: RunID) async throws
    func events(for run: RunID) async throws -> [RunEvent]
    func allRunIDs() async throws -> [RunID]
}

public enum RunJournalError: LocalizedError, Equatable, Sendable {
    case corruptEntry(runID: RunID, line: Int)

    public var errorDescription: String? {
        switch self {
        case let .corruptEntry(runID, line):
            "Run journal for \(runID) has a corrupt entry at line \(line)"
        }
    }
}

/// Durable, suspension-safe: each event is appended and fsynced before the call
/// returns, so a checkpoint is never lost to a process the OS kills without warning.
public actor FileRunJournal: RunJournal {
    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for run: RunID) -> URL {
        directory.appendingPathComponent("\(run.rawValue.uuidString).jsonl")
    }

    public func append(_ event: RunEvent, for run: RunID) async throws {
        let data = try JSONEncoder().encode(event)
        var line = data
        line.append(UInt8(ascii: "\n"))
        let url = fileURL(for: run)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.synchronize()
            try handle.close()
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    public func events(for run: RunID) async throws -> [RunEvent] {
        let url = fileURL(for: run)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        let lines = data.split(separator: UInt8(ascii: "\n"))
        var events: [RunEvent] = []
        for (index, lineData) in lines.enumerated() {
            guard let event = try? decoder.decode(RunEvent.self, from: Data(lineData)) else {
                // A torn tail — a partial final line from a crash mid-append — is the
                // expected residue of the exact failure this journal exists to survive;
                // everything decoded before it is still good. Corruption anywhere else
                // in the file is a real integrity problem and still throws.
                if index == lines.count - 1 { return events }
                throw RunJournalError.corruptEntry(runID: run, line: index + 1)
            }
            events.append(event)
        }
        return events
    }

    public func allRunIDs() async throws -> [RunID] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files.compactMap { url in
            guard url.pathExtension == "jsonl",
                  let uuid = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                return nil
            }
            return RunID(uuid)
        }
    }
}
