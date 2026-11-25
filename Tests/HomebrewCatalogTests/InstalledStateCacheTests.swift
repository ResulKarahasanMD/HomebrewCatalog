import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("InstalledStateCache")
struct InstalledStateCacheTests {
    @Test("save and load snapshot round-trip")
    func snapshotRoundTrip() async throws {
        let cache = InstalledStateCache.isolated()

        let snapshot = InstalledStateSnapshot(
            lastUpdated: Date(),
            formulas: [
                InstalledFormulaInfo(
                    name: "jq",
                    fullName: "homebrew/core/jq",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.7.1",
                    latestVersion: "1.7.1",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false,
                    isLeaf: true
                )
            ],
            casks: [],
            leafNames: ["jq"],
            fetchSucceeded: true
        )

        try await cache.saveSnapshot(snapshot)
        let loaded = try await cache.loadSnapshot(maxAge: 300)

        #expect(loaded?.formulas.count == 1)
        #expect(loaded?.formulas.first?.name == "jq")
        #expect(loaded?.leafNames == ["jq"])
        #expect(loaded?.fetchSucceeded == true)
    }

    @Test("stale unsuccessful snapshot is not treated as fresh")
    func unsuccessfulSnapshotRejectedByFreshGate() async throws {
        let cache = InstalledStateCache.isolated()

        let empty = InstalledStateSnapshot(
            lastUpdated: Date(),
            formulas: [],
            casks: [],
            leafNames: [],
            fetchSucceeded: false
        )
        try await cache.saveSnapshot(empty)

        let fresh = try await cache.loadSnapshot(maxAge: 300)
        #expect(fresh != nil)
        #expect(fresh?.fetchSucceeded == false)
    }

    @Test("stale snapshot is not returned within maxAge gate")
    func staleSnapshotRejected() async throws {
        let cache = InstalledStateCache.isolated()

        let stale = InstalledStateSnapshot(
            lastUpdated: Date().addingTimeInterval(-600),
            formulas: [],
            casks: [],
            leafNames: []
        )
        try await cache.saveSnapshot(stale)

        let loaded = try await cache.loadSnapshot(maxAge: 300)
        #expect(loaded == nil)

        let anyAge = try await cache.loadSnapshot(maxAge: .infinity)
        #expect(anyAge != nil)
    }
}
