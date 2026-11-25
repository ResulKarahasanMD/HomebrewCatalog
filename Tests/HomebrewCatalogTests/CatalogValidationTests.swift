import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("Catalog validation")
struct CatalogValidationTests {
    @Test("catalogDropsInvalidNames: formula records with invalid names are dropped")
    func dropsInvalidFormulae() throws {
        let body = Data(
            #"""
            [{"name":"jq","tap":"homebrew/core"},
             {"name":"--force","tap":"homebrew/core"},
             {"name":"../../x","tap":"homebrew/core"},
             {"name":"python@3.12","tap":"homebrew/core"}]
            """#.utf8)
        let decoded = try JSONDecoder().decode([BrewFormula].self, from: body)
        #expect(decoded.count == 4)
        #expect(HomebrewAPIService.droppingInvalidNames(decoded).map(\.name) == ["jq", "python@3.12"])
    }

    @Test("cask records with invalid tokens are dropped")
    func dropsInvalidCasks() throws {
        let body = Data(
            #"[{"token":"iterm2","name":["iTerm2"]},{"token":"-f","name":["Evil"]},{"token":"a b","name":["Spaced"]}]"#
                .utf8)
        let decoded = try JSONDecoder().decode([BrewCask].self, from: body)
        #expect(decoded.count == 3)
        #expect(HomebrewAPIService.droppingInvalidNames(decoded).map(\.token) == ["iterm2"])
    }
}
