//
//  ProviderSettingsView.swift
//  Work Agent
//
//  Settings: a plain list of providers you add and remove by API key.
//

import SwiftUI

// REQ: FR-069 — add and remove providers by API key.
struct ProviderSettingsView: View {
    @Environment(ProviderStore.self) private var store
    @Environment(RegistryLoader.self) private var registryLoader

    @State private var isAdding = false
    @State private var selection: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if store.providers.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            bottomBar
        }
        .frame(width: 520, height: 360)
        .task { if registryLoader.registry == nil { await registryLoader.loadLocal() } }
        .sheet(isPresented: $isAdding) { AddProviderSheet() }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "key")
                .font(.system(size: 30)).foregroundStyle(.tertiary)
            Text("No models connected").font(.title3.weight(.medium))
            Text("Add a provider with your API key. Keys stay on this Mac.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add Provider…") { isAdding = true }
                .controlSize(.large).padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.providers) { provider in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(provider.displayName).font(.body)
                        Text("Key \(provider.keyHint)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .tag(provider.id)
                .contextMenu {
                    Button("Remove", role: .destructive) { remove(provider.id) }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // Classic macOS +/− strip.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button { isAdding = true } label: {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help("Add a provider")

            Button { if let selection { remove(selection) } } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(selection == nil)
            .help("Remove the selected provider")

            Spacer()

            registryStatus
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    // REQ: FR-054 — quietly shows whether the model list is current, and can refresh it.
    private var registryStatus: some View {
        HStack(spacing: 6) {
            if registryLoader.isRefreshing { ProgressView().controlSize(.small) }
            if let source = registryLoader.source {
                Text(source.label).font(.caption).foregroundStyle(.secondary)
            }
            Button("Refresh") { Task { await registryLoader.refresh() } }
                .buttonStyle(.link).font(.caption).disabled(registryLoader.isRefreshing)
        }
    }

    private func remove(_ providerID: String) {
        guard let provider = store.providers.first(where: { $0.id == providerID }) else { return }
        do { try store.remove(provider) } catch { errorMessage = error.localizedDescription }
        if selection == providerID { selection = nil }
    }
}
