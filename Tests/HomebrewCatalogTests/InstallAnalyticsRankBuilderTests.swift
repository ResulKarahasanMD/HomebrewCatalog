import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("InstallAnalyticsRankBuilder")
struct InstallAnalyticsRankBuilderTests {
    @Test("parseInstallCount handles comma-separated values")
    func parseCommaSeparated() {
        #expect(InstallAnalyticsRankBuilder.parseInstallCount("487,796") == 487_796)
        #expect(InstallAnalyticsRankBuilder.parseInstallCount("5,840") == 5_840)
        #expect(InstallAnalyticsRankBuilder.parseInstallCount("1") == 1)
    }

    @Test("parseInstallCount returns zero for invalid input")
    func parseInvalid() {
        #expect(InstallAnalyticsRankBuilder.parseInstallCount("") == 0)
        #expect(InstallAnalyticsRankBuilder.parseInstallCount("n/a") == 0)
    }

    @Test("formulaCounts maps formula names to install counts")
    func formulaCounts() throws {
        let json = """
        {
          "category": "formula_install",
          "total_items": 2,
          "start_date": "2026-01-01",
          "end_date": "2026-02-01",
          "total_count": 100,
          "items": [
            {"number": 1, "formula": "openssl@3", "count": "10,000", "percent": "10"},
            {"number": 2, "formula": "gh", "count": "500", "percent": "5"}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(AnalyticsResponse.self, from: Data(json.utf8))
        let counts = InstallAnalyticsRankBuilder.formulaCounts(from: response)
        #expect(counts["openssl@3"] == 10_000)
        #expect(counts["gh"] == 500)
    }

    @Test("analytics responses decode numeric total_count from live API shape")
    func decodeNumericTotalCount() throws {
        let json = """
        {
          "category": "formula_install",
          "total_items": 1,
          "start_date": "2025-05-20",
          "end_date": "2026-05-20",
          "total_count": 272011158,
          "items": [
            {"number": 1, "formula": "openssl@3", "count": "5,566,316", "percent": "2.05"}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(AnalyticsResponse.self, from: Data(json.utf8))
        #expect(response.totalCount == 272_011_158)
        #expect(response.items[0].formula == "openssl@3")
    }

    @Test("caskCounts maps flat items array")
    func caskCounts() throws {
        let json = """
        {
          "category": "cask_install",
          "total_items": 2,
          "start_date": "2026-01-01",
          "end_date": "2026-02-01",
          "total_count": "100",
          "items": [
            {"number": 1, "cask": "firefox", "count": "12,000", "percent": "10"},
            {"number": 2, "cask": "1password", "count": "5,840", "percent": "5"}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(CaskAnalyticsResponse.self, from: Data(json.utf8))
        let counts = InstallAnalyticsRankBuilder.caskCounts(from: response)
        #expect(counts["firefox"] == 12_000)
        #expect(counts["1password"] == 5_840)
    }
}
