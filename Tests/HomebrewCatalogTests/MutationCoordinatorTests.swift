import Foundation
import SwiftData
import Testing
@testable import HomebrewCatalog

@MainActor
private struct Harness {
    let service = MockBrewService()
    let container: ModelContainer
    let installed: InstalledFeatureStore
    let coordinator: MutationCoordinator

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        installed = InstalledFeatureStore(service: service, installedCache: .isolated())
        coordinator = MutationCoordinator(service: service, installed: installed)
    }

    var context: ModelContext { container.mainContext }

    func records() throws -> [ActionRecord] {
        try context.fetch(FetchDescriptor<ActionRecord>())
    }
}

/// Collects observer callbacks; the observer runs on the main actor.
@MainActor
private final class OutputLog {
    var chunks: [String] = []
}

enum RecordedMutationCall: Equatable, Sendable {
    case install(String, isCask: Bool)
    case uninstall(String, isCask: Bool)
    case upgrade(String?, isCask: Bool)
    case upgradeNames([String])
    case reinstall(String, isCask: Bool)
    case pin(String)
    case unpin(String)
}

extension MockBrewService {
    func recordedMutationCalls() -> [RecordedMutationCall] {
        installCalls.map { .install($0.name, isCask: $0.isCask) }
            + uninstallCalls.map { .uninstall($0.name, isCask: $0.isCask) }
            + upgradeCalls.map { .upgrade($0.name, isCask: $0.isCask) }
            + upgradeNamesCalls.map { .upgradeNames($0) }
            + reinstallCalls.map { .reinstall($0.name, isCask: $0.isCask) }
            + pinCalls.map { .pin($0) }
            + unpinCalls.map { .unpin($0) }
    }
}

@MainActor
private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

private let jq = InstalledFormulaInfo(
    name: "jq",
    fullName: "homebrew/core/jq",
    desc: "JSON processor",
    homepage: nil,
    license: nil,
    installedVersion: "1.7.1",
    latestVersion: "1.8.0",
    isPinned: false,
    isOutdated: true,
    installedOnRequest: true,
    installedAsDependency: false
)

private let jqOutdated = OutdatedInfo(
    name: "jq", installedVersion: "1.7.1", latestVersion: "1.8.0", isPinned: false, itemType: .formula)

@Suite("MutationCoordinator", .timeLimit(.minutes(1)))
@MainActor
struct MutationCoordinatorTests {
    nonisolated static let routes: [(op: BrewMutation.Op, call: RecordedMutationCall)] = [
        (.install(name: "jq", isCask: false), .install("jq", isCask: false)),
        (.uninstall(name: "iterm2", isCask: true), .uninstall("iterm2", isCask: true)),
        (.upgrade(target: .all), .upgradeNames([])),
        (.upgrade(target: .named(name: "rectangle", isCask: true)), .upgrade("rectangle", isCask: true)),
        (.reinstall(name: "jq", isCask: false), .reinstall("jq", isCask: false)),
        (.pin(name: "jq"), .pin("jq")),
        (.unpin(name: "jq"), .unpin("jq")),
    ]

    @Test("each mutation routes to the matching brew call", arguments: routes)
    func routesToService(op: BrewMutation.Op, call: RecordedMutationCall) async throws {
        let h = try Harness()

        await h.coordinator.run(BrewMutation(op), context: h.context)

        #expect(await h.service.recordedMutationCalls() == [call])
    }

    @Test("a zero exit is recorded as success with its output redacted")
    func successIsRecorded() async throws {
        let h = try Harness()
        await h.service.configureMutations(result: ProcessResult(
            stdout: "==> Pouring jq\nGITHUB_TOKEN=ghp_leak\n", stderr: "", exitCode: 0, command: "brew install jq"))

        let record = await h.coordinator.run(BrewMutation(.install(name: "jq", isCask: false)), context: h.context)

        #expect(record.status == .success)
        #expect(record.exitCode == 0)
        #expect(record.completedAt != nil)
        #expect(record.output.contains("==> Pouring jq"))
        #expect(!record.output.contains("ghp_leak"))
        #expect(try h.records().map(\.id) == [record.id])
    }

    @Test("a non-zero exit is recorded as failure with brew's stderr")
    func failureIsRecorded() async throws {
        let h = try Harness()
        await h.service.configureMutations(result: ProcessResult(
            stdout: "", stderr: "Error: No available formula with the name \"nosuch\".", exitCode: 1,
            command: "brew install nosuch"))

        let record = await h.coordinator.run(BrewMutation(.install(name: "nosuch", isCask: false)), context: h.context)

        #expect(record.status == .failed)
        #expect(record.exitCode == 1)
        #expect(record.errorOutput == "Error: No available formula with the name \"nosuch\".")
    }

