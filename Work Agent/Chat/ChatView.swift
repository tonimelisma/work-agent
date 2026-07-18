//
//  ChatView.swift
//  Work Agent
//
//  The main window: a chat. Messages scroll above, composer pinned at the bottom.
//

import SwiftUI

// REQ: FR-068 — the main window is a chat: history above, text input at the bottom.
struct ChatView: View {
    @Environment(ProviderStore.self) private var store
    @Environment(RegistryLoader.self) private var registryLoader
    @Environment(\.openSettings) private var openSettings

    @State private var model: ChatViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .task {
            if registryLoader.registry == nil { await registryLoader.loadLocal() }
            if model == nil {
                model = ChatViewModel(store: store, registryLoader: registryLoader)
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ChatViewModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if conversationIsEmpty(model) {
                emptyState
            } else {
                transcript(model)
            }
            Divider()
            Composer(model: model, openSettings: { openSettings() })
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.clear()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .disabled(model.conversation.messages.isEmpty)
                .help("Clear the conversation")
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func conversationIsEmpty(_ model: ChatViewModel) -> Bool {
        model.conversation.messages.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: store.hasProviders ? "text.bubble" : "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            if store.hasProviders {
                Text("Ask anything")
                    .font(.title3.weight(.medium))
                Text("Pick a model below and start typing.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("No model connected")
                    .font(.title3.weight(.medium))
                Text("Add a model in Settings to get started.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Settings…") { openSettings() }
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcript(_ model: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.conversation.messages) { message in
                        MessageRow(message: message, showReasoning: model.showReasoning)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(scrollAnchor)
                }
                .padding(16)
            }
            .onChange(of: model.conversation.messages.last?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(scrollAnchor, anchor: .bottom) }
            }
            .onChange(of: model.conversation.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(scrollAnchor, anchor: .bottom) }
            }
        }
    }

    private let scrollAnchor = "bottom-anchor"
}

// MARK: - Message row

private struct MessageRow: View {
    let message: ChatMessage
    let showReasoning: Bool

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // REQ: FR-065 — reasoning shown in a friendly, separate region.
                if message.hasReasoning && showReasoning && message.role == .assistant {
                    ReasoningBlock(text: message.reasoning, isStreaming: message.isStreaming && message.text.isEmpty)
                }
                if let failure = message.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                } else if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                } else if message.isStreaming {
                    ProgressView().controlSize(.small)
                }
            }
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var bubbleColor: Color {
        message.role == .user ? Color.accentColor : Color(nsColor: .controlBackgroundColor)
    }
}

private struct ReasoningBlock: View {
    let text: String
    let isStreaming: Bool
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Label(isStreaming ? "Thinking…" : "Reasoning", systemImage: "brain")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Composer

private struct Composer: View {
    @Bindable var model: ChatViewModel
    let openSettings: () -> Void
    @Environment(ProviderStore.self) private var store
    @Environment(RegistryLoader.self) private var registryLoader
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                modelPicker

                TextField("Message", text: $model.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .focused($focused)
                    .onSubmit(sendIfPossible)
                    .disabled(!store.hasProviders)

                if model.isStreaming {
                    Button(action: model.stop) {
                        Image(systemName: "stop.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless).help("Stop")
                } else {
                    Button(action: sendIfPossible) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canSend)
                    .help("Send")
                }
            }
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private func sendIfPossible() {
        guard model.canSend else { return }
        model.send()
    }

    // REQ: FR-055 — model chosen here, across all configured providers (FR-061 curated).
    @ViewBuilder
    private var modelPicker: some View {
        if store.hasProviders, let registry = registryLoader.registry {
            Menu {
                ForEach(store.providers) { provider in
                    let models = registry.curatedModels(for: provider.id)
                    if !models.isEmpty {
                        Section(provider.displayName) {
                            ForEach(models) { m in
                                Button {
                                    store.select(providerID: provider.id, modelID: m.id)
                                } label: {
                                    if isSelected(provider.id, m.id) {
                                        Label(m.name, systemImage: "checkmark")
                                    } else {
                                        Text(m.name)
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(model.selectedModelName ?? "Model", systemImage: "cpu")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            Button("Add a model…", action: openSettings)
                .controlSize(.small)
        }
    }

    private func isSelected(_ providerID: String, _ modelID: String) -> Bool {
        store.selectedModel == ModelSelection(providerID: providerID, modelID: modelID)
    }
}
