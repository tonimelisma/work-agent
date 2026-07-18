//
//  ProviderStore.swift
//  Work Agent
//
//  The user's configured providers and which model the chat targets.
//  Metadata only — secrets live in the Keychain.
//

import Foundation
import Observation

/// A provider the user has configured, identified by its models.dev id.
///
// REQ: FR-069 — the configured unit is provider + key. The key lives in the Keychain
// under `keychainAccount`; this type is written to preferences and deliberately holds
// no secret (FR-052). The model is chosen in the chat, not here (revises FR-050/FR-055).
nonisolated struct ConfiguredProvider: Codable, Identifiable, Hashable {
    let id: String
    /// Display name captured at configure time, so the row still reads correctly if the
    /// registry later renames or drops the provider.
    var displayName: String
    /// The last few characters of the key, for the list. Not a secret.
    var keyHint: String
    var addedAt: Date

    var keychainAccount: String { "provider.\(id)" }
}

/// The model the chat is currently pointed at.
// REQ: FR-055 — the user designates which provider and model is used.
nonisolated struct ModelSelection: Codable, Hashable {
    var providerID: String
    var modelID: String
}

/// Persists which providers are configured and which model the chat targets.
@MainActor
@Observable
final class ProviderStore {
    private(set) var providers: [ConfiguredProvider] = []
    private(set) var selectedModel: ModelSelection?

    private let defaults: UserDefaults
    private let providersKey = "configuredProviders"
    private let selectionKey = "selectedModel"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var hasProviders: Bool { !providers.isEmpty }

    func isConfigured(_ providerID: String) -> Bool {
        providers.contains { $0.id == providerID }
    }

    private func load() {
        if let data = defaults.data(forKey: providersKey),
           let decoded = try? JSONDecoder().decode([ConfiguredProvider].self, from: data) {
            providers = decoded
        }
        if let data = defaults.data(forKey: selectionKey),
           let decoded = try? JSONDecoder().decode(ModelSelection.self, from: data) {
            selectedModel = decoded
        }
        reconcileSelection()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: providersKey)
        }
        if let selection = selectedModel, let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: selectionKey)
        } else {
            defaults.removeObject(forKey: selectionKey)
        }
    }

    /// Add or replace a provider, storing its key in the Keychain.
    // REQ: FR-050/FR-069 — the user configures a provider by pasting its API key.
    func add(providerID: String, displayName: String, key: String) throws {
        try Keychain.set(key, account: "provider.\(providerID)")
        let provider = ConfiguredProvider(
            id: providerID,
            displayName: displayName,
            keyHint: Self.hint(for: key),
            addedAt: Date()
        )
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        sortProviders()
        // First provider added: point the chat at its first curated model, so the app
        // is immediately usable rather than configured-but-idle.
        if selectedModel == nil, let first = CuratedCatalog.modelIDs(for: provider.id).first {
            selectedModel = ModelSelection(providerID: provider.id, modelID: first)
        }
        save()
    }

    /// A non-secret hint like "…X3IA" — enough to tell two keys apart, no more.
    private static func hint(for key: String) -> String {
        let tail = key.suffix(4)
        return tail.isEmpty ? "" : "…\(tail)"
    }

    /// Remove a provider and delete its credential.
    // REQ: FR-057 — removing a provider deletes its stored credential.
    func remove(_ provider: ConfiguredProvider) throws {
        try Keychain.delete(account: provider.keychainAccount)
        providers.removeAll { $0.id == provider.id }
        reconcileSelection()
        save()
    }

    // REQ: FR-055 — the user designates which provider and model is used.
    func select(providerID: String, modelID: String) {
        guard isConfigured(providerID) else { return }
        selectedModel = ModelSelection(providerID: providerID, modelID: modelID)
        save()
    }

    /// The API key for a configured provider, or nil. Read on demand — never cached.
    // REQ: FR-052 — the key is fetched from the Keychain at the point of use.
    func key(for providerID: String) throws -> String? {
        try Keychain.get(account: "provider.\(providerID)")
    }

    private func sortProviders() {
        // Curated display order, so the list reads the same as the menus.
        providers.sort {
            let l = CuratedCatalog.providerOrder.firstIndex(of: $0.id) ?? .max
            let r = CuratedCatalog.providerOrder.firstIndex(of: $1.id) ?? .max
            return l < r
        }
    }

    /// Never leave the selection pointing at a provider that isn't configured.
    private func reconcileSelection() {
        if let selection = selectedModel, isConfigured(selection.providerID) { return }
        if let firstProvider = providers.first,
           let firstModel = CuratedCatalog.modelIDs(for: firstProvider.id).first {
            selectedModel = ModelSelection(providerID: firstProvider.id, modelID: firstModel)
        } else {
            selectedModel = nil
        }
    }
}
