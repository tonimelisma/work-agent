//
//  RuntimeEnvironment.swift
//  Work Agent
//
//  Where the app injects its credentials and catalog into AgentKit's
//  provider-neutral runtime (agent-loop-implementation.md §7): the package never
//  sees a Keychain or a registry, only a resolved Model + configuration.
//
//  REQ: FR-071 — a run is keyed by conversation, not owned by whichever
//  ChatViewModel happens to be on screen, so switching the sidebar selection
//  never interrupts another conversation's in-flight run.
//

import Foundation
import Observation
import RuntimeCore
import Executors
import FoundationModels
import SwiftData

@MainActor
@Observable
final class RuntimeEnvironment {
    private struct ActiveRun {
        let handle: RunHandle
        let executorID: String
    }

    let coordinator: TaskCoordinator
    private let checkpoints: any CheckpointStore
    private let store: ProviderStore
    private let registryLoader: RegistryLoader
    private var activeRuns: [UUID: ActiveRun] = [:]

    static let instructions = "You are Work Agent, a helpful assistant running natively on the user's Mac."

    init(store: ProviderStore, registryLoader: RegistryLoader) {
        self.store = store
        self.registryLoader = registryLoader

        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("Work Agent", isDirectory: true)

        let journal = (try? FileRunJournal(directory: root.appendingPathComponent("runs/journal")))
            ?? (try! FileRunJournal(directory: FileManager.default.temporaryDirectory.appendingPathComponent("journal")))
        let checkpointStore = (try? FileCheckpointStore(directory: root.appendingPathComponent("runs/checkpoints")))
            ?? (try! FileCheckpointStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("checkpoints")))
        checkpoints = checkpointStore
        coordinator = TaskCoordinator(journal: journal, checkpoints: checkpointStore)
    }

    func isStreaming(_ conversationID: UUID) -> Bool {
        activeRuns[conversationID] != nil
    }

    /// The configured model selection to fail over to automatically (FR-006):
    /// the first other configured provider's first curated model, if one exists.
    func fallbackSelection(excluding primary: ModelSelection) -> ModelSelection? {
        guard let other = store.providers.first(where: { $0.id != primary.providerID }),
              let modelID = CuratedCatalog.modelIDs(for: other.id).first else { return nil }
        return ModelSelection(providerID: other.id, modelID: modelID)
    }

    // REQ: FR-070, FR-071 — send a message in `record`'s conversation. The run
    // outlives whichever view is currently showing this conversation.
    func send(_ text: String, in record: ConversationRecord, selection: ModelSelection) {
        guard !isStreaming(record.id) else { return }

        record.pausedRunIDValue = nil
        record.pausedExecutorID = nil

        var messages = record.messages
        messages.append(ChatMessage(role: .user, text: text))
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, isStreaming: true))
        record.messages = messages
        record.updatedAt = Date()
        if record.title == "New Chat" {
            record.title = String(text.prefix(40))
        }

        let priorArchive = record.archiveData.flatMap { try? TranscriptArchive.decode($0) }
        let fallbackSelection = fallbackSelection(excluding: selection)

        let onDelta: @Sendable (String) -> Void = { [weak self, conversationID = record.id] delta in
            Task { @MainActor in self?.appendDelta(delta, to: assistantID, conversationID: conversationID) }
        }

        recordsByConversationID[record.id] = record

        do {
            let primaryExecutor = try executor(for: selection, prompt: text, onDelta: onDelta)
            let fallbackExecutor = try fallbackSelection.map {
                try executor(for: $0, prompt: text, onDelta: onDelta)
            }

            Task { [weak self] in
                guard let self else { return }
                let handle = await self.coordinator.start(
                    resumingFrom: priorArchive,
                    primaryID: selection.providerID, primary: primaryExecutor,
                    fallbackID: fallbackSelection?.providerID, fallback: fallbackExecutor
                )
                self.activeRuns[record.id] = ActiveRun(handle: handle, executorID: selection.providerID)
                await self.consume(handle: handle, record: record, assistantID: assistantID)
            }
        } catch {
            failAssistant(assistantID, in: record, error: error)
        }
    }

    func stop(_ conversationID: UUID, record: ConversationRecord) {
        activeRuns[conversationID]?.handle.cancel()
        activeRuns.removeValue(forKey: conversationID)
        var messages = record.messages
        if let last = messages.indices.last, messages[last].isStreaming {
            messages[last].isStreaming = false
        }
        record.messages = messages
    }

    /// FR-072 — called by the app delegate before the app actually quits: pause
    /// every in-flight run at its next safe checkpoint and mark it for an
    /// explicit resume, rather than losing or silently continuing the work.
    func pauseAllActiveRunsForTermination() {
        for (conversationID, run) in activeRuns {
            pendingPauseExecutorIDs[conversationID] = run.executorID
            run.handle.cancel()
        }
    }

    // REQ: FR-072 — resume a conversation's paused run explicitly (never automatic).
    func resume(_ record: ConversationRecord, selection: ModelSelection) {
        guard record.pausedRunIDValue != nil, !isStreaming(record.id) else { return }
        var messages = record.messages
        guard let lastIndex = messages.indices.last, messages[lastIndex].role == .assistant else { return }
        messages[lastIndex].isStreaming = true
        record.messages = messages
        let assistantID = messages[lastIndex].id
        record.pausedRunIDValue = nil
        record.pausedExecutorID = nil

        guard let archive = record.archiveData.flatMap({ try? TranscriptArchive.decode($0) }) else { return }
        let checkpoint = RunCheckpoint(
            runID: RunID(), status: .pausedAwaitingResume(reason: .appQuit),
            archive: archive, executorID: selection.providerID
        )
        let fallbackSelection = fallbackSelection(excluding: selection)
        let onDelta: @Sendable (String) -> Void = { [weak self, conversationID = record.id] delta in
            Task { @MainActor in self?.appendDelta(delta, to: assistantID, conversationID: conversationID) }
        }

        recordsByConversationID[record.id] = record

        do {
            // Resuming replays the same last user prompt against the resumed transcript.
            let prompt = messages.last(where: { $0.role == .user })?.text ?? ""
            let primaryExecutor = try executor(for: selection, prompt: prompt, onDelta: onDelta)
            let fallbackExecutor = try fallbackSelection.map {
                try executor(for: $0, prompt: prompt, onDelta: onDelta)
            }
            Task { [weak self] in
                guard let self else { return }
                let handle = await self.coordinator.resume(
                    checkpoint, primaryID: selection.providerID, primary: primaryExecutor,
                    fallbackID: fallbackSelection?.providerID, fallback: fallbackExecutor
                )
                self.activeRuns[record.id] = ActiveRun(handle: handle, executorID: selection.providerID)
                await self.consume(handle: handle, record: record, assistantID: assistantID)
            }
        } catch {
            failAssistant(assistantID, in: record, error: error)
        }
    }

    private var pendingPauseExecutorIDs: [UUID: String] = [:]

    private func consume(handle: RunHandle, record: ConversationRecord, assistantID: UUID) async {
        do {
            for try await event in handle.events {
                switch event {
                case .runPaused:
                    if let executorID = pendingPauseExecutorIDs.removeValue(forKey: record.id) {
                        record.pausedRunIDValue = handle.id.rawValue
                        record.pausedExecutorID = executorID
                    }
                    markAssistantStreamingDone(assistantID, in: record)
                case .runCompleted:
                    if let checkpoint = try? await checkpoints.load(handle.id) {
                        record.archiveData = try? checkpoint.archive.encoded()
                    }
                    markAssistantStreamingDone(assistantID, in: record)
                default:
                    break
                }
            }
        } catch {
            failAssistant(assistantID, in: record, error: error)
        }
        activeRuns.removeValue(forKey: record.id)
        pendingPauseExecutorIDs.removeValue(forKey: record.id)
        recordsByConversationID.removeValue(forKey: record.id)
    }

    private func appendDelta(_ delta: String, to assistantID: UUID, conversationID: UUID) {
        guard let record = recordsByConversationID[conversationID] else { return }
        var messages = record.messages
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].text += delta
        record.messages = messages
    }

    /// Records currently driving a run, so a delta callback (which only knows the
    /// conversation id, to stay `Sendable`) can find its way back to the SwiftData
    /// instance the rest of this class already holds a reference to.
    private var recordsByConversationID: [UUID: ConversationRecord] = [:]

    private func markAssistantStreamingDone(_ assistantID: UUID, in record: ConversationRecord) {
        var messages = record.messages
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].isStreaming = false
        }
        record.messages = messages
        record.updatedAt = Date()
    }

    private func failAssistant(_ assistantID: UUID, in record: ConversationRecord, error: Error) {
        var messages = record.messages
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].isStreaming = false
            messages[index].failure = friendlyDescription(for: error)
        }
        record.messages = messages
        activeRuns.removeValue(forKey: record.id)
        recordsByConversationID.removeValue(forKey: record.id)
    }

    // REQ: PRODUCT.md §2 — no status codes or protocol vocabulary reach the user.
    private func friendlyDescription(for error: Error) -> String? {
        if let chatError = error as? ChatError { return chatError.errorDescription }
        if case let LiveExecutorError.httpFailure(_, status) = error {
            return ChatError.from(status: status).errorDescription
        }
        return ChatError.unreachable(error.localizedDescription).errorDescription
    }

    /// Builds the erased attempt executor AgentKit's `TaskCoordinator` runs for
    /// `selection`: constructs the concrete `LanguageModel`, then defers to
    /// `runSessionAttempt` — the one place a `LanguageModelSession` is created.
    private func executor(
        for selection: ModelSelection,
        prompt: String,
        onDelta: @escaping @Sendable (String) -> Void
    ) throws -> RunAttemptExecutor {
        guard let registryProvider = registryLoader.registry?.provider(id: selection.providerID) else {
            throw ChatError.notConfigured
        }
        guard let key = try store.key(for: selection.providerID), !key.isEmpty else {
            throw ChatError.rejected
        }

        if selection.providerID == "anthropic" {
            let model = AnthropicModel(model: selection.modelID, apiKey: key)
            return { resumeArchive in
                try await runSessionAttempt(
                    model: model, tools: [], instructions: Self.instructions,
                    resuming: resumeArchive, prompt: prompt, onDelta: onDelta
                )
            }
        }

        guard let base = ProviderCatalog.chatBaseURL(for: registryProvider) else {
            throw ChatError.notConfigured
        }
        let model = OpenAICompatibleModel(
            providerID: selection.providerID,
            model: selection.modelID,
            endpoint: base.appendingPathComponent("chat/completions"),
            apiKey: key
        )
        return { resumeArchive in
            try await runSessionAttempt(
                model: model, tools: [], instructions: Self.instructions,
                resuming: resumeArchive, prompt: prompt, onDelta: onDelta
            )
        }
    }
}
