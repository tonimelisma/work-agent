import Foundation
import FoundationModels

@available(macOS 27.0, *)
public enum TranscriptArchiveError: LocalizedError, Equatable, Sendable {
    case unsupportedEntry(id: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedEntry(id):
            "Cannot safely filter metadata for unknown transcript entry \(id)"
        }
    }
}

/// Versioned app persistence around Apple's Codable transcript.
@available(macOS 27.0, *)
public struct TranscriptArchive: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var transcript: Transcript

    public init(version: Int = currentVersion, transcript: Transcript) {
        self.version = version
        self.transcript = transcript
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TranscriptArchive {
        try JSONDecoder().decode(TranscriptArchive.self, from: data)
    }

    /// Returns a replay archive that retains neutral metadata and metadata owned by
    /// the destination provider while preserving Apple's typed transcript entries.
    public func replay(for provider: String) throws -> TranscriptArchive {
        TranscriptArchive(
            version: version,
            transcript: Transcript(entries: try transcript.map { entry in
                try Self.filtered(entry, for: provider)
            })
        )
    }

    private static func filtered(
        _ entry: Transcript.Entry,
        for provider: String
    ) throws -> Transcript.Entry {
        switch entry {
        case .prompt(var prompt):
            prompt.metadata = filtered(prompt.metadata, for: provider)
            return .prompt(prompt)

        case let .toolCalls(toolCalls):
            let calls = toolCalls.map { call in
                Transcript.ToolCall(
                    id: call.id,
                    metadata: filtered(call.metadata, for: provider),
                    toolName: call.toolName,
                    arguments: call.arguments
                )
            }
            return .toolCalls(Transcript.ToolCalls(id: toolCalls.id, calls))

        case let .response(response):
            return .response(
                Transcript.Response(
                    id: response.id,
                    metadata: filtered(response.metadata, for: provider),
                    segments: response.segments
                )
            )

        case let .reasoning(reasoning):
            return .reasoning(
                Transcript.Reasoning(
                    id: reasoning.id,
                    metadata: filtered(reasoning.metadata, for: provider),
                    segments: reasoning.segments,
                    signature: reasoning.signature
                )
            )

        case .instructions, .toolOutput:
            return entry

        @unknown default:
            throw TranscriptArchiveError.unsupportedEntry(id: entry.id)
        }
    }

    private static func filtered(
        _ metadata: [String: any Codable & Sendable & Equatable],
        for provider: String
    ) -> [String: any Codable & Sendable & Equatable] {
        metadata.filter {
            $0.key.hasPrefix("neutral.") || $0.key.hasPrefix("\(provider).")
        }
    }
}
