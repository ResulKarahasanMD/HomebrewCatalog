import Foundation
@testable import HomebrewCatalog

// Swift Testing runs tests in parallel, and the `.shared` caches write to the user's
// real ~/Library/Caches/HomebrewCatalog. Every test gets its own directory instead.

extension URL {
    static func uniqueTestCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HomebrewCatalogTests-\(UUID().uuidString)", isDirectory: true)
    }
}

extension CatalogCache {
    static func isolated() -> CatalogCache {
        CatalogCache(directory: .uniqueTestCacheDirectory())
    }
}

extension InstalledStateCache {
    static func isolated() -> InstalledStateCache {
        InstalledStateCache(directory: .uniqueTestCacheDirectory())
    }
}
