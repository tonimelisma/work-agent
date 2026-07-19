//
//  CuratedCatalogTests.swift
//  Work AgentTests
//
//  Split out of the old ChatAdapterTests.swift when increment 4 replaced the
//  app-level ChatProvider streaming adapters with AgentKit's Executors — their
//  SSE-parsing coverage now lives in AgentKit/Tests/ExecutorsTests. This suite
//  outlived that split because CuratedCatalog is unrelated to how a reply streams.
//

import Foundation
import Testing
@testable import Work_Agent

@Suite("Curated catalog")
struct CuratedCatalogTests {

    @Test("FR-061/FR-062: the curated set is 11 first-party providers")
    func curatedShape() {
        #expect(CuratedCatalog.providerOrder.count == 11)
        #expect(CuratedCatalog.isCurated(providerID: "openai", modelID: "gpt-5.6"))
        #expect(!CuratedCatalog.isCurated(providerID: "openai", modelID: "gpt-3.5"))
        #expect(!CuratedCatalog.isCurated(providerID: "openrouter"))  // a reseller
    }

    @Test("FR-061: curated models resolve against the bundled snapshot")
    func resolvesAgainstSnapshot() throws {
        let url = try #require(Bundle(for: SnapshotAnchor.self).url(forResource: "models-dev-snapshot", withExtension: "json")
            ?? Bundle.main.url(forResource: "models-dev-snapshot", withExtension: "json"))
        let registry = try JSONDecoder().decode(ModelRegistry.self, from: try Data(contentsOf: url))

        // Every curated provider resolves to at least its first model.
        for id in CuratedCatalog.providerOrder {
            let models = registry.curatedModels(for: id)
            #expect(!models.isEmpty, "curated provider \(id) resolved no models")
        }
        #expect(registry.curatedProviders().count == 11)
    }
}

private final class SnapshotAnchor {}
