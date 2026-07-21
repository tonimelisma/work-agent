import Foundation

// REQ: FR-073 — a conversation's run status survives an app restart. The checkpoint
// is the durable position the app's conductor resumes from; it must be written before
// the run is exposed to the app as safely paused/completed (agent-loop-implementation.md §5).
public protocol CheckpointStore: Sendable {
    func save(_ checkpoint: RunCheckpoint) async throws
    func load(_ run: RunID) async throws -> RunCheckpoint?
    func loadAll() async throws -> [RunCheckpoint]
    func delete(_ run: RunID) async throws
}

public actor FileCheckpointStore: CheckpointStore {
    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for run: RunID) -> URL {
        directory.appendingPathComponent("\(run.rawValue.uuidString).json")
    }

    public func save(_ checkpoint: RunCheckpoint) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)
        try data.write(to: fileURL(for: checkpoint.runID), options: .atomic)
    }

    public func load(_ run: RunID) async throws -> RunCheckpoint? {
        guard let data = try? Data(contentsOf: fileURL(for: run)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RunCheckpoint.self, from: data)
    }

    public func loadAll() async throws -> [RunCheckpoint] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(RunCheckpoint.self, from: data)
        }
    }

    public func delete(_ run: RunID) async throws {
        try? FileManager.default.removeItem(at: fileURL(for: run))
    }
}
