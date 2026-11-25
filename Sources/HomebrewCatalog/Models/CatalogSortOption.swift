import Foundation

enum CatalogSortOption: String, CaseIterable, Sendable {
    case `default` = "Default"
    case mostDownloaded = "Most Downloaded"
}

enum AnalyticsTimePeriod: String, CaseIterable, Sendable, Identifiable {
    case thirtyDays = "30 days"
    case ninetyDays = "90 days"
    case oneYear = "Past year"

    var id: String { rawValue }

    var apiPeriod: HomebrewAPIService.AnalyticsPeriod {
        switch self {
        case .thirtyDays: .thirtyDays
        case .ninetyDays: .ninetyDays
        case .oneYear: .oneYear
        }
    }

    var helpText: String {
        switch self {
        case .thirtyDays:
            "Install counts from the last 30 days."
        case .ninetyDays:
            "Install counts from the last 90 days."
        case .oneYear:
            "Install counts from the last 365 days (longest window Homebrew publishes)."
        }
    }

    var installCountLabel: String {
        switch self {
        case .thirtyDays: "30d installs"
        case .ninetyDays: "90d installs"
        case .oneYear: "past year installs"
        }
    }
}
