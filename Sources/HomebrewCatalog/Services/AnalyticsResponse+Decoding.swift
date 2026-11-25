import Foundation

extension AnalyticsResponse {
    enum CodingKeys: String, CodingKey {
        case category
        case totalItems
        case startDate
        case endDate
        case totalCount
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(String.self, forKey: .category)
        totalItems = try container.decode(Int.self, forKey: .totalItems)
        startDate = try container.decode(String.self, forKey: .startDate)
        endDate = try container.decode(String.self, forKey: .endDate)
        totalCount = try AnalyticsJSON.decodeTotalCount(from: container, forKey: .totalCount)
        items = try container.decode([AnalyticsItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(totalItems, forKey: .totalItems)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(totalCount, forKey: .totalCount)
        try container.encode(items, forKey: .items)
    }
}

extension CaskAnalyticsResponse {
    enum CodingKeys: String, CodingKey {
        case category
        case totalItems
        case startDate
        case endDate
        case totalCount
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(String.self, forKey: .category)
        totalItems = try container.decode(Int.self, forKey: .totalItems)
        startDate = try container.decode(String.self, forKey: .startDate)
        endDate = try container.decode(String.self, forKey: .endDate)
        totalCount = try AnalyticsJSON.decodeTotalCount(from: container, forKey: .totalCount)
        items = try container.decode([CaskAnalyticsItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(totalItems, forKey: .totalItems)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(totalCount, forKey: .totalCount)
        try container.encode(items, forKey: .items)
    }
}

private enum AnalyticsJSON {
    static func decodeTotalCount<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let text = try? container.decode(String.self, forKey: key) {
            return InstallAnalyticsRankBuilder.parseInstallCount(text)
        }
        return 0
    }
}
