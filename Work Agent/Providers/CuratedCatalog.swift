//
//  CuratedCatalog.swift
//  Work Agent
//
//  The curated set: which providers and models the app offers. Nothing else appears.
//

import Foundation

// REQ: FR-061 — the system offers only an explicit curated set of models.
// REQ: FR-062 — first-party providers only; no resellers or aggregators.
//
// This is a hand-maintained allowlist on purpose. models.dev has no "quality" or
// "agentic" field, so "the best models" is our editorial judgement, not a filter the
// registry can express. The registry still supplies the metadata (names, context,
// pricing, reasoning flag) for these ids — see docs/decisions/0005 and
// docs/research/llm-provider-registries.md.
//
// Model ids verified against a live models.dev/api.json on 2026-07-16; all first-party,
// all tool-capable. Toni's list, verbatim.
enum CuratedCatalog {
    /// Provider id (models.dev) → the model ids we offer for it, in display order.
    static let models: [String: [String]] = [
        "openai": ["gpt-5.6", "gpt-5.6-sol", "gpt-5.6-luna", "gpt-5.6-terra"],
        "anthropic": ["claude-opus-4-8", "claude-sonnet-5", "claude-fable-5"],
        "google": ["gemini-3.5-flash"],
        "xai": ["grok-4.5"],
        "moonshotai": ["kimi-k3"],
        "zai": ["glm-5.2"],
        "meta": ["muse-spark-1.1"],
        "deepseek": ["deepseek-v4-pro"],
        "minimax": ["MiniMax-M3"],
        "thinkingmachines": ["inkling"],
        "alibaba": ["qwen3.7-max"],
    ]

    /// Provider ids in a stable display order (most-used first).
    static let providerOrder = [
        "openai", "anthropic", "google", "xai", "moonshotai",
        "zai", "meta", "deepseek", "minimax", "thinkingmachines", "alibaba",
    ]

    static var providerIDs: [String] { providerOrder }

    static func isCurated(providerID: String) -> Bool {
        models[providerID] != nil
    }

    static func isCurated(providerID: String, modelID: String) -> Bool {
        models[providerID]?.contains(modelID) ?? false
    }

    static func modelIDs(for providerID: String) -> [String] {
        models[providerID] ?? []
    }
}

// MARK: - Resolving the curated set against live registry metadata

extension ModelRegistry {
    /// Curated providers present in the registry, in curated display order.
    func curatedProviders() -> [RegistryProvider] {
        CuratedCatalog.providerOrder.compactMap { provider(id: $0) }
    }

    /// The curated models for a provider, resolved to registry metadata, in curated order.
    /// Model ids not found in the registry are dropped rather than shown broken.
    func curatedModels(for providerID: String) -> [RegistryModel] {
        guard let provider = provider(id: providerID) else { return [] }
        let byID = Dictionary(provider.models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return CuratedCatalog.modelIDs(for: providerID).compactMap { byID[$0] }
    }
}
