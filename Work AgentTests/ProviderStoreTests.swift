//
//  ProviderStoreTests.swift
//  Work AgentTests
//

import Foundation
import Testing
@testable import Work_Agent

private func isolatedDefaults() -> UserDefaults {
    let name = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Configured provider persistence", .serialized)
@MainActor
struct ProviderStoreTests {

    @Test("FR-052: a configured provider carries no credential into preferences")
    func credentialNeverPersistedInDefaults() throws {
        let defaults = isolatedDefaults()
        let store = ProviderStore(defaults: defaults)
        try store.add(providerID: "anthropic", displayName: "Anthropic", key: "sk-ant-SUPER-SECRET")
        defer { try? store.remove(store.providers[0]) }

        let data = try #require(defaults.data(forKey: "configuredProviders"))
        let asString = String(decoding: data, as: UTF8.self)
        #expect(!asString.contains("SUPER-SECRET"))
        #expect(!asString.contains("sk-ant-SUPER"))
    }

    @Test("FR-069: the row shows a non-secret key hint, not the key")
    func keyHintIsNotTheKey() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        try store.add(providerID: "openai", displayName: "OpenAI", key: "sk-proj-abcdWXYZ")
        defer { try? store.remove(store.providers[0]) }

        let hint = store.providers[0].keyHint
        #expect(hint == "…WXYZ")
        #expect(!hint.contains("abcd"))
    }

    @Test("FR-050 / FR-063: configured providers and selection survive a restart")
    func persistsAcrossInstances() throws {
        let defaults = isolatedDefaults()
        let first = ProviderStore(defaults: defaults)
        try first.add(providerID: "anthropic", displayName: "Anthropic", key: "k")
        defer { try? first.remove(first.providers[0]) }

        let second = ProviderStore(defaults: defaults)
        #expect(second.providers.count == 1)
        #expect(second.providers.first?.id == "anthropic")
        #expect(second.selectedModel?.providerID == "anthropic")
    }

    @Test("FR-055: the first provider added selects its first curated model")
    func firstProviderSelectsCuratedModel() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        try store.add(providerID: "openai", displayName: "OpenAI", key: "k")
        defer { try? store.remove(store.providers[0]) }

        // CuratedCatalog lists gpt-5.6 first for openai.
        #expect(store.selectedModel == ModelSelection(providerID: "openai", modelID: "gpt-5.6"))
    }

    @Test("FR-055: adding a second provider does not steal the selection")
    func secondProviderKeepsSelection() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        try store.add(providerID: "openai", displayName: "OpenAI", key: "k")
        try store.add(providerID: "anthropic", displayName: "Anthropic", key: "k")
        defer { for p in store.providers { try? store.remove(p) } }

        #expect(store.selectedModel?.providerID == "openai")
    }

    @Test("FR-055: the user can select a different model, if its provider is configured")
    func selectModel() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        try store.add(providerID: "openai", displayName: "OpenAI", key: "k")
        try store.add(providerID: "anthropic", displayName: "Anthropic", key: "k")
        defer { for p in store.providers { try? store.remove(p) } }

        store.select(providerID: "anthropic", modelID: "claude-sonnet-5")
        #expect(store.selectedModel == ModelSelection(providerID: "anthropic", modelID: "claude-sonnet-5"))

        // Selecting a provider that isn't configured is ignored.
        store.select(providerID: "google", modelID: "gemini-3.5-flash")
        #expect(store.selectedModel?.providerID == "anthropic")
    }

    @Test("FR-057: removing a provider deletes its key and reselects")
    func removeDeletesKeyAndReselects() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        try store.add(providerID: "openai", displayName: "OpenAI", key: "sk-openai")
        try store.add(providerID: "anthropic", displayName: "Anthropic", key: "sk-anthropic")
        defer { for p in store.providers { try? store.remove(p) } }

        #expect(try store.key(for: "openai") == "sk-openai")
        try store.remove(store.providers.first { $0.id == "openai" }!)

        #expect(try store.key(for: "openai") == nil)
        // Selection had pointed at openai; it should promote to the remaining provider.
        #expect(store.selectedModel?.providerID == "anthropic")
    }

    @Test("FR-057: removing the last provider clears the selection")
    func removingLastClearsSelection() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        try store.add(providerID: "openai", displayName: "OpenAI", key: "k")
        try store.remove(store.providers[0])
        #expect(store.selectedModel == nil)
        #expect(!store.hasProviders)
    }

    @Test("FR-050: re-adding a provider replaces rather than duplicates, and updates the key")
    func addReplaces() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        try store.add(providerID: "openai", displayName: "OpenAI", key: "k1")
        try store.add(providerID: "openai", displayName: "OpenAI", key: "k2")
        defer { try? store.remove(store.providers[0]) }

        #expect(store.providers.count == 1)
        #expect(try store.key(for: "openai") == "k2")
    }
}