    @Test("streamed output reaches the observer in order, line by line, before run returns")
    func streamedOutputIsOrderedAndComplete() async throws {
        let h = try Harness()
        await h.service.configureMutations(
            outputChunks: ["==> Fetching jq\n", "==> Pouring ", "jq--1.8.0.bottle\n", "done"])
        let log = OutputLog()

        await h.coordinator.run(
            BrewMutation(.install(name: "jq", isCask: false)), context: h.context,
            onOutput: { log.chunks.append($0) })

        #expect(log.chunks == ["==> Fetching jq\n", "==> Pouring jq--1.8.0.bottle\n", "done"])
        #expect(h.coordinator.currentOutput == "==> Fetching jq\n==> Pouring jq--1.8.0.bottle\ndone")
    }

    @Test("a secret in streamed output is redacted before the observer sees it")
    func streamedSecretIsRedacted() async throws {
        let h = try Harness()
        await h.service.configureMutations(outputChunks: ["export GITHUB_TOKEN=ghp_", "leak\n"])
        let log = OutputLog()

        await h.coordinator.run(
            BrewMutation(.install(name: "jq", isCask: false)), context: h.context,
            onOutput: { log.chunks.append($0) })

        #expect(log.chunks.joined().contains("export GITHUB_TOKEN="))
        #expect(!log.chunks.joined().contains("leak"))
        #expect(!h.coordinator.currentOutput.contains("leak"))
    }

