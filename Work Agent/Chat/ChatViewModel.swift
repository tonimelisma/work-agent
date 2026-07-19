//
//  ChatViewModel.swift
//  Work Agent
//
//  Thin per-conversation UI state. Execution lives in RuntimeEnvironment, keyed
//  by conversation id (FR-071) — not here — so a run outlives this object's
//  lifetime across sidebar selection changes.
//

import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    let record: ConversationRecord
    var input = ""
    /// FR-066 — the user can turn reasoning display on or off. On by default.
    var showReasoning = true

    private let store: ProviderStore
    private let registryLoader: RegistryLoader
    private let runtime: RuntimeEnvironment

    init(record: ConversationRecord, store: ProviderStore, registryLoader: RegistryLoader, runtime: RuntimeEnvironment) {
        self.record = record
        self.store = store
        self.registryLoader = registryLoader
        self.runtime = runtime
    }

    var messages: [ChatMessage] { record.messages }
    var isStreaming: Bool { runtime.isStreaming(record.id) }
    var isPaused: Bool { record.pausedRunIDValue != nil }
    var pausedExecutorID: String? { record.pausedExecutorID }

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isStreaming
            && store.selectedModel != nil
    }

    /// Display name of the currently selected model, if resolvable.
    var selectedModelName: String? {
        guard let selection = store.selectedModel,
              let model = registryLoader.registry?
                .curatedModels(for: selection.providerID)
                .first(where: { $0.id == selection.modelID }) else { return nil }
        return model.name
    }

    // REQ: FR-070 — sending a message runs it through the durable runtime.
    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let selection = store.selectedModel else { return }
        input = ""
        runtime.send(text, in: record, selection: selection)
    }

    func stop() {
        runtime.stop(record.id, record: record)
    }

    // REQ: FR-072 — resume a run the user paused (or that paused itself on quit).
    func resume() {
        guard let selection = store.selectedModel else { return }
        runtime.resume(record, selection: selection)
    }

    func clear() {
        stop()
        record.messages = []
        record.archiveData = nil
    }
}
