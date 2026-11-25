import Foundation
import SwiftData

typealias PackageGroup = SchemaV1.PackageGroup

extension SchemaV1 {
    /// Stored shape of a package group in version 1. Frozen: a new field belongs in a new schema version.
    @Model
    final class PackageGroup {
        @Attribute(.unique) var id: String
        var name: String
        var icon: String
        var color: String
        var packageIDs: [String]
        var dateCreated: Date

        init(name: String, icon: String = "folder.fill", color: String = "blue") {
            self.id = UUID().uuidString
            self.name = name
            self.icon = icon
            self.color = color
            self.packageIDs = []
            self.dateCreated = Date()
        }
    }
}
