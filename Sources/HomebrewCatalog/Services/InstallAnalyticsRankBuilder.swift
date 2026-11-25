import Foundation

enum InstallAnalyticsRankBuilder: Sendable {
    static func parseInstallCount(_ raw: String) -> Int {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits) else { return 0 }
        return value
    }

    static func formulaCounts(from response: AnalyticsResponse) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(response.items.count)
        for item in response.items {
            counts[item.formula] = parseInstallCount(item.count)
        }
        return counts
    }

    static func caskCounts(from response: CaskAnalyticsResponse) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(response.items.count)
        for item in response.items {
            counts[item.cask] = parseInstallCount(item.count)
        }
        return counts
    }
}
