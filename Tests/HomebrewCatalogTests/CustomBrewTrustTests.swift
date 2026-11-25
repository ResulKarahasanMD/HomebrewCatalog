import Foundation
import Testing
@testable import HomebrewCatalog

/// The ownership/mode rule behind a custom brew path, as a pure function so foreign
/// owners and groups can be covered without creating such files.
@Suite("Custom brew ownership rule")
struct CustomBrewTrustTests {
    private let me: UInt32 = 501
    private let admin: UInt32 = 80
    private let staff: UInt32 = 20

    @Test("owner must be root or the current user")
    func ownerCheck() {
        #expect(BrewProcessService.isTrustedOwnership(
            mode: 0o755, owner: me, group: staff, isDirectory: false, currentUser: me))
        #expect(BrewProcessService.isTrustedOwnership(
            mode: 0o755, owner: 0, group: 0, isDirectory: false, currentUser: me))
        #expect(!BrewProcessService.isTrustedOwnership(
            mode: 0o755, owner: 502, group: staff, isDirectory: false, currentUser: me))
    }

    @Test("world-writable is always refused")
    func worldWritable() {
        #expect(!BrewProcessService.isTrustedOwnership(
            mode: 0o757, owner: me, group: admin, isDirectory: true, currentUser: me))
        #expect(!BrewProcessService.isTrustedOwnership(
            mode: 0o1777, owner: 0, group: 0, isDirectory: true, currentUser: me))
    }

    @Test("group-writable passes only for an admin-group directory")
    func groupWritable() {
        // Homebrew's own layout: drwxrwxr-x user:admin on <prefix>/bin.
        #expect(BrewProcessService.isTrustedOwnership(
            mode: 0o775, owner: me, group: admin, isDirectory: true, currentUser: me))
        #expect(!BrewProcessService.isTrustedOwnership(
            mode: 0o775, owner: me, group: staff, isDirectory: true, currentUser: me))
        #expect(!BrewProcessService.isTrustedOwnership(
            mode: 0o775, owner: me, group: admin, isDirectory: false, currentUser: me))
    }
}
