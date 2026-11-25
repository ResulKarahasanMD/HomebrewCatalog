import Foundation
import Testing
@testable import HomebrewCatalog

/// Kept apart from `ConditionalFetchTests` and free of new symbols on purpose: these ran
/// (and failed) against the code before the fix.
@Suite("Catalog HTTP status")
struct CatalogStatusTests {
    private let url = URL(string: "https://formulae.brew.sh/api/formula.json")!

    @Test("a non-200, non-304 answer is an error even when its body is valid JSON", arguments: [
        201, 206, 403, 404, 500, 503,
    ])
    func non200Throws(_ status: Int) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: nil)!
        let body = Data(#"[{"name":"jq","tap":"homebrew/core"}]"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try HomebrewAPIService.interpretConditional(
                [BrewFormula].self, data: body, response: response, sentETag: nil, decoder: JSONDecoder())
        }
    }
}
