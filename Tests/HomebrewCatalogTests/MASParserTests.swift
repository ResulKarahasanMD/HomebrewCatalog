import Testing
@testable import HomebrewCatalog

@Suite("MASService parsing")
struct MASParserTests {
    @Test("Parses name and version from mas list")
    func parsesInstalled() {
        let apps = MASService.parseInstalled(
            """
            497799835  Xcode        (27.0)
            1333542190 1Password 7  (7.9.11)
            """)
        #expect(apps.count == 2)
        #expect(apps[0].appID == 497_799_835)
        #expect(apps[0].name == "Xcode")
        #expect(apps[0].currentVersion == "27.0")
        #expect(apps[1].name == "1Password 7")
    }

    @Test("Parses current and available version from mas outdated")
    func parsesOutdated() {
        let apps = MASService.parseOutdated("409183694  Keynote  (13.1 -> 14.0)")
        #expect(apps.count == 1)
        #expect(apps[0].currentVersion == "13.1")
        #expect(apps[0].availableVersion == "14.0")
    }

    // BUG-03: the last "(" after the last ")" made the version slice's lower bound
    // exceed its upper bound, which traps at runtime instead of throwing.
    @Test(
        "Malformed parentheses keep the line instead of crashing",
        arguments: [
            "123456789  Weird App (1.0) (",
            "123456789  Weird App ) (",
        ])
    func malformedParenthesesDoNotTrap(line: String) {
        let installed = MASService.parseInstalled(line)
        #expect(installed.count == 1)
        #expect(installed[0].currentVersion == "unknown")

        let outdated = MASService.parseOutdated(line)
        #expect(outdated.count == 1)
        #expect(outdated[0].availableVersion == nil)
    }
}
