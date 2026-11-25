import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("CatalogCache")
struct CatalogCacheTests {
    @Test("loadCatalogSnapshot returns nil when cache is stale")
    func staleSnapshotReturnsNil() async throws {
        let cache = CatalogCache.isolated()

        let formulae = try decodeFormulae(from: #"[{"name":"jq","tap":"homebrew/core"}]"#)
        let metadata = CatalogMetadata(
            lastUpdated: Date().addingTimeInterval(-86_400 * 2),
            formulaCount: formulae.count,
            caskCount: 0,
            appVersion: CatalogCache.schemaVersion
        )
        try await cache.saveCatalog(formulae: formulae, casks: [], metadata: metadata)

        let snapshot = try await cache.loadCatalogSnapshot(maxAge: 86_400)
        #expect(snapshot == nil)
    }

    @Test("loadCatalogSnapshot returns data when cache is fresh")
    func freshSnapshotLoads() async throws {
        let cache = CatalogCache.isolated()

        let now = Date()
        let formulae = try decodeFormulae(from: #"[{"name":"jq","tap":"homebrew/core"}]"#)
        let casks = try decodeCasks(
            from: #"[{"token":"iterm2","name":["iTerm2"],"tap":"homebrew/cask"}]"#)
        let metadata = CatalogMetadata(
            lastUpdated: now,
            formulaCount: formulae.count,
            caskCount: casks.count,
            appVersion: CatalogCache.schemaVersion
        )
        try await cache.saveCatalog(formulae: formulae, casks: casks, metadata: metadata)

        let snapshot = try await cache.loadCatalogSnapshot(maxAge: 86_400)
        #expect(snapshot?.formulas.count == 1)
        #expect(snapshot?.casks.count == 1)
        #expect(snapshot?.metadata.formulaCount == 1)
    }

    private func decodeFormulae(from json: String) throws -> [BrewFormula] {
        try JSONDecoder().decode([BrewFormula].self, from: Data(json.utf8))
    }

    private func decodeCasks(from json: String) throws -> [BrewCask] {
        try JSONDecoder().decode([BrewCask].self, from: Data(json.utf8))
    }
}