    @Test("cancelling the run's task stops its brew command and records it as cancelled")
    func cancelRecordsCancelled() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)

        // Records are not Sendable, so the task hands back the id.
        let run = Task { await h.coordinator.run(BrewMutation(.install(name: "jq", isCask: false)), context: h.context).id }
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        run.cancel()
        let id = await run.value
        let record = try #require(try h.records().first { $0.id == id })

        #expect(record.status == .cancelled)
        #expect(record.completedAt != nil)
    }

    // Cancel used to stop every brew command in flight, so another sheet's install died
    // while this run's queued step went on to run.
    @Test("cancelling a run that waits for its turn leaves the running mutation alone")
    func cancelWhileQueuedDoesNotTouchRunningMutation() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)

        let install = Task {
            await h.coordinator.run(BrewMutation(.install(name: "big", isCask: false)), context: h.context).statusRaw
        }
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        let queued = Task {
            await h.coordinator.run(BrewMutation(.install(name: "wget", isCask: false)), context: h.context).statusRaw
        }
        #expect(await eventually { (try? h.records().count) == 2 })

        queued.cancel()
        #expect(await queued.value == ActionStatus.cancelled.rawValue)
        #expect(await h.service.heldMutationCount == 1)
        #expect(h.coordinator.isRunning)

        await h.service.releaseHeldMutation()
        #expect(await install.value == ActionStatus.success.rawValue)
        #expect(await h.service.installCalls.map(\.name) == ["big"])
        #expect(!h.coordinator.isRunning)
    }

    @Test("after a queued run is cancelled, the next one still gets its turn")
    func cancelledWaiterDoesNotBlockQueue() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)

        let first = Task { _ = await h.coordinator.run(BrewMutation(.install(name: "a", isCask: false)), context: h.context) }
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        let cancelled = Task { _ = await h.coordinator.run(BrewMutation(.install(name: "b", isCask: false)), context: h.context) }
        let third = Task { _ = await h.coordinator.run(BrewMutation(.install(name: "c", isCask: false)), context: h.context) }
        #expect(await eventually { (try? h.records().count) == 3 })
        cancelled.cancel()
        await cancelled.value

        await h.service.releaseHeldMutation()
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        await h.service.releaseHeldMutation()
        await first.value
        await third.value

        #expect(await h.service.installCalls.map(\.name) == ["a", "c"])
        #expect(!h.coordinator.isRunning)
    }

    @Test("mutations run one at a time and a queued one waits as pending")
    func mutationsAreSerialized() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)

        let first = Task { _ = await h.coordinator.run(BrewMutation(.install(name: "jq", isCask: false)), context: h.context) }
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        let second = Task { _ = await h.coordinator.run(BrewMutation(.install(name: "wget", isCask: false)), context: h.context) }
        #expect(await eventually { (try? h.records().count) == 2 })
        try await Task.sleep(for: .milliseconds(50))

        #expect(await h.service.installCalls.map(\.name) == ["jq"])
        #expect(try h.records().first { $0.packageName == "wget" }?.status == .pending)
        #expect(h.coordinator.isRunning)

        await h.service.releaseHeldMutation()
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        await h.service.releaseHeldMutation()
        await first.value
        await second.value

        #expect(await h.service.installCalls.map(\.name) == ["jq", "wget"])
        #expect(await h.service.maxConcurrentMutations == 1)
        #expect(!h.coordinator.isRunning)
    }

    @Test("a long log is stored as its last part, after a marker saying how much was dropped")
    func longOutputIsTruncatedForStorage() async throws {
        let h = try Harness()
        let limit = ActionRecord.storedOutputLimit
        let long = String(repeating: "x", count: limit + 5_000) + "Error: the end"
        await h.service.configureMutations(result: ProcessResult(
            stdout: long, stderr: long, exitCode: 1, command: "brew install --build-from-source foo"))

        let record = await h.coordinator.run(BrewMutation(.install(name: "foo", isCask: false)), context: h.context)

        for stored in [record.output, record.errorOutput] {
            #expect(stored.hasPrefix("[… 5014 earlier characters not kept …]\n"))
            #expect(stored.hasSuffix("xError: the end"))
            #expect(stored.count == "[… 5014 earlier characters not kept …]\n".count + limit)
        }
    }

    @Test("streamed output kept after a failure is truncated the same way")
    func streamedOutputIsTruncatedForStorage() async throws {
        let h = try Harness()
        let limit = ActionRecord.storedOutputLimit
        await h.service.configureMutations(
            outputChunks: [String(repeating: "y", count: limit + 99) + "\n"], error: BrewProcessError.timeout)

        let record = await h.coordinator.run(BrewMutation(.install(name: "foo", isCask: false)), context: h.context)

        #expect(record.output.hasPrefix("[… 100 earlier characters not kept …]\n"))
        #expect(record.output.count == "[… 100 earlier characters not kept …]\n".count + limit)
    }

    @Test("a failed uninstall leaves the package in the installed list")
    func failedUninstallKeepsPackage() async throws {
        let h = try Harness()
        await h.service.configureInstalledListings(formulas: [jq], leaves: ["jq"])
        await h.installed.refresh()
        await h.service.configureMutations(result: ProcessResult(
            stdout: "", stderr: "Error: Refusing to uninstall jq because it is required by gh", exitCode: 1,
            command: "brew uninstall jq"))

        await h.coordinator.run(BrewMutation(.uninstall(name: "jq", isCask: false)), context: h.context)

        #expect(h.installed.installedFormulas.map(\.name) == ["jq"])
    }

    @Test("a successful uninstall removes the package from the installed list")
    func successfulUninstallRemovesPackage() async throws {
        let h = try Harness()
        await h.service.configureInstalledListings(formulas: [jq], leaves: ["jq"])
        await h.installed.refresh()

        await h.coordinator.run(BrewMutation(.uninstall(name: "jq", isCask: false)), context: h.context)

        #expect(h.installed.installedFormulas.isEmpty)
    }

    @Test("upgrade-all re-reads installed state even when brew exits non-zero")
    func upgradeAllRefreshesAfterPartialFailure() async throws {
        let h = try Harness()
        await h.service.configureInstalledListings(formulas: [jq], outdated: [jqOutdated])
        await h.installed.refresh()
        #expect(h.installed.outdatedPackages.map(\.name) == ["jq"])
        // jq upgraded before another package failed.
        await h.service.configureInstalledListings(formulas: [jq], outdated: [])
        await h.service.configureMutations(result: ProcessResult(
            stdout: "", stderr: "Error: wget: download failed", exitCode: 1, command: "brew upgrade"))

        await h.coordinator.run(BrewMutation(.upgrade(target: .all)), context: h.context)

        #expect(h.installed.outdatedPackages.isEmpty)
    }
}

private func upgrade(_ name: String, isCask: Bool = false) -> BrewMutation {
    BrewMutation(.upgrade(target: .named(name: name, isCask: isCask)))
}

/// Releases whatever a wrong implementation started after a cancel, so a failing test
/// ends instead of hanging on a held mutation.
@MainActor
private func drainHeldMutations(_ service: MockBrewService) async {
    for _ in 0..<4 {
        try? await Task.sleep(for: .milliseconds(20))
        await service.releaseHeldMutation()
    }
}

