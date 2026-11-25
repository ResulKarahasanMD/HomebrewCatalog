import Testing
@testable import HomebrewCatalog

// Line formats from Homebrew's own source (Library/Homebrew/cleanup.rb and cmd/cleanup.rb,
// checked 2026-09-30): "Would remove: <path> (<size>)", "Would remove (broken link): <path>",
// "Would remove (empty directory): <dir>", "==> This operation would free approximately
// <size> of disk space." and "==> Would autoremove <n> unneeded formula(e):" + one name per line.
@Suite("MaintenancePreview")
struct MaintenancePreviewTests {
    @Test("a cleanup dry run lists each path with its size and the total it would free")
    func cleanupPreviewParses() {
        let output = """
            Would remove: /Users/alice/Library/Caches/Homebrew/downloads/1a2b--jq--1.7.1.arm64_sequoia.bottle.tar.gz (512.3KB)
            Would remove: /opt/homebrew/Cellar/jq/1.7.1 (19 files, 1.4MB)
            Warning: Skipping wget: most recent version 1.25.0 not installed
            Would remove (broken link): /opt/homebrew/bin/oldtool
            Would remove (empty directory): /opt/homebrew/share/foo
            ==> This operation would free approximately 1.9MB of disk space.
            """

        let preview = CleanupPreview(output: output)

        #expect(preview.items == [
            .init(path: "/Users/alice/Library/Caches/Homebrew/downloads/1a2b--jq--1.7.1.arm64_sequoia.bottle.tar.gz",
                  detail: "512.3KB"),
            .init(path: "/opt/homebrew/Cellar/jq/1.7.1", detail: "19 files, 1.4MB"),
            .init(path: "/opt/homebrew/bin/oldtool", detail: "broken link"),
            .init(path: "/opt/homebrew/share/foo", detail: "empty directory"),
        ])
        #expect(preview.freed == "1.9MB")
        #expect(preview.notes == ["Warning: Skipping wget: most recent version 1.25.0 not installed"])
        #expect(!preview.isEmpty)
    }

    @Test("a cleanup dry run with nothing to remove is empty")
    func emptyCleanupPreview() {
        let preview = CleanupPreview(output: "")

        #expect(preview.isEmpty)
        #expect(preview.freed == nil)
    }

    @Test("an autoremove dry run lists the formulae it would uninstall", arguments: [
        ("==> Would autoremove 2 unneeded formulae:\nlibevent\nutf8proc\n", ["libevent", "utf8proc"]),
        ("==> Would autoremove 1 unneeded formula:\nlibevent", ["libevent"]),
        ("", []),
    ])
    func autoremovePreviewParses(output: String, formulae: [String]) {
        #expect(AutoremovePreview(output: output).formulae == formulae)
    }
}
