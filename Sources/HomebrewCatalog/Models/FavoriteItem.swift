import Foundation
import SwiftData

typealias FavoriteItem = SchemaV1.FavoriteItem

extension SchemaV1 {
    /// Stored shape of a favorite in version 1. Frozen: a new field belongs in a new schema version.
    @Model
    final class FavoriteItem {
        @Attribute(.unique) var id: String
        var name: String
        var itemTypeRaw: String
        var dateAdded: Date

        init(id: String, name: String, itemType: BrewItemType) {
            self.id = id
            self.name = name
            self.itemTypeRaw = itemType.rawValue
            self.dateAdded = Date()
        }
    }
}

extension FavoriteItem {
    var itemType: BrewItemType {
        BrewItemType(rawValue: itemTypeRaw) ?? .formula
    }
}
