import Foundation

actor HomebrewAPIService {
    static let shared = HomebrewAPIService()
    
    private let session: URLSession
    private let baseURL = "https://formulae.brew.sh/api"
    
    // BrewFormula/BrewCask declare explicit snake_case CodingKeys, so they must be
    // decoded WITHOUT .convertFromSnakeCase (the strategy would rewrite "full_name"
    // to "fullName" and every multi-word field would silently decode as nil).
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Analytics DTOs use camelCase properties with no CodingKeys and rely on the strategy.
    private let analyticsDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    private init() {
        let config = NetworkSessionConfiguration.apiClient(
            requestTimeout: 120,
            resourceTimeout: 300,
            waitsForConnectivity: true
        )
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Endpoints
    
    func fetchAllFormulae() async throws -> [BrewFormula] {
        let url = URL(string: "\(baseURL)/formula.json")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode([BrewFormula].self, from: data)
    }
    
    func fetchAllCasks() async throws -> [BrewCask] {
        let url = URL(string: "\(baseURL)/cask.json")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode([BrewCask].self, from: data)
    }
    
    func fetchFormulaDetail(name: String) async throws -> BrewFormula {
        let checked = try BrewArgumentValidator.validated(name, as: .package)
        guard let url = URL(string: "\(baseURL)/formula/\(checked).json") else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(BrewFormula.self, from: data)
    }
    
    func fetchCaskDetail(token: String) async throws -> BrewCask {
        let checked = try BrewArgumentValidator.validated(token, as: .package)
        guard let url = URL(string: "\(baseURL)/cask/\(checked).json") else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(BrewCask.self, from: data)
    }
    
    // MARK: - Analytics
    
    func fetchInstallAnalytics(days: AnalyticsPeriod) async throws -> AnalyticsResponse {
        let url = URL(string: "\(baseURL)/analytics/install/\(days.rawValue).json")!
        let (data, _) = try await session.data(from: url)
        return try analyticsDecoder.decode(AnalyticsResponse.self, from: data)
    }
    
    func fetchCaskInstallAnalytics(days: AnalyticsPeriod) async throws -> CaskAnalyticsResponse {
        let url = URL(string: "\(baseURL)/analytics/cask-install/\(days.rawValue).json")!
        let (data, _) = try await session.data(from: url)
        return try analyticsDecoder.decode(CaskAnalyticsResponse.self, from: data)
    }

    func fetchAnalyticsBundle(period: AnalyticsPeriod) async throws -> AnalyticsBundle {
        async let formulaTask = fetchInstallAnalytics(days: period)
        async let caskTask = fetchCaskInstallAnalytics(days: period)
        let (formula, cask) = try await (formulaTask, caskTask)
        return AnalyticsBundle(formula: formula, cask: cask, period: period)
    }
    
    enum AnalyticsPeriod: String, Sendable {
        case thirtyDays = "30d"
        case ninetyDays = "90d"
        case oneYear = "365d"
    }
    
    // MARK: - Background Fetch
    // formula.json (~32 MB) and cask.json (~19 MB) carry ETags. Sending the stored
    // ETag back as If-None-Match gets a 304 with an empty body when nothing changed.

    func fetchCatalog(formulaETag: String? = nil, caskETag: String? = nil) async throws -> CatalogData {
        async let formulaeTask = conditionalFetch(
            [BrewFormula].self, path: "formula.json", eTag: formulaETag)
        async let casksTask = conditionalFetch([BrewCask].self, path: "cask.json", eTag: caskETag)

        let (formulae, casks) = try await (formulaeTask, casksTask)
        return CatalogData(
            formulae: formulae.items.map(Self.droppingInvalidNames),
            casks: casks.items.map(Self.droppingInvalidNames),
            formulaETag: formulae.eTag, caskETag: casks.eTag,
            timestamp: Date())
    }

    private func conditionalFetch<Item: Decodable & Sendable>(
        _ type: [Item].Type, path: String, eTag: String?
    ) async throws -> ConditionalFetchResult<Item> {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(path)")!)
        if let eTag {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        return try Self.interpretConditional(
            type, data: data, response: response, sentETag: eTag, decoder: decoder)
    }

    /// Split out of `conditionalFetch` so the 304 handling is testable without a network.
    nonisolated static func interpretConditional<Item: Decodable & Sendable>(
        _ type: [Item].Type, data: Data, response: URLResponse, sentETag: String?,
        decoder: JSONDecoder
    ) throws -> ConditionalFetchResult<Item> {
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 {
            return ConditionalFetchResult(items: nil, eTag: sentETag)
        }
        // Anything but 200 is an error page or a partial answer, not a catalog: report the
        // status instead of failing later as a JSON decoding error.
        if let status = http?.statusCode, status != 200 {
            throw CatalogFetchError.unexpectedStatus(status)
        }
        return ConditionalFetchResult(
            items: try decoder.decode([Item].self, from: data),
            eTag: http?.value(forHTTPHeaderField: "ETag"))
    }

    /// Catalog records whose identifier is not a valid package name are dropped: the id is
    /// later shown, used as a file-name seed and passed to brew, and the catalog is
    /// protected by TLS only.
    nonisolated static func droppingInvalidNames<Item: BrewItem>(_ items: [Item]) -> [Item] {
        items.filter { BrewArgumentValidator.isValid($0.brewIdentifier, as: .package) }
    }
}

enum CatalogFetchError: Error, LocalizedError, Equatable {
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "The Homebrew catalog server answered with HTTP \(status)."
        }
    }
}

// MARK: - DTOs

/// `items == nil` means 304 Not Modified: the caller's stored copy is current.
struct ConditionalFetchResult<Item: Sendable>: Sendable {
    let items: [Item]?
    let eTag: String?
}

/// A `nil` list means the server answered 304 for it; load the cached copy instead.
struct CatalogData: Sendable {
    let formulae: [BrewFormula]?
    let casks: [BrewCask]?
    let formulaETag: String?
    let caskETag: String?
    let timestamp: Date
}

struct AnalyticsBundle: Sendable {
    let formula: AnalyticsResponse
    let cask: CaskAnalyticsResponse
    let period: HomebrewAPIService.AnalyticsPeriod
}

struct AnalyticsResponse: Codable, Sendable {
    let category: String
    let totalItems: Int
    let startDate: String
    let endDate: String
    let totalCount: Int
    let items: [AnalyticsItem]
}

struct AnalyticsItem: Codable, Sendable {
    let number: Int
    let formula: String
    let count: String
    let percent: String
}

struct CaskAnalyticsResponse: Codable, Sendable {
    let category: String
    let totalItems: Int
    let startDate: String
    let endDate: String
    let totalCount: Int
    let items: [CaskAnalyticsItem]
}

struct CaskAnalyticsItem: Codable, Sendable {
    let number: Int
    let cask: String
    let count: String
    let percent: String
}
