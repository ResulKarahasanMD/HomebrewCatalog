import Foundation
import SwiftData

actor CatalogCache {
    static let shared = CatalogCache()
    
    static let defaultDirectory = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("HomebrewCatalog", isDirectory: true)

    private nonisolated let cacheDirectory: URL
    
    private let formulasFile = "formulas.json"
    private let casksFile = "casks.json"
    private let metadataFile = "metadata.plist"

    private func formulaAnalyticsFile(period: HomebrewAPIService.AnalyticsPeriod) -> String {
        "formula-analytics-\(period.rawValue).json"
    }

    private func caskAnalyticsFile(period: HomebrewAPIService.AnalyticsPeriod) -> String {
        "cask-analytics-v2-\(period.rawValue).json"
    }

    private func legacyCaskAnalyticsFile(period: HomebrewAPIService.AnalyticsPeriod) -> String {
        "cask-analytics-\(period.rawValue).json"
    }

    private let analyticsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let analyticsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    
    /// Tests pass a temporary directory so they never touch the user's real cache.
    init(directory: URL = defaultDirectory) {
        cacheDirectory = directory
    }
    
    // MARK: - File Persistence
    
    func saveFormulas(_ formulas: [BrewFormula]) async throws {
        try ensureCacheDirectoryExists()
        let url = cacheDirectory.appendingPathComponent(formulasFile)
        let data = try JSONEncoder().encode(formulas)
        try data.write(to: url, options: .atomic)
    }
    
    func saveCasks(_ casks: [BrewCask]) async throws {
        try ensureCacheDirectoryExists()
        let url = cacheDirectory.appendingPathComponent(casksFile)
        let data = try JSONEncoder().encode(casks)
        try data.write(to: url, options: .atomic)
    }
    
    func loadFormulas() async throws -> [BrewFormula] {
        let url = cacheDirectory.appendingPathComponent(formulasFile)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([BrewFormula].self, from: data)
    }
    
    func loadCasks() async throws -> [BrewCask] {
        let url = cacheDirectory.appendingPathComponent(casksFile)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([BrewCask].self, from: data)
    }
    
    // MARK: - Metadata
    
    func saveMetadata(_ metadata: CatalogMetadata) async throws {
        try ensureCacheDirectoryExists()
        let url = cacheDirectory.appendingPathComponent(metadataFile)
        let data = try PropertyListEncoder().encode(metadata)
        try data.write(to: url, options: .atomic)
    }
    
    private func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func loadMetadata() async throws -> CatalogMetadata? {
        let url = cacheDirectory.appendingPathComponent(metadataFile)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try PropertyListDecoder().decode(CatalogMetadata.self, from: data)
    }
    
    // MARK: - Cache Management
    
    func clearCache() async throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in contents {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    /// Bump when the decoded model shape changes so stale caches are refetched
    /// instead of being loaded with missing fields.
    static let schemaVersion = "2"

    func isCacheValid(maxAge: TimeInterval = 86400) async -> Bool {
        guard let metadata = try? await loadMetadata() else { return false }
        guard metadata.appVersion == Self.schemaVersion else { return false }
        return Date().timeIntervalSince(metadata.lastUpdated) < maxAge
    }

    /// Loads catalog from disk when metadata is within `maxAge`; returns `nil` if missing or stale.
    func loadCatalogSnapshot(maxAge: TimeInterval) async throws -> CatalogSnapshot? {
        guard let metadata = try await loadMetadata() else { return nil }
        guard metadata.appVersion == Self.schemaVersion else { return nil }
        guard Date().timeIntervalSince(metadata.lastUpdated) < maxAge else { return nil }

        async let formulasTask = loadFormulas()
        async let casksTask = loadCasks()
        let (formulas, casks) = try await (formulasTask, casksTask)
        return CatalogSnapshot(formulas: formulas, casks: casks, metadata: metadata)
    }

    func saveCatalog(
        formulae: [BrewFormula],
        casks: [BrewCask],
        metadata: CatalogMetadata
    ) async throws {
        async let formulasSave = saveFormulas(formulae)
        async let casksSave = saveCasks(casks)
        try await formulasSave
        try await casksSave
        try await saveMetadata(metadata)
    }

    // MARK: - Analytics Persistence

    func saveAnalytics(_ bundle: AnalyticsBundle) async throws {
        try ensureCacheDirectoryExists()
        let formulaURL = cacheDirectory.appendingPathComponent(formulaAnalyticsFile(period: bundle.period))
        let caskURL = cacheDirectory.appendingPathComponent(caskAnalyticsFile(period: bundle.period))
        try analyticsEncoder.encode(bundle.formula).write(to: formulaURL, options: .atomic)
        try analyticsEncoder.encode(bundle.cask).write(to: caskURL, options: .atomic)
    }

    func loadAnalytics(
        period: HomebrewAPIService.AnalyticsPeriod,
        maxAge: TimeInterval
    ) async throws -> AnalyticsBundle? {
        guard let metadata = try await loadMetadata() else { return nil }
        guard Date().timeIntervalSince(metadata.lastUpdated) < maxAge else { return nil }

        let formulaURL = cacheDirectory.appendingPathComponent(formulaAnalyticsFile(period: period))
        let caskURL = cacheDirectory.appendingPathComponent(caskAnalyticsFile(period: period))
        guard FileManager.default.fileExists(atPath: formulaURL.path),
              FileManager.default.fileExists(atPath: caskURL.path)
        else { return nil }

        do {
            let formulaData = try Data(contentsOf: formulaURL)
            let caskData = try Data(contentsOf: caskURL)
            let formula = try analyticsDecoder.decode(AnalyticsResponse.self, from: formulaData)
            let cask = try analyticsDecoder.decode(CaskAnalyticsResponse.self, from: caskData)
            return AnalyticsBundle(formula: formula, cask: cask, period: period)
        } catch {
            try? FileManager.default.removeItem(at: formulaURL)
            try? FileManager.default.removeItem(at: caskURL)
            let legacyCaskURL = cacheDirectory.appendingPathComponent(
                legacyCaskAnalyticsFile(period: period)
            )
            try? FileManager.default.removeItem(at: legacyCaskURL)
            throw error
        }
    }
    
    nonisolated var cacheSize: UInt64 {
        let contents = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return contents.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + UInt64(size)
        }
    }
}

struct CatalogMetadata: Codable, Sendable {
    var lastUpdated: Date
    var formulaCount: Int
    var caskCount: Int
    var appVersion: String
    /// ETags of the stored formula.json / cask.json, sent back as If-None-Match.
    var formulaETag: String? = nil
    var caskETag: String? = nil
}

struct CatalogSnapshot: Sendable {
    let formulas: [BrewFormula]
    let casks: [BrewCask]
    let metadata: CatalogMetadata
}
