import Foundation
import SwiftData
import Testing
@testable import HomebrewCatalog

/// The store shape every build before SchemaV1 wrote: an unversioned `Schema` of these
/// four models, and no `ActionRecord.mutationPayload`.
private enum PreVersioningModels {
    @Model
    final class FavoriteItem {
        @Attribute(.unique) var id: String
        var name: String
        var itemTypeRaw: String
        var dateAdded: Date

        init(id: String, name: String) {
            self.id = id
            self.name = name
            self.itemTypeRaw = "Formula"
            self.dateAdded = Date(timeIntervalSince1970: 1_700_000_000)
        }
    }

    @Model
    final class HistoryItem {
        @Attribute(.unique) var id: String
        var name: String
        var itemTypeRaw: String
        var lastViewed: Date
        var viewCount: Int

        init(id: String, name: String) {
            self.id = id
            self.name = name
            self.itemTypeRaw = "Formula"
            self.lastViewed = Date(timeIntervalSince1970: 1_700_000_000)
            self.viewCount = 3
        }
    }

    @Model
    final class ActionRecord {
        @Attribute(.unique) var id: String
        var command: String
        var arguments: String
        var packageName: String
        var packageTypeRaw: String
        var statusRaw: String
        var output: String
        var errorOutput: String
        var startedAt: Date
        var completedAt: Date?
        var exitCode: Int32
        var isRetryable: Bool

        init(id: String) {
            self.id = id
            self.command = "brew"
            self.arguments = "install --cask iterm2"
            self.packageName = "iterm2"
            self.packageTypeRaw = "Cask"
            self.statusRaw = "failed"
            self.output = ""
            self.errorOutput = "Error: Download failed"
            self.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
            self.completedAt = Date(timeIntervalSince1970: 1_700_000_042)
            self.exitCode = 1
            self.isRetryable = true
        }
    }

    @Model
    final class PackageGroup {
        @Attribute(.unique) var id: String
        var name: String
        var icon: String
        var color: String
        var packageIDs: [String]
        var dateCreated: Date

        init(id: String, name: String) {
            self.id = id
            self.name = name
            self.icon = "folder.fill"
            self.color = "blue"
            self.packageIDs = ["Formula:jq", "Cask:iterm2"]
            self.dateCreated = Date(timeIntervalSince1970: 1_700_000_000)
        }
    }
}

@Suite("SchemaV1")
@MainActor
struct SchemaV1Tests {
    // SwiftData's default for an unsandboxed app is ~/Library/Application Support/default.store,
    // which other processes use too: on 2026-09-30 Apple's icloudmailagent owned that file
    // and the app's fetches failed with "no such table: ZACTIONRECORD".
    @Test("the app keeps its own store instead of SwiftData's shared default.store")
    func storeHasItsOwnLocation() {
        let sharedDefault = ModelConfiguration(schema: Schema(versionedSchema: SchemaV1.self)).url
        let url = PersistenceController.defaultStoreURL

        #expect(url != sharedDefault)
        #expect(url.deletingLastPathComponent().lastPathComponent == "com.resulahmet.HomebrewCatalog")
    }

    // SchemaV1 is the migration baseline: it must keep describing the version-1 store even
    // after the app's current models change. A new field belongs in a new VersionedSchema.
    @Test("SchemaV1 describes exactly the version-1 store")
    func schemaV1IsFrozen() {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let attributes = Dictionary(uniqueKeysWithValues: schema.entities.map {
            ($0.name, $0.attributes.map(\.name).sorted())
        })

        #expect(attributes == [
            "ActionRecord": [
                "arguments", "command", "completedAt", "errorOutput", "exitCode", "id", "isRetryable",
                "mutationPayload", "output", "packageName", "packageTypeRaw", "startedAt", "statusRaw",
            ],
            "FavoriteItem": ["dateAdded", "id", "itemTypeRaw", "name"],
            "HistoryItem": ["id", "itemTypeRaw", "lastViewed", "name", "viewCount"],
            "PackageGroup": ["color", "dateCreated", "icon", "id", "name", "packageIDs"],
        ])
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("a fresh store round-trips every model")
    func freshStoreRoundTrips() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let writer = ModelContext(container)
        writer.insert(FavoriteItem(id: "Formula:jq", name: "jq", itemType: .formula))
        writer.insert(HistoryItem(id: "Cask:iterm2", name: "iterm2", itemType: .cask))
        writer.insert(ActionRecord(mutation: BrewMutation(.pin(name: "jq"))))
        let group = PackageGroup(name: "Dev Tools")
        group.packageIDs = ["Formula:jq"]
        writer.insert(group)
        try writer.save()

        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<FavoriteItem>()).map(\.id) == ["Formula:jq"])
        #expect(try reader.fetch(FetchDescriptor<HistoryItem>()).map(\.itemType) == [.cask])
        #expect(try reader.fetch(FetchDescriptor<ActionRecord>()).map { $0.retryMutation?.op } == [.pin(name: "jq")])
        #expect(try reader.fetch(FetchDescriptor<PackageGroup>()).map(\.packageIDs) == [["Formula:jq"]])
    }

    @Test("a store written before versioning opens and keeps its rows")
    func preVersioningStoreMigrates() throws {
        let directory = URL.uniqueTestCacheDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")

        do {
            let legacySchema = Schema([
                PreVersioningModels.FavoriteItem.self,
                PreVersioningModels.HistoryItem.self,
                PreVersioningModels.ActionRecord.self,
                PreVersioningModels.PackageGroup.self,
            ])
            let legacy = try ModelContainer(
                for: legacySchema, configurations: [ModelConfiguration(schema: legacySchema, url: storeURL)])
            let context = ModelContext(legacy)
            context.insert(PreVersioningModels.FavoriteItem(id: "Formula:jq", name: "jq"))
            context.insert(PreVersioningModels.HistoryItem(id: "Formula:wget", name: "wget"))
            context.insert(PreVersioningModels.ActionRecord(id: "legacy-1"))
            context.insert(PreVersioningModels.PackageGroup(id: "group-1", name: "Dev Tools"))
            try context.save()
        }

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = ModelContext(container)

        let records = try context.fetch(FetchDescriptor<ActionRecord>())
        #expect(records.map(\.id) == ["legacy-1"])
        #expect(records.first?.mutationPayload == nil)
        #expect(records.first?.errorOutput == "Error: Download failed")
        #expect(records.first?.retryMutation?.op == .install(name: "iterm2", isCask: true))
        #expect(try context.fetch(FetchDescriptor<FavoriteItem>()).map(\.name) == ["jq"])
        #expect(try context.fetch(FetchDescriptor<HistoryItem>()).map(\.viewCount) == [3])
        #expect(try context.fetch(FetchDescriptor<PackageGroup>()).map(\.packageIDs) == [["Formula:jq", "Cask:iterm2"]])
    }
}
