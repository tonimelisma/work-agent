//
//  ConversationRecord.swift
//  Work Agent
//
//  SwiftData persistence for a durable conversation (ADR-0008). One record per
//  conversation in the sidebar (FR-071); the messages a user sees are stored
//  alongside the raw TranscriptArchive a run resumes from, so the UI projection
//  (FR-065/066: friendly display) never has to be reverse-engineered from the
//  model-facing transcript, and vice versa (FR-063: everything is kept).
//

import Foundation
import SwiftData

@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    /// JSON-encoded `[ChatMessage]` — what the UI renders.
    var messagesData: Data
    /// JSON-encoded `TranscriptArchive` from the last committed run, if any turn has
    /// completed — what the next run resumes from. Nil for a conversation with no
    /// assistant reply yet.
    var archiveData: Data?

    // REQ: FR-072 — a run that was paused by an app quit, awaiting explicit resume.
    var pausedRunIDValue: UUID?
    var pausedExecutorID: String?

    init(id: UUID = UUID(), title: String = "New Chat", createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        updatedAt = createdAt
        messagesData = (try? JSONEncoder().encode([ChatMessage]())) ?? Data()
    }

    var messages: [ChatMessage] {
        get { (try? JSONDecoder().decode([ChatMessage].self, from: messagesData)) ?? [] }
        set { messagesData = (try? JSONEncoder().encode(newValue)) ?? messagesData }
    }
}
