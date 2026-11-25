import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("DownloadRankBuilder")
struct DownloadRankBuilderTests {
    @Test("formula union includes analytics-only names")
    func formulaUnion() {
        let formulas = [
            BrewFormula(analyticsStubName: "wget"),
        ]
        let counts = ["wget": 100, "legacy-formula": 50]
        let entries = DownloadRankBuilder.buildFormulaEntries(
            formulas: formulas,
            installCounts: counts
        )
        let names = Set(entries.map(\.name))
        #expect(names.contains("wget"))
        #expect(names.contains("legacy-formula"))
        #expect(entries.first(where: { $0.name == "legacy-formula" })?.isCatalogItem == false)
    }

    @Test("ranked rows sort by install count descending")
    func rankedSort() {
        let entries = [
            DownloadRankBuilder.Entry(
                id: "a", name: "a", installCount: 0, itemType: .formula, isCatalogItem: true),
            DownloadRankBuilder.Entry(
                id: "b", name: "b", installCount: 500, itemType: .formula, isCatalogItem: true),
            DownloadRankBuilder.Entry(
                id: "c", name: "c", installCount: 10_000, itemType: .formula, isCatalogItem: true),
        ]
        let rows = DownloadRankBuilder.rankedRows(from: entries)
        #expect(rows.map(\.name) == ["c", "b", "a"])
        #expect(rows.map(\.rank) == [1, 2, 3])
    }

    @Test("combined ranking merges formulae and casks globally")
    func combinedRanking() {
        let formulaRows = [
            DownloadRankRow(
                packageID: "f1", rank: 1, name: "f1", installCount: 100, itemType: .formula,
                isCatalogItem: true),
        ]
        let caskRows = [
            DownloadRankRow(
                packageID: "c1", rank: 1, name: "c1", installCount: 200, itemType: .cask,
                isCatalogItem: true),
        ]
        let combined = DownloadRankBuilder.combinedRankedRows(
            formulaRows: formulaRows,
            caskRows: caskRows
        )
        #expect(combined.count == 2)
        #expect(combined[0].name == "c1")
        #expect(combined[0].rank == 1)
        #expect(combined[1].name == "f1")
        #expect(combined[1].rank == 2)
    }

    @Test("combined ranking keeps a formula and a cask with the same id distinct")
    func combinedRankingSharedID() {
        let formulaRows = [
            DownloadRankRow(
                packageID: "mpv", rank: 1, name: "mpv", installCount: 100, itemType: .formula,
                isCatalogItem: true),
        ]
        let caskRows = [
            DownloadRankRow(
                packageID: "mpv", rank: 1, name: "mpv", installCount: 50, itemType: .cask,
                isCatalogItem: true),
        ]
        let combined = DownloadRankBuilder.combinedRankedRows(
            formulaRows: formulaRows, caskRows: caskRows)
        #expect(Set(combined.map(\.id)).count == 2)
        #expect(combined.map(\.packageID) == ["mpv", "mpv"])
        #expect(combined.map(\.id) == ["Formula:mpv", "Cask:mpv"])
    }
}
