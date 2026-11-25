import Foundation

struct DownloadRankRow: Identifiable, Sendable, Hashable {
    /// Formula name or cask token, as used for lookups and `brew` commands.
    let packageID: String
    let rank: Int
    let name: String
    let installCount: Int
    let itemType: BrewItemType
    let isCatalogItem: Bool
}

enum DownloadRankFilter: String, CaseIterable, Sendable {
    case all = "All"
    case formulae = "Formulae"
    case casks = "Casks"
}

extension DownloadRankRow {
    /// Unique across the combined formula + cask ranking, where bare ids can repeat.
    var id: String { itemType.qualifiedID(packageID) }
}
