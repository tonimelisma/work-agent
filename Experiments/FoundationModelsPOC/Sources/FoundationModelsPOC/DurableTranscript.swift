import Foundation

/// App-owned, Codable persistence boundary. Provider state remains namespaced and is
/// deliberately excluded when replaying to another provider.
public struct DurableTranscript: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case prompt, response, reasoning, toolCall, toolOutput }
        public var id: String
        public var kind: Kind
        public var text: String
        public var metadata: [String: String]
        public init(id: String, kind: Kind, text: String, metadata: [String: String] = [:]) {
            self.id = id; self.kind = kind; self.text = text; self.metadata = metadata
        }
    }
    public var entries: [Entry]
    public init(entries: [Entry] = []) { self.entries = entries }

    public func replay(for provider: String) -> DurableTranscript {
        DurableTranscript(entries: entries.map { entry in
            var copy = entry
            copy.metadata = entry.metadata.filter { $0.key.hasPrefix("neutral.") || $0.key.hasPrefix("\(provider).") }
            return copy
        })
    }
}
