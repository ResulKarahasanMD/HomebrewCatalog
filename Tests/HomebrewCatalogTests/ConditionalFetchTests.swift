import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("Conditional catalog fetch")
struct ConditionalFetchTests {
    private let url = URL(string: "https://formulae.brew.sh/api/formula.json")!

    private func response(status: Int, eTag: String?) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/2",
            headerFields: eTag.map { ["ETag": $0] })!
    }

    @Test("304 Not Modified returns no items and keeps the sent ETag")
    func notModifiedKeepsETag() throws {
        let result = try HomebrewAPIService.interpretConditional(
            [BrewFormula].self, data: Data(), response: response(status: 304, eTag: nil),
            sentETag: "\"abc\"", decoder: JSONDecoder())
        #expect(result.items == nil)
        #expect(result.eTag == "\"abc\"")
    }

    @Test("200 decodes the body and takes the new ETag")
    func okDecodesAndUpdatesETag() throws {
        let body = Data(#"[{"name":"jq","tap":"homebrew/core"}]"#.utf8)
        let result = try HomebrewAPIService.interpretConditional(
            [BrewFormula].self, data: body, response: response(status: 200, eTag: "\"new\""),
            sentETag: "\"old\"", decoder: JSONDecoder())
        #expect(result.items?.map(\.name) == ["jq"])
        #expect(result.eTag == "\"new\"")
    }

    @Test("Metadata written before ETags existed still decodes")
    func legacyMetadataDecodes() throws {
        let json = #"{"lastUpdated":0,"formulaCount":1,"caskCount":2,"appVersion":"2"}"#
        let metadata = try JSONDecoder().decode(CatalogMetadata.self, from: Data(json.utf8))
        #expect(metadata.formulaETag == nil)
        #expect(metadata.caskETag == nil)
    }
}
