//
//  ConversationListView.swift
//  Work Agent
//
//  REQ: FR-071 — the sidebar list of conversations, Cowork-style. Each row is a
//  durable conversation; selecting one never interrupts another's in-flight run.
//

import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Query(sort: \ConversationRecord.updatedAt, order: .reverse) private var conversations: [ConversationRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(ConversationsStore.self) private var conversationsStore
    @Environment(RuntimeEnvironment.self) private var runtime

    var body: some View {
        @Bindable var conversationsStore = conversationsStore
        List(selection: $conversationsStore.selectedID) {
            ForEach(conversations) { record in
                row(for: record).tag(record.id)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Conversations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    _ = conversationsStore.create(in: modelContext)
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New conversation")
            }
        }
        .task {
            if conversationsStore.selectedID == nil {
                conversationsStore.selectedID = conversations.first?.id
            }
        }
    }

    private func row(for record: ConversationRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(record.title).lineLimit(1)
                Spacer()
                if runtime.isStreaming(record.id) {
                    ProgressView().controlSize(.mini)
                } else if record.pausedRunIDValue != nil {
                    Image(systemName: "pause.circle").foregroundStyle(.secondary)
                }
            }
            if let last = record.messages.last(where: { !$0.text.isEmpty }) {
                Text(last.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { conversationsStore.delete(conversations[index], in: modelContext) }
    }
}
