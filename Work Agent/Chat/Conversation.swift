//
//  Conversation.swift
//  Work Agent
//
//  The chat data model. One conversation, persisted in full.
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

/// The full conversation. One per app, for now (multiple conversations are deferred).
nonisolated struct Conversation: Codable, Sendable {
    var messages: [ChatMessage] = []

    /// Messages to send to the model: only role + text, reasoning stripped.
    var wireMessages: [ChatMessage] {
        messages
            .filter { !$0.text.isEmpty && $0.failure == nil }
            .map { ChatMessage(role: $0.role, text: $0.text) }
    }
}
