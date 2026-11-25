import Foundation

struct InstalledStateSnapshot: Codable, Sendable {
    var lastUpdated: Date
    var formulas: [InstalledFormulaInfo]
    var casks: [InstalledCaskInfo]
    var leafNames: [String]
    /// True when at least one brew listing succeeded during the last refresh.
    var fetchSucceeded: Bool

    init(
        lastUpdated: Date,
        formulas: [InstalledFormulaInfo],
        casks: [InstalledCaskInfo],
        leafNames: [String],
        fetchSucceeded: Bool = false
    ) {
        self.lastUpdated = lastUpdated
        self.formulas = formulas
        self.casks = casks
        self.leafNames = leafNames
        self.fetchSucceeded = fetchSucceeded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        formulas = try container.decode([InstalledFormulaInfo].self, forKey: .formulas)
        casks = try container.decode([InstalledCaskInfo].self, forKey: .casks)
        leafNames = try container.decode([String].self, forKey: .leafNames)
        fetchSucceeded = try container.decodeIfPresent(Bool.self, forKey: .fetchSucceeded) ?? false
    }
}

actor InstalledStateCache {
    static let shared = InstalledStateCache()

    static let defaultMaxAge: TimeInterval = 300

    static let defaultDirectory = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("HomebrewCatalog", isDirectory: true)

    private nonisolated let cacheDirectory: URL

    private let snapshotFile = "installed-snapshot.json"

    /// Tests pass a temporary directory so they never touch the user's real cache.
    init(directory: URL = defaultDirectory) {
        cacheDirectory = directory
    }

    func loadSnapshot(maxAge: TimeInterval = .infinity) async throws -> InstalledStateSnapshot? {
        let url = cacheDirectory.appendingPathComponent(snapshotFile)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(InstalledStateSnapshot.self, from: data)

        if !maxAge.isInfinite,
            Date().timeIntervalSince(snapshot.lastUpdated) >= maxAge
        {
            return nil
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: InstalledStateSnapshot) async throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let url = cacheDirectory.appendingPathComponent(snapshotFile)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    func clear() async throws {
        let url = cacheDirectory.appendingPathComponent(snapshotFile)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
