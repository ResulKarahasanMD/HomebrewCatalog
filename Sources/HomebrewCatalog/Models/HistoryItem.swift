import Foundation
import SwiftData

typealias HistoryItem = SchemaV1.HistoryItem

extension SchemaV1 {
    /// Stored shape of a visited item in version 1. Frozen: a new field belongs in a new schema version.
    @Model
    final class HistoryItem {
        @Attribute(.unique) var id: String
        var name: String
        var itemTypeRaw: String
        var lastViewed: Date
        var viewCount: Int

        init(id: String, name: String, itemType: BrewItemType) {
            self.id = id
            self.name = name
            self.itemTypeRaw = itemType.rawValue
            self.lastViewed = Date()
            self.viewCount = 1
        }
    }
}

extension HistoryItem {
    var itemType: BrewItemType {
        BrewItemType(rawValue: itemTypeRaw) ?? .formula
    }

    func recordView() {
        lastViewed = Date()
        viewCount += 1
    }
}