@Suite("MutationCoordinator sequences", .timeLimit(.minutes(1)))
@MainActor
struct MutationSequenceTests {
    @Test("a sequence runs its mutations in order and reports progress")
    func sequenceReportsProgress() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)

        let run = Task {
            _ = await h.coordinator.runSequence([upgrade("jq"), upgrade("wget"), upgrade("gh")], context: h.context)
        }
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        #expect(h.coordinator.sequenceProgress == .init(completed: 0, total: 3, current: "jq"))

        await h.service.releaseHeldMutation()
        #expect(await eventually {
            let held = await h.service.heldMutationCount
            return held == 1 && h.coordinator.sequenceProgress?.completed == 1
        })
        #expect(h.coordinator.sequenceProgress == .init(completed: 1, total: 3, current: "wget"))

        await h.service.releaseHeldMutation()
        #expect(await eventually {
            let held = await h.service.heldMutationCount
            return held == 1 && h.coordinator.sequenceProgress?.completed == 2
        })
        await h.service.releaseHeldMutation()
        await run.value

        #expect(h.coordinator.sequenceProgress == nil)
        #expect(await h.service.upgradeCalls.map(\.name) == ["jq", "wget", "gh"])
        #expect(try h.records().map(\.status) == [.success, .success, .success])
    }

    @Test("cancelling a sequence stops the running step and skips the rest")
    func cancelStopsSequence() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)

        let run = Task {
            await h.coordinator.runSequence([upgrade("jq"), upgrade("wget"), upgrade("gh")], context: h.context)
                .map(\.id)
        }
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        run.cancel()
        await drainHeldMutations(h.service)
        let ids = await run.value

        #expect(ids.count == 1)
        #expect(await h.service.upgradeCalls.map(\.name) == ["jq"])
        #expect(try h.records().map(\.status) == [.cancelled])
    }

    @Test("cancelling a sequence still waiting for its turn runs none of its steps")
    func cancelQueuedSequence() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)
        let install = Task { _ = await h.coordinator.run(BrewMutation(.install(name: "big", isCask: false)), context: h.context) }
        #expect(await eventually { await h.service.heldMutationCount == 1 })

        let sequence = Task {
            await h.coordinator.runSequence([upgrade("x"), upgrade("y")], context: h.context)
                .map { "\($0.packageName):\($0.statusRaw)" }
        }
        #expect(await eventually { (try? h.records().count) == 2 })
        sequence.cancel()
        let steps = await sequence.value

        #expect(steps == ["x:cancelled"])
        await h.service.releaseHeldMutation()
        await install.value
        #expect(await h.service.upgradeCalls.isEmpty)
        #expect(await h.service.installCalls.map(\.name) == ["big"])
    }

    @Test("a failed step does not stop the rest of the sequence")
    func failureContinuesSequence() async throws {
        let h = try Harness()
        await h.service.configureMutations(result: ProcessResult(
            stdout: "", stderr: "Error: wget: download failed", exitCode: 1, command: "brew upgrade"))

        let records = await h.coordinator.runSequence([upgrade("jq"), upgrade("wget")], context: h.context)

        #expect(records.map(\.status) == [.failed, .failed])
        #expect(await h.service.upgradeCalls.map(\.name) == ["jq", "wget"])
    }

    @Test("a sequence started after a cancelled one runs in full")
    func cancelDoesNotLeakIntoNextSequence() async throws {
        let h = try Harness()
        await h.service.configureMutations(hold: true)
        let first = Task { _ = await h.coordinator.runSequence([upgrade("jq"), upgrade("wget")], context: h.context) }
        #expect(await eventually { await h.service.heldMutationCount == 1 })
        first.cancel()
        await drainHeldMutations(h.service)
        await first.value
        await h.service.configureMutations(hold: false)

        let records = await h.coordinator.runSequence([upgrade("gh"), upgrade("fd")], context: h.context)

        #expect(records.map(\.status) == [.success, .success])
    }

    @Test("a sequence prints each command before that step's output")
    func sequenceLabelsEachStep() async throws {
        let h = try Harness()
        await h.service.configureMutations(outputChunks: ["ok\n"])
        let log = OutputLog()

        await h.coordinator.runSequence(
            [upgrade("jq"), upgrade("rectangle", isCask: true)], context: h.context,
            onOutput: { log.chunks.append($0) })

        #expect(log.chunks == ["$ brew upgrade jq\n", "ok\n", "$ brew upgrade --cask rectangle\n", "ok\n"])
    }
}
