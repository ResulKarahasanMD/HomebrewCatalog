import Foundation
import SwiftData
import Testing
@testable import HomebrewCatalog

@Suite("RetryGate")
@MainActor
struct RetryGateTests {
    private func failedRecord(_ op: BrewMutation.Op) -> ActionRecord {
        let record = ActionRecord(mutation: BrewMutation(op))
        record.status = .failed
        return record
    }

    @Test("a Retry request stages the command and runs nothing until confirmed")
    func requestRunsNothing() async throws {
        let service = MockBrewService()
        let installed = InstalledFeatureStore(service: service, installedCache: .isolated())
        let coordinator = MutationCoordinator(service: service, installed: installed)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)

        var gate = RetryGate()
        let staged = gate.request(failedRecord(.uninstall(name: "wget", isCask: false)).retryMutation)

        #expect(staged)
        #expect(gate.command == "brew uninstall wget")
        #expect(await service.uninstallCalls.isEmpty)

        // Only the confirmation hands the mutation to the coordinator.
        let confirmed = gate.confirm()
        let mutation = try #require(confirmed)
        await coordinator.run(mutation, context: context)
        #expect(await service.uninstallCalls.count == 1)

        // The confirmation is spent: a second click has nothing to run.
        let second = gate.confirm()
        #expect(second == nil)
        #expect(gate.pending == nil)
    }

    @Test("cancelling drops the staged mutation")
    func cancelDropsPending() {
        var gate = RetryGate()
        gate.request(BrewMutation(.install(name: "jq", isCask: false)))
        gate.cancel()
        #expect(gate.pending == nil)
        let confirmed = gate.confirm()
        #expect(confirmed == nil)
    }

    @Test("a stored record whose package name is option-like is never staged", arguments: [
        "--force", "-f", "../x", "wget --zap",
    ])
    func invalidStoredNameIsRefused(_ name: String) {
        var gate = RetryGate()
        let staged = gate.request(failedRecord(.uninstall(name: name, isCask: true)).retryMutation)
        #expect(!staged)
        #expect(gate.pending == nil)
        #expect(gate.command == nil)
        #expect(gate.refusal != nil)
    }

    @Test("upgrade-all has no name to check and can be staged")
    func upgradeAllIsStaged() {
        var gate = RetryGate()
        let staged = gate.request(BrewMutation(.upgrade(target: .all)))
        #expect(staged)
        #expect(gate.command == "brew upgrade")
    }

    @Test("no retry mutation, nothing staged")
    func nilRequest() {
        var gate = RetryGate()
        let staged = gate.request(nil)
        #expect(!staged)
        #expect(gate.pending == nil)
        #expect(gate.refusal == nil)
    }
}
