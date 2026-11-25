import Foundation
import Observation
import SwiftData

/// Runs every brew command that changes installed state. Commands run one at a time,
/// because brew holds a lock while it installs, and each run leaves an `ActionRecord`
/// that carries the mutation so it can be retried exactly. A run is cancelled by
/// cancelling the task that called `run` or `runSequence`; that stops only its own command.
@Observable
@MainActor
final class MutationCoordinator {
    /// True while a mutation is running or waiting for its turn.
    private(set) var isRunning = false
    /// Redacted output of the running mutation, or of the last one.
    private(set) var currentOutput = ""

    private let service: any BrewService
    private let installed: InstalledFeatureStore
    private let redactor = OutputRedactor()
    private var waitingTurns: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    init(service: any BrewService, installed: InstalledFeatureStore) {
        self.service = service
        self.installed = installed
    }

    /// Records the mutation as pending, runs it once earlier ones finish, and updates
    /// installed state. Failures are recorded on the returned record, never thrown. If the
    /// calling task is cancelled the record ends as cancelled; while still waiting for its
    /// turn, the command never starts.
    @discardableResult
    func run(
        _ mutation: BrewMutation,
        context: ModelContext,
        onOutput: (@MainActor (String) -> Void)? = nil
    ) async -> ActionRecord {
        let record = ActionRecord(mutation: mutation)
        context.insert(record)
        try? context.save()

        guard await waitForTurn() else {
            record.status = .cancelled
            record.completedAt = Date()
            try? context.save()
            return record
        }
        defer { finishTurn() }

        record.status = .running
        record.startedAt = Date()
        try? context.save()
        currentOutput = ""

        let outcome: Result<ProcessResult, any Error> =
            Task.isCancelled ? .failure(CancellationError()) : await execute(mutation.op, onOutput: onOutput)
        switch outcome {
        case .success(let result):
            record.output = ActionRecord.storable(redactor.redact(result.stdout))
            record.errorOutput = ActionRecord.storable(redactor.redact(result.stderr))
            record.exitCode = result.exitCode
            record.status = result.exitCode == 0 ? .success : .failed
        case .failure(let error):
            record.output = ActionRecord.storable(currentOutput)
            record.errorOutput = ActionRecord.storable(redactor.redact(error.localizedDescription))
            record.exitCode = -1
            record.status = Self.isCancellation(error) ? .cancelled : .failed
        }
        record.completedAt = Date()
        try? context.save()

        // A cancelled caller would cancel the brew listings this runs, so it gets its own task.
        let succeeded = record.status == .success
        await Task { await refreshInstalledState(after: mutation.op, succeeded: succeeded) }.value
        return record
    }

    struct SequenceProgress: Equatable, Sendable {
        let completed: Int
        let total: Int
        /// Package of the step running now.
        let current: String
    }

    /// Set while `runSequence` is working through its steps.
    private(set) var sequenceProgress: SequenceProgress?

    /// Runs the mutations one after another, printing each command before its output.
    /// A failed step does not stop the rest; cancelling the calling task stops the running
    /// step and skips the ones after it. Returns the records of the steps that ran.
    @discardableResult
    func runSequence(
        _ mutations: [BrewMutation],
        context: ModelContext,
        onOutput: (@MainActor (String) -> Void)? = nil
    ) async -> [ActionRecord] {
        defer { sequenceProgress = nil }

        var records: [ActionRecord] = []
        for (index, mutation) in mutations.enumerated() {
            if Task.isCancelled { break }
            sequenceProgress = SequenceProgress(
                completed: index, total: mutations.count, current: mutation.op.packageName)
            onOutput?("$ brew \(mutation.op.brewArguments.joined(separator: " "))\n")
            records.append(await run(mutation, context: context, onOutput: onOutput))
        }
        return records
    }

    // MARK: - Turns

    /// True once it is this run's turn; false if the calling task was cancelled while it
    /// waited, in which case the run does not hold the turn.
    private func waitForTurn() async -> Bool {
        guard isRunning else {
            isRunning = true
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waitingTurns.append((id, continuation))
                }
            }
        } onCancel: {
            Task { @MainActor in self.abandonTurn(id) }
        }
    }

    private func abandonTurn(_ id: UUID) {
        guard let index = waitingTurns.firstIndex(where: { $0.id == id }) else { return }
        waitingTurns.remove(at: index).continuation.resume(returning: false)
    }

    private func finishTurn() {
        if waitingTurns.isEmpty {
            isRunning = false
        } else {
            waitingTurns.removeFirst().continuation.resume(returning: true)
        }
    }

    // MARK: - Execution

    private func execute(
        _ op: BrewMutation.Op,
        onOutput: (@MainActor (String) -> Void)?
    ) async -> Result<ProcessResult, any Error> {
        do {
            let result = try await OrderedOutput.run(sink: { [self] line in
                currentOutput += line
                onOutput?(line)
            }) { try await perform(op, onOutput: $0) }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    private func perform(
        _ op: BrewMutation.Op,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        switch op {
        case .install(let name, let isCask):
            try await service.install(name: name, isCask: isCask, onOutput: onOutput)
        case .uninstall(let name, let isCask):
            try await service.uninstall(name: name, isCask: isCask, onOutput: onOutput)
        case .upgrade(.all):
            try await service.upgrade(names: [], onOutput: onOutput)
        case .upgrade(.named(let name, let isCask)):
            try await service.upgrade(name: name, isCask: isCask, onOutput: onOutput)
        case .reinstall(let name, let isCask):
            try await service.reinstall(name: name, isCask: isCask, onOutput: onOutput)
        case .pin(let name):
            try await service.pin(name: name)
        case .unpin(let name):
            try await service.unpin(name: name)
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if case BrewProcessError.cancelled = error { return true }
        return false
    }

    // MARK: - Installed State

    private func refreshInstalledState(after op: BrewMutation.Op, succeeded: Bool) async {
        switch op {
        case .upgrade(.all):
            // Some packages may have upgraded before a later one failed, so re-read
            // installed state whatever the exit code.
            await installed.refresh()
        case .install(let name, let isCask), .uninstall(let name, let isCask), .reinstall(let name, let isCask),
            .upgrade(.named(let name, let isCask)):
            await applyIfSucceeded(op, name: name, isCask: isCask, succeeded: succeeded)
        case .pin(let name), .unpin(let name):
            await applyIfSucceeded(op, name: name, isCask: false, succeeded: succeeded)
        }
    }

    /// A failed single-package command leaves the package as it was, so the list stays.
    private func applyIfSucceeded(_ op: BrewMutation.Op, name: String, isCask: Bool, succeeded: Bool) async {
        guard succeeded else { return }
        let patched = await installed.applyIncrementalUpdate(action: op.verb, packageName: name, isCask: isCask)
        if !patched {
            await installed.refresh()
        }
    }
}
