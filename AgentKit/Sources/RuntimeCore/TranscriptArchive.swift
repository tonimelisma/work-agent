import Foundation
import FoundationModels
import ToolVocabulary

// REQ: agent-loop-implementation.md §3 — a versioned TranscriptArchive stores Apple's
// Codable transcript as the model-context projection; reconstruction derives a session
// from committed run state and strips foreign-provider metadata (FR-006 failover).
// Migrated from Experiments/FoundationModelsPOC/Sources/FoundationModelsPOC/DurableTranscript.swift,
// proven live against DeepSeek, Google, and Anthropic (increment 3).

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
public struct TranscriptArchive: Codable, Sendable {
    public static let currentVersion = 1
    public static let signatureProviderMetadataKey = TranscriptMetadataKeys.signatureProvider

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
    /// This is the mechanism FR-006 automatic failover reconstructs a session on.
    public func replay(to destinationProvider: String) throws -> TranscriptArchive {
        TranscriptArchive(
            version: version,
            transcript: Transcript(entries: try transcript.map { entry in
                try Self.filtered(entry, destinationProvider: destinationProvider)
            })
        )
    }

    private static func filtered(
        _ entry: Transcript.Entry,
        destinationProvider: String
    ) throws -> Transcript.Entry {
        switch entry {
        case .prompt(var prompt):
            prompt.metadata = filtered(prompt.metadata, for: destinationProvider)
            return .prompt(prompt)

        case let .toolCalls(toolCalls):
            let calls = toolCalls.map { call in
                Transcript.ToolCall(
                    id: call.id,
                    metadata: filtered(call.metadata, for: destinationProvider),
                    toolName: call.toolName,
                    arguments: call.arguments
                )
            }
            return .toolCalls(Transcript.ToolCalls(id: toolCalls.id, calls))

        case let .response(response):
            return .response(
                Transcript.Response(
                    id: response.id,
                    metadata: filtered(response.metadata, for: destinationProvider),
                    segments: response.segments
                )
            )

        case let .reasoning(reasoning):
            var metadata = filtered(reasoning.metadata, for: destinationProvider)
            let signatureProvider = reasoning.metadata[signatureProviderMetadataKey] as? String
            let destinationOwnsSignature = signatureProvider == destinationProvider
            if !destinationOwnsSignature {
                metadata.removeValue(forKey: signatureProviderMetadataKey)
            }
            return .reasoning(
                Transcript.Reasoning(
                    id: reasoning.id,
                    metadata: metadata,
                    segments: reasoning.segments,
                    signature: destinationOwnsSignature ? reasoning.signature : nil
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
