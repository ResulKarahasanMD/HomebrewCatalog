import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("BrewArgumentValidator")
struct BrewArgumentValidatorTests {
    @Test("accepts real-world names", arguments: [
        "wget", "python@3.12", "gtk+3", "c-ares", "visual-studio-code@insiders", "a52dec", "0-ad",
        "homebrew/cask/iterm2", "user/tap/my_tool", "ResulKarahasanMD/tap/Tool",
    ])
    func acceptsNames(_ name: String) {
        #expect(BrewArgumentValidator.isValid(name, as: .package))
        #expect(BrewArgumentValidator.isValid(name, as: .service))
    }

    @Test("rejects option-like and path-like names", arguments: [
        "--force", "-f", "-", "", " wget", "wget ", "wget\n", "../etc", "a/../b/c", "a..b", "/usr/bin/x",
        "a;b", "$(id)", "wget --HEAD", "a/b", "a/b/c/d", "wget\u{0}", "@wget", "+x", ".hidden",
    ])
    func rejectsOptionLikeNames(_ name: String) {
        #expect(!BrewArgumentValidator.isValid(name, as: .package))
        #expect(!BrewArgumentValidator.isValid(name, as: .service))
        #expect(throws: BrewProcessError.self) { try BrewArgumentValidator.validated(name, as: .package) }
    }

    @Test("a name longer than the limit is rejected")
    func rejectsOverlongName() {
        #expect(BrewArgumentValidator.isValid(String(repeating: "a", count: 128), as: .package))
        #expect(!BrewArgumentValidator.isValid(String(repeating: "a", count: 129), as: .package))
    }

    @Test("tap names", arguments: [
        ("user/repo", true), ("homebrew/cask-fonts", true), ("ResulKarahasanMD/homebrew-tap", true),
        ("--custom-remote", false), ("-u/repo", false), ("user/repo extra", false), ("user", false),
        ("user/repo/extra", false), ("user/..", false), ("https://example.com/x.git", false), ("", false),
    ])
    func tapNames(_ name: String, _ ok: Bool) {
        #expect(BrewArgumentValidator.isValid(name, as: .tap) == ok)
    }

    @Test("mas search text", arguments: [
        ("Xcode", true), ("Final Cut Pro", true), ("pages & numbers", true),
        ("-h", false), ("--help", false), ("", false), ("a\u{1B}[0m", false), ("line\nbreak", false),
    ])
    func masQuery(_ query: String, _ ok: Bool) {
        #expect(BrewArgumentValidator.isValid(query, as: .masQuery) == ok)
    }

    @Test("the error names the kind and never echoes more than 64 characters")
    func errorDescription() {
        let long = "-" + String(repeating: "x", count: 500)
        do {
            _ = try BrewArgumentValidator.validated(long, as: .tap)
            Issue.record("expected a throw")
        } catch let BrewProcessError.invalidArgument(kind, value) {
            #expect(kind == "tap")
            #expect(value.count == 64)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

@Suite("BrewArguments")
struct BrewArgumentsTests {
    @Test("names follow the option terminator")
    func namesFollowTerminator() throws {
        #expect(try BrewArguments.package("install", name: "wget", isCask: false) == ["install", "--", "wget"])
        #expect(
            try BrewArguments.package("uninstall", name: "iterm2", isCask: true)
                == ["uninstall", "--cask", "--", "iterm2"])
        #expect(
            try BrewArguments.named(["uses"], options: ["--installed"], names: ["openssl@3"])
                == ["uses", "--installed", "--", "openssl@3"])
        #expect(try BrewArguments.service("restart", name: "postgresql@17") == ["services", "restart", "--", "postgresql@17"])
        #expect(try BrewArguments.tap("untap", name: "user/repo") == ["untap", "--", "user/repo"])
        #expect(
            try BrewArguments.named(["upgrade"], names: ["a", "b"]) == ["upgrade", "--", "a", "b"])
    }

    @Test("no names means no terminator, so `brew upgrade` stays `brew upgrade`")
    func noNames() throws {
        #expect(try BrewArguments.named(["upgrade"], names: []) == ["upgrade"])
        #expect(try BrewArguments.named(["upgrade"], options: ["--cask"], names: []) == ["upgrade", "--cask"])
    }

    @Test("one invalid name refuses the whole command")
    func oneBadNameRefusesAll() {
        #expect(throws: BrewProcessError.self) {
            try BrewArguments.named(["upgrade"], names: ["wget", "--force"])
        }
        #expect(throws: BrewProcessError.self) { try BrewArguments.tap("tap", name: "--custom-remote") }
        #expect(throws: BrewProcessError.self) { try BrewArguments.service("start", name: "--all") }
    }
}

/// Every name-taking entry point of the live service must throw before it resolves brew or
/// spawns anything. A fresh actor is used; with an invalid name no process is started.
@Suite("BrewProcessService refuses invalid names")
struct BrewProcessServiceValidationTests {
    private static func isInvalidArgument(_ error: any Error) -> Bool {
        if case BrewProcessError.invalidArgument = error { return true }
        return false
    }

    private func expectRefusal(
        _ body: @Sendable (BrewProcessService) async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let service = BrewProcessService()
        do {
            try await body(service)
            Issue.record("expected invalidArgument", sourceLocation: sourceLocation)
        } catch {
            #expect(Self.isInvalidArgument(error), "got \(error)", sourceLocation: sourceLocation)
        }
    }

    @Test("package operations")
    func packageOperations() async {
        let bad = "--force"
        await expectRefusal { _ = try await $0.install(name: bad, isCask: false) { _ in } }
        await expectRefusal { _ = try await $0.uninstall(name: bad, isCask: true) { _ in } }
        await expectRefusal { _ = try await $0.upgrade(name: bad, isCask: false) { _ in } }
        await expectRefusal { _ = try await $0.upgrade(names: ["wget", bad]) { _ in } }
        await expectRefusal { _ = try await $0.reinstall(name: bad, isCask: false) { _ in } }
        await expectRefusal { _ = try await $0.pin(name: bad) }
        await expectRefusal { _ = try await $0.unpin(name: bad) }
        await expectRefusal { _ = try await $0.reverseDependencies(name: bad, installed: true) }
        await expectRefusal { _ = try await $0.infoInstalledFormula(name: bad) }
        await expectRefusal { _ = try await $0.infoInstalledCask(name: bad) }
    }

    @Test("services and taps")
    func servicesAndTaps() async {
        await expectRefusal { _ = try await $0.startService(name: "--all") }
        await expectRefusal { _ = try await $0.stopService(name: "--all") }
        await expectRefusal { _ = try await $0.restartService(name: "-v") }
        await expectRefusal { _ = try await $0.addTap(name: "--custom-remote") { _ in } }
        await expectRefusal { _ = try await $0.addTap(name: "user/repo https://example.com/x.git") { _ in } }
        await expectRefusal { _ = try await $0.removeTap(name: "--force") }
    }

    @Test("mas search refuses option-like text before looking for mas")
    func masSearch() async {
        do {
            _ = try await MASService().search(query: "--help")
            Issue.record("expected invalidQuery")
        } catch MASError.invalidQuery {
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
