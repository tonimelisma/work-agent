//
//  ModelRegistryTests.swift
//  Work AgentTests
//

import Foundation
import Testing
@testable import Work_Agent

private func decode(_ json: String) throws -> ModelRegistry {
    try JSONDecoder().decode(ModelRegistry.self, from: Data(json.utf8))
}

@Suite("Model registry decoding")
struct ModelRegistryTests {

    @Test("NFR-007: a provider that fails to decode is skipped, not fatal")
    func malformedProviderIsSkipped() throws {
        // Second provider has no `id`, which is the one field we require.
        let registry = try decode("""
        {
          "openai": {"id": "openai", "name": "OpenAI", "env": ["OPENAI_API_KEY"],
                     "models": {"gpt-5": {"id": "gpt-5", "name": "GPT-5", "tool_call": true}}},
          "broken": {"name": "Broken", "env": []},
          "anthropic": {"id": "anthropic", "name": "Anthropic", "env": ["ANTHROPIC_API_KEY"],
                        "models": {"claude": {"id": "claude", "name": "Claude", "tool_call": true}}}
        }
        """)

        #expect(registry.providers.count == 2)
        #expect(registry.provider(id: "broken") == nil)
        #expect(registry.provider(id: "openai") != nil)
        #expect(registry.provider(id: "anthropic") != nil)
    }

    @Test("NFR-007: a malformed model is skipped without losing its provider")
    func malformedModelIsSkipped() throws {
        let registry = try decode("""
        {
          "openai": {"id": "openai", "name": "OpenAI", "env": [],
            "models": {
              "good": {"id": "good", "name": "Good", "tool_call": true},
              "bad": {"name": "No id here"}
            }}
        }
        """)

        let provider = try #require(registry.provider(id: "openai"))
        #expect(provider.models.count == 1)
        #expect(provider.models.first?.id == "good")
    }

    @Test("NFR-007: unknown fields are ignored")
    func unknownFieldsIgnored() throws {
        // models.dev has no schema version. New fields must not break us.
        let registry = try decode("""
        {
          "openai": {"id": "openai", "name": "OpenAI", "env": [], "npm": "@ai-sdk/openai",
                     "some_future_field": {"nested": [1, 2, 3]},
            "models": {"gpt-5": {"id": "gpt-5", "name": "GPT-5", "tool_call": true,
                                 "another_new_thing": "surprise"}}}
        }
        """)

        #expect(registry.provider(id: "openai")?.models.count == 1)
    }

    @Test("FR-061: tool-capable models are separable from the rest")
    func toolCapableFiltering() throws {
        let registry = try decode("""
        {
          "openai": {"id": "openai", "name": "OpenAI", "env": [],
            "models": {
              "agentic": {"id": "agentic", "name": "Agentic", "tool_call": true},
              "chatty": {"id": "chatty", "name": "Chatty", "tool_call": false},
              "silent": {"id": "silent", "name": "Silent"}
            }}
        }
        """)

        let provider = try #require(registry.provider(id: "openai"))
        #expect(provider.models.count == 3)
        #expect(provider.toolCapableModels.map(\.id) == ["agentic"])
    }

    @Test("FR-061: a model omitting tool_call is treated as not tool-capable")
    func missingToolCallDefaultsFalse() throws {
        // A false positive strands the user mid-agent-run; a false negative just hides
        // a model. Default to the recoverable failure.
        let registry = try decode("""
        {"p": {"id": "p", "name": "P", "env": [], "models": {"m": {"id": "m", "name": "M"}}}}
        """)

        #expect(registry.provider(id: "p")?.models.first?.toolCall == false)
    }

