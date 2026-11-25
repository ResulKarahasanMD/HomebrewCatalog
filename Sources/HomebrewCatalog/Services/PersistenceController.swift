import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    private static var _shared: PersistenceController?

    static var shared: PersistenceController {
        guard let _shared else {
            fatalError("PersistenceController.configure(container:) must be called before use")
        }
        return _shared
    }

    static func configure(container: ModelContainer) {
        _shared = PersistenceController(container: container)
    }

    /// SwiftData's default for an unsandboxed app is ~/Library/Application Support/default.store,
    /// a file any other unsandboxed process may claim too (Apple's icloudmailagent does), so
    /// the app keeps its store in its own folder.
    nonisolated static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "com.resulahmet.HomebrewCatalog", directoryHint: .isDirectory)
            .appending(path: "HomebrewCatalog.store", directoryHint: .notDirectory)
    }

    /// Opens the app's store at `defaultStoreURL`; tests pass `inMemory` or a scratch `url`.
    nonisolated static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let storeURL = url ?? defaultStoreURL
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    let container: ModelContainer

    private init(container: ModelContainer) {
        self.container = container
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - Favorites

    func addToFavorites(id: String, name: String, itemType: BrewItemType) {
        let favorite = FavoriteItem(id: id, name: name, itemType: itemType)
        context.insert(favorite)
        try? context.save()
    }

    func removeFromFavorites(id: String) {
        let descriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let item = try? context.fetch(descriptor).first {
            context.delete(item)
            try? context.save()
        }
    }

    func isFavorite(id: String) -> Bool {
        let descriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    func toggleFavorite(id: String, name: String, itemType: BrewItemType) -> Bool {
        if isFavorite(id: id) {
            removeFromFavorites(id: id)
            return false
        } else {
            addToFavorites(id: id, name: name, itemType: itemType)
            return true
        }
    }

    // MARK: - History

    func recordHistory(id: String, name: String, itemType: BrewItemType) {
        let descriptor = FetchDescriptor<HistoryItem>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.recordView()
        } else {
            let historyItem = HistoryItem(id: id, name: name, itemType: itemType)
            context.insert(historyItem)
        }
        try? context.save()
    }

    func clearHistory() {
        let descriptor = FetchDescriptor<HistoryItem>()
        if let items = try? context.fetch(descriptor) {
            for item in items {
                context.delete(item)
            }
            try? context.save()
        }
    }

    // MARK: - Action Records

    func clearActionHistory() {
        let descriptor = FetchDescriptor<ActionRecord>()
        if let items = try? context.fetch(descriptor) {
            for item in items {
                context.delete(item)
            }
            try? context.save()
        }
    }

    // MARK: - Package Groups

    func createGroup(name: String, icon: String, color: String) -> PackageGroup {
        let group = PackageGroup(name: name, icon: icon, color: color)
        context.insert(group)
        try? context.save()
        return group
    }

    func deleteGroup(_ group: PackageGroup) {
        context.delete(group)
        try? context.save()
    }

    func addToGroup(_ group: PackageGroup, packageID: String) {
        if !group.packageIDs.contains(packageID) {
            group.packageIDs.append(packageID)
            try? context.save()
        }
    }

    func removeFromGroup(_ group: PackageGroup, packageID: String) {
        group.packageIDs.removeAll { $0 == packageID }
        try? context.save()
    }
}
