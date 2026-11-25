import Foundation

enum DownloadRankBuilder: Sendable {
    struct Entry: Sendable {
        let id: String
        let name: String
        let installCount: Int
        let itemType: BrewItemType
        let isCatalogItem: Bool
    }

    static func buildFormulaEntries(
        formulas: [BrewFormula],
        installCounts: [String: Int]
    ) -> [Entry] {
        var catalogIDs = Set<String>()
        catalogIDs.reserveCapacity(formulas.count)
        var entries: [Entry] = []
        entries.reserveCapacity(formulas.count + installCounts.count)

        for formula in formulas {
            catalogIDs.insert(formula.id)
            entries.append(
                Entry(
                    id: formula.id,
                    name: formula.name,
                    installCount: installCounts[formula.name] ?? 0,
                    itemType: .formula,
                    isCatalogItem: true
                )
            )
        }

        for (name, count) in installCounts where !catalogIDs.contains(name) {
            entries.append(
                Entry(
                    id: name,
                    name: name,
                    installCount: count,
                    itemType: .formula,
                    isCatalogItem: false
                )
            )
        }

        return entries
    }

    static func buildCaskEntries(
        casks: [BrewCask],
        installCounts: [String: Int]
    ) -> [Entry] {
        var catalogIDs = Set<String>()
        catalogIDs.reserveCapacity(casks.count)
        var entries: [Entry] = []
        entries.reserveCapacity(casks.count + installCounts.count)

        for cask in casks {
            catalogIDs.insert(cask.id)
            entries.append(
                Entry(
                    id: cask.id,
                    name: cask.name,
                    installCount: installCount(for: cask, in: installCounts),
                    itemType: .cask,
                    isCatalogItem: true
                )
            )
        }

        for (token, count) in installCounts where !catalogIDs.contains(token) {
            entries.append(
                Entry(
                    id: token,
                    name: token,
                    installCount: count,
                    itemType: .cask,
                    isCatalogItem: false
                )
            )
        }

        return entries
    }

    static func rankedRows(from entries: [Entry]) -> [DownloadRankRow] {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.installCount != rhs.installCount {
                return lhs.installCount > rhs.installCount
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return sorted.enumerated().map { index, entry in
            DownloadRankRow(
                packageID: entry.id,
                rank: index + 1,
                name: entry.name,
                installCount: entry.installCount,
                itemType: entry.itemType,
                isCatalogItem: entry.isCatalogItem
            )
        }
    }

    static func combinedRankedRows(
        formulaRows: [DownloadRankRow],
        caskRows: [DownloadRankRow]
    ) -> [DownloadRankRow] {
        let merged = (formulaRows + caskRows).map { row in
            Entry(
                id: row.packageID,
                name: row.name,
                installCount: row.installCount,
                itemType: row.itemType,
                isCatalogItem: row.isCatalogItem
            )
        }
        return rankedRows(from: merged)
    }

    private static func installCount(for cask: BrewCask, in installCounts: [String: Int]) -> Int {
        if let count = installCounts[cask.token] {
            return count
        }
        if let names = cask.names {
            for alias in names where installCounts[alias] != nil {
                return installCounts[alias]!
            }
        }
        return installCounts[cask.name] ?? 0
    }
}
