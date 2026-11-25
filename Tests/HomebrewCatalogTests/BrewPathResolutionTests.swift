import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("BrewPathResolution")
struct BrewPathResolutionTests {
    private static func makeExecutableFixture(
        parent: URL,
        name: String = "brew"
    ) throws -> URL {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let path = parent.appendingPathComponent(name)
        FileManager.default.createFile(
            atPath: path.path,
            contents: Data("#!/bin/sh\necho fake brew\n".utf8),
            attributes: [.posixPermissions: NSNumber(value: Int16(0o755))]
        )
        return path
    }

    private static func freshTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("brewcat-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Apple Silicon brew at /opt/homebrew is allowed when present")
    func appleSiliconAllowed() {
        let path = "/opt/homebrew/bin/brew"
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        #expect(BrewProcessService.isAllowedBrewPath(path, customOverride: nil))
    }

    @Test("Intel brew at /usr/local is allowed when present")
    func intelAllowed() {
        let path = "/usr/local/bin/brew"
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        #expect(BrewProcessService.isAllowedBrewPath(path, customOverride: nil))
    }

    /// A fake Homebrew prefix: `<root>/bin/brew` next to `<root>/Library/Homebrew/brew.sh`.
    private static func makeHomebrewPrefix(brewName: String = "brew") throws -> (root: URL, brew: URL) {
        let root = freshTempDir()
        let brew = try makeExecutableFixture(
            parent: root.appendingPathComponent("bin", isDirectory: true), name: brewName)
        let library = root.appendingPathComponent("Library/Homebrew", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: library.appendingPathComponent("brew.sh").path, contents: Data("# brew.sh\n".utf8))
        return (root, brew)
    }

    private static func chmod(_ url: URL, _ mode: Int16) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
    }

    @Test("Custom override is accepted for a private Homebrew prefix outside the allow-list")
    func customOverrideAcceptsHomebrewLayout() throws {
        let (root, brew) = try Self.makeHomebrewPrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(BrewProcessService.isAllowedBrewPath(brew.path, customOverride: brew.path))
        // The override only vouches for itself, not for other paths.
        #expect(!BrewProcessService.isAllowedBrewPath(brew.path, customOverride: "/somewhere/else/bin/brew"))
    }

    @Test("Custom override: an executable outside a Homebrew layout is refused")
    func customOverrideRequiresHomebrewLayout() throws {
        let dir = Self.freshTempDir().appendingPathComponent("bin", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let fixture = try Self.makeExecutableFixture(parent: dir)
        #expect(
            !BrewProcessService.isAllowedBrewPath(fixture.path, customOverride: fixture.path)
        )
    }

    @Test("Custom override: a file not named brew is refused")
    func customOverrideRequiresBrewName() throws {
        let (root, tool) = try Self.makeHomebrewPrefix(brewName: "not-brew")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!BrewProcessService.isAllowedBrewPath(tool.path, customOverride: tool.path))
    }

    @Test("Custom override: a group- or world-writable brew file is refused", arguments: [0o775, 0o757, 0o777])
    func customOverrideRejectsWritableFile(_ mode: Int) throws {
        let (root, brew) = try Self.makeHomebrewPrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.chmod(brew, Int16(mode))
        #expect(!BrewProcessService.isAllowedBrewPath(brew.path, customOverride: brew.path))
    }

    @Test("Custom override: a world-writable bin directory or prefix is refused")
    func customOverrideRejectsWorldWritable() throws {
        let (root, brew) = try Self.makeHomebrewPrefix()
        defer {
            try? Self.chmod(root, 0o755)
            try? FileManager.default.removeItem(at: root)
        }
        try Self.chmod(brew.deletingLastPathComponent(), 0o777)
        #expect(!BrewProcessService.isAllowedBrewPath(brew.path, customOverride: brew.path))

        try Self.chmod(brew.deletingLastPathComponent(), 0o755)
        try Self.chmod(root, 0o777)
        #expect(!BrewProcessService.isAllowedBrewPath(brew.path, customOverride: brew.path))
    }

    @Test("Custom override: a symlink kept in a world-writable directory is refused")
    func customOverrideRejectsLinkInWritableDirectory() throws {
        let (root, brew) = try Self.makeHomebrewPrefix()
        let linkDir = Self.freshTempDir()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: linkDir)
        }
        try FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let link = linkDir.appendingPathComponent("brew")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: brew)
        #expect(BrewProcessService.isAllowedBrewPath(link.path, customOverride: link.path))

        try Self.chmod(linkDir, 0o777)
        #expect(!BrewProcessService.isAllowedBrewPath(link.path, customOverride: link.path))
    }

    @Test("Empty path is rejected")
    func emptyPathRejected() {
        #expect(!BrewProcessService.isAllowedBrewPath("", customOverride: nil))
    }

    @Test("Nonexistent path is rejected")
    func nonexistentPathRejected() {
        let phantom = "/tmp/nonexistent-\(UUID().uuidString)/brew"
        #expect(!BrewProcessService.isAllowedBrewPath(phantom, customOverride: nil))
    }

    @Test("Temp-dir brew is rejected when grandparent is not in the allow-list")
    func tempDirRejected() throws {
        let dir = Self.freshTempDir().appendingPathComponent("bin", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let fixture = try Self.makeExecutableFixture(parent: dir)
        #expect(!BrewProcessService.isAllowedBrewPath(fixture.path, customOverride: nil))
    }

    @Test("Symlinked temp brew is rejected — resolution happens before allow-list check")
    func symlinkedTempRejected() throws {
        let tmpRoot = Self.freshTempDir()
        defer { try? FileManager.default.removeItem(at: tmpRoot) }
        let binDir = tmpRoot.appendingPathComponent("bin", isDirectory: true)
        let target = try Self.makeExecutableFixture(parent: binDir, name: "brew")

        let decoy = tmpRoot.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
        let linkPath = decoy.appendingPathComponent("brew")
        try FileManager.default.createSymbolicLink(at: linkPath, withDestinationURL: target)

        #expect(!BrewProcessService.isAllowedBrewPath(linkPath.path, customOverride: nil))
    }

    @Test("Non-executable file is rejected")
    func nonExecutableRejected() throws {
        let dir = Self.freshTempDir().appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let path = dir.appendingPathComponent("brew")
        FileManager.default.createFile(
            atPath: path.path,
            contents: Data("not executable".utf8),
            attributes: [.posixPermissions: NSNumber(value: Int16(0o644))]
        )
        #expect(!BrewProcessService.isAllowedBrewPath(path.path, customOverride: nil))
    }
}
