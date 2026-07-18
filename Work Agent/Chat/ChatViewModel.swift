//
//  ChatViewModel.swift
//  Work Agent
//
//  Owns the conversation, drives streaming, persists everything.
//

import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "net.melisma.Work-Agent", category: "chat")

@MainActor
@Observable
final class ChatViewModel {
    private(set) var conversation = Conversation()
    private(set) var isStreaming = false
    var input = ""
    /// FR-066 — the user can turn reasoning display on or off. On by default.
    var showReasoning = true

    private let store: ProviderStore
    private let registryLoader: RegistryLoader
    private var streamTask: Task<Void, Never>?

    init(store: ProviderStore, registryLoader: RegistryLoader) {
        self.store = store
        self.registryLoader = registryLoader
        load()
    }

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

    // REQ: FR-070 — sending a message streams the selected model's reply.
    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let selection = store.selectedModel else { return }
        input = ""

        conversation.messages.append(ChatMessage(role: .user, text: text))
        var assistant = ChatMessage(role: .assistant, isStreaming: true)
        conversation.messages.append(assistant)
        let assistantID = assistant.id
        isStreaming = true
        save()

        let wire = conversation.wireMessages

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let registryProvider = registryLoader.registry?.provider(id: selection.providerID) else {
                    throw ChatError.notConfigured
                }
                guard let key = try store.key(for: selection.providerID), !key.isEmpty else {
                    throw ChatError.rejected
                }
                guard let provider = ChatProviderFactory.provider(for: registryProvider) else {
                    throw ChatError.notConfigured
                }

                for try await chunk in provider.stream(messages: wire, model: selection.modelID, apiKey: key) {
                    switch chunk {
                    case .text(let t): assistant.text += t
                    case .reasoning(let r): assistant.reasoning += r
                    }
                    updateAssistant(id: assistantID, with: assistant)
                }
                assistant.isStreaming = false
                updateAssistant(id: assistantID, with: assistant)
            } catch {
                assistant.isStreaming = false
                assistant.failure = (error as? ChatError)?.errorDescription
                    ?? ChatError.unreachable(error.localizedDescription).errorDescription
                updateAssistant(id: assistantID, with: assistant)
                log.warning("Chat stream failed: \(error.localizedDescription, privacy: .public)")
            }
            isStreaming = false
            save()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let last = conversation.messages.indices.last, conversation.messages[last].isStreaming {
            conversation.messages[last].isStreaming = false
        }
        save()
    }

    func clear() {
        stop()
        conversation = Conversation()
        save()
    }

    private func updateAssistant(id: UUID, with message: ChatMessage) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index] = message
    }

    // MARK: - Persistence (FR-063: everything is kept)

    private var fileURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        let appDir = dir.appendingPathComponent("Work Agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("conversation.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Conversation.self, from: data) else { return }
        conversation = decoded
        // A stream that was interrupted by a quit is no longer streaming.
        for index in conversation.messages.indices where conversation.messages[index].isStreaming {
            conversation.messages[index].isStreaming = false
        }
    }

    private func save() {
        guard let fileURL else { return }
        if let data = try? JSONEncoder().encode(conversation) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
