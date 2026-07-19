//
//  Conversation.swift
//  Work Agent
//
//  A chat message and its role. Persistence is ConversationRecord's job
//  (SwiftData, ADR-0008); this is just the wire/display shape (FR-063).
//

import Foundation

nonisolated enum ChatRole: String, Codable, Hashable, Sendable {
    case system, user, assistant
}

/// A single message. Carries both what's shown and the full trace.
// REQ: FR-063 — reasoning and text are both persisted; display is a separate choice.
nonisolated struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var role: ChatRole
    var text: String
    /// Model reasoning, accumulated. Empty when the model emits none.
    var reasoning: String
    /// True while tokens are still streaming into this message.
    var isStreaming: Bool
    /// Human-readable failure attached to this turn, if it failed.
    var failure: String?

    init(id: UUID = UUID(), role: ChatRole, text: String = "",
         reasoning: String = "", isStreaming: Bool = false, failure: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.isStreaming = isStreaming
        self.failure = failure
    }

    var hasReasoning: Bool { !reasoning.isEmpty }
}