    @Test("Model metadata decodes: limits, cost, reasoning")
    func modelMetadata() throws {
        let registry = try decode("""
        {
          "anthropic": {"id": "anthropic", "name": "Anthropic", "env": [],
            "models": {"claude-opus-4-5": {
              "id": "claude-opus-4-5", "name": "Claude Opus 4.5", "family": "claude-opus",
              "tool_call": true, "reasoning": true, "attachment": true,
              "release_date": "2025-11-24",
              "limit": {"context": 200000, "output": 64000},
              "cost": {"input": 5, "output": 25, "cache_read": 0.5}
            }}}
        }
        """)

        let model = try #require(registry.provider(id: "anthropic")?.models.first)
        #expect(model.contextLimit == 200_000)
        #expect(model.outputLimit == 64_000)
        #expect(model.inputCostPerMTok == 5)
        #expect(model.outputCostPerMTok == 25)
        #expect(model.reasoning)
        #expect(model.family == "claude-opus")
    }

    @Test("FR-051: usable providers exclude those we cannot reach")
    func usableProvidersRequireABaseURL() throws {
        let registry = try decode("""
        {
          "anthropic": {"id": "anthropic", "name": "Anthropic", "env": [],
                        "models": {"m": {"id": "m", "name": "M", "tool_call": true}}},
          "hosted": {"id": "hosted", "name": "Hosted", "env": [], "api": "https://api.hosted.example/v1",
                     "models": {"m": {"id": "m", "name": "M", "tool_call": true}}},
          "unreachable": {"id": "unreachable", "name": "Unreachable", "env": [],
                          "models": {"m": {"id": "m", "name": "M", "tool_call": true}}},
          "nourl-notools": {"id": "nourl-notools", "name": "Neither", "env": [],
                            "models": {"m": {"id": "m", "name": "M", "tool_call": false}}}
        }
        """)

        let usable = registry.usableProviders.map(\.id).sorted()
        // anthropic has no `api` but we supply its base URL; unreachable has neither.
        #expect(usable == ["anthropic", "hosted"])
    }

    @Test("Empty registry decodes to empty rather than throwing")
    func emptyRegistry() throws {
        #expect(try decode("{}").providers.isEmpty)
    }
}

@Suite("Bundled registry snapshot")
struct BundledSnapshotTests {

    /// The snapshot is a build input; if it's missing or unparseable the app silently
    /// has no providers, which is the failure this catches.
    @Test("FR-054: the bundled snapshot exists, parses, and carries real providers")
    func bundledSnapshotIsUsable() async throws {
        let url = try #require(
            Bundle(for: BundleMarker.self).url(forResource: "models-dev-snapshot", withExtension: "json")
                ?? Bundle.main.url(forResource: "models-dev-snapshot", withExtension: "json"),
            "Bundled models.dev snapshot is missing from the app bundle"
        )

        let data = try Data(contentsOf: url)
        let registry = try JSONDecoder().decode(ModelRegistry.self, from: data)

        #expect(registry.providers.count > 100)
        #expect(!registry.usableProviders.isEmpty)

        // anthropic and openai are the two vendors with native adapters (ADR-0007);
        // every other curated provider routes through the OpenAI-compatible one.
        let anthropic = try #require(registry.provider(id: "anthropic"))
        let openai = try #require(registry.provider(id: "openai"))
        #expect(!anthropic.toolCapableModels.isEmpty)
        #expect(!openai.toolCapableModels.isEmpty)
    }

    /// Guards the finding in docs/research/llm-provider-registries.md. If models.dev ever
    /// starts publishing base URLs for the majors, this fails and tells us the hardcoded
    /// fallbacks in ProviderCatalog can go.
    @Test("ADR-0005: the majors still ship no base URL, so our fallbacks are still needed")
    func majorsStillLackBaseURLs() throws {
        let url = try #require(
            Bundle(for: BundleMarker.self).url(forResource: "models-dev-snapshot", withExtension: "json")
                ?? Bundle.main.url(forResource: "models-dev-snapshot", withExtension: "json")
        )
        let registry = try JSONDecoder().decode(ModelRegistry.self, from: try Data(contentsOf: url))

        for id in ["anthropic", "openai", "google"] {
            let provider = try #require(registry.provider(id: id))
            #expect(provider.api == nil, "\(id) now publishes a base URL — ProviderCatalog can drop its fallback")
            #expect(ProviderCatalog.baseURL(for: provider) != nil, "\(id) has no reachable base URL")
        }
    }
}

/// Anchor for locating the test bundle's resources.
private final class BundleMarker {}
