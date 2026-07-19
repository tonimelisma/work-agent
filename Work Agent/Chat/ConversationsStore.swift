//
//  ConversationsStore.swift
//  Work Agent
//
//  REQ: FR-071 — which conversation the sidebar has selected. The conversation
//  list itself comes from a SwiftData @Query in the view; this just owns
//  selection plus create/delete, which touch the ModelContext directly.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationsStore {
    var selectedID: UUID?

    func create(in context: ModelContext) -> ConversationRecord {
        let record = ConversationRecord()
        context.insert(record)
        try? context.save()
        selectedID = record.id
        return record
    }

    func delete(_ record: ConversationRecord, in context: ModelContext) {
        if selectedID == record.id { selectedID = nil }
        context.delete(record)
        try? context.save()
    }
}
