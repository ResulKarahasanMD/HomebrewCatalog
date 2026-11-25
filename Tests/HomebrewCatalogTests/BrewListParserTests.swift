import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("Brew list parser fixtures")
struct BrewListParserTests {
    @Test("parses installed formulas from fixture")
    func parseInstalledFormulas() throws {
        let json = try fixture("installed-formulas.json")
        let formulas = try BrewProcessService.parseInstalledFormulas(json)

        #expect(formulas.count == 2)
        let ripgrep = try #require(formulas.first { $0.name == "ripgrep" })
        #expect(ripgrep.isOutdated == true)
        #expect(ripgrep.latestVersion == "14.1.1")
        let oniguruma = try #require(formulas.first { $0.name == "oniguruma" })
        #expect(oniguruma.installedAsDependency == true)
    }

    @Test("parses installed casks from fixture")
    func parseInstalledCasks() throws {
        let json = try fixture("installed-casks.json")
        let casks = try BrewProcessService.parseInstalledCasks(json)

        #expect(casks.count == 2)
        #expect(casks[0].token == "visual-studio-code")
        #expect(casks[0].isOutdated == true)
        #expect(casks[1].token == "iterm2")
        #expect(casks[1].isOutdated == false)
    }

    @Test("parses outdated list from fixture")
    func parseOutdated() throws {
        let json = try fixture("outdated.json")
        let outdated = try BrewProcessService.parseOutdated(json)

        #expect(outdated.count == 3)
        #expect(outdated.contains { $0.name == "wget" && $0.itemType == .formula })
        #expect(outdated.contains { $0.name == "openssl@3" && $0.isPinned })
        #expect(outdated.contains { $0.name == "google-chrome" && $0.itemType == .cask })
    }

    @Test("parses outdated cask when installed_versions is a string or array")
    func parseOutdatedCaskVersionShapes() throws {
        let arrayJSON = """
        {"formulae":[],"casks":[{"name":"claude-code","installed_versions":["2.1.138"],"current_version":"2.1.139"}]}
        """
        let stringJSON = """
        {"formulae":[],"casks":[{"name":"claude-code","installed_versions":"2.1.138","current_version":"2.1.139"}]}
        """

        let fromArray = try BrewProcessService.parseOutdated(arrayJSON)
        let fromString = try BrewProcessService.parseOutdated(stringJSON)

        #expect(fromArray.count == 1)
        #expect(fromArray[0].installedVersion == "2.1.138")
        #expect(fromString.count == 1)
        #expect(fromString[0].installedVersion == "2.1.138")
    }

    @Test("parses live outdated JSON file when present")
    func parseLiveOutdatedJSON() throws {
        let path = "/tmp/brew-outdated.json"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let json = try String(contentsOfFile: path, encoding: .utf8)
        let outdated = try BrewProcessService.parseOutdated(json)
        #expect(!outdated.isEmpty)
    }

    @Test("parses pinned names from fixture")
    func parsePinned() throws {
        let text = try fixture("pinned.txt")
        let names = BrewProcessService.parseLineSeparatedNames(text)

        #expect(names == ["ripgrep", "openssl@3"])
    }

    @Test("installed formula parser handles null array")
    func parseInstalledFormulasWithNullArray() throws {
        let formulas = try BrewProcessService.parseInstalledFormulas("{\"formulae\": null}")
        #expect(formulas.isEmpty)
    }

    @Test("installed formula parser handles empty array")
    func parseInstalledFormulasWithEmptyArray() throws {
        let formulas = try BrewProcessService.parseInstalledFormulas("{\"formulae\": []}")
        #expect(formulas.isEmpty)
    }

    @Test("parses leaves names from fixture")
    func parseLeaves() throws {
        let text = try fixture("leaves.txt")
        let names = BrewProcessService.parseLineSeparatedNames(text)

        #expect(names == ["ripgrep", "jq"])
    }

    private func fixture(_ name: String) throws -> String {
        guard
            let url = Bundle(for: FixtureBundleToken.self)
                .url(forResource: name, withExtension: nil)
        else {
            throw FixtureError.notFound(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private final class FixtureBundleToken {}

private enum FixtureError: Error {
    case notFound(String)
}
