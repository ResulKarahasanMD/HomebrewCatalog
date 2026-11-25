import Foundation
import Observation

/// brew doctor, cleanup and autoremove. Cleanup and autoremove delete files and packages,
/// so each run needs a dry-run preview that found something, and a run spends it.
@Observable
@MainActor
final class MaintenanceFeatureStore {
    private(set) var doctorOutput = ""
    private(set) var isRunningDoctor = false
    /// The last `brew cleanup --dry-run`; nil until previewed, and again once cleanup ran.
    private(set) var cleanupPreview: CleanupPreview?
    /// The last `brew autoremove --dry-run`; nil until previewed, and again once autoremove ran.
    private(set) var autoremovePreview: AutoremovePreview?
    private(set) var isLoadingCleanupPreview = false
    private(set) var isLoadingAutoremovePreview = false
    private(set) var isRunningCleanup = false
    private(set) var isRunningAutoremove = false
    private(set) var error: String?

    var canRunCleanup: Bool {
        !isRunningCleanup && !(cleanupPreview?.isEmpty ?? true)
    }

    var canRunAutoremove: Bool {
        !isRunningAutoremove && !(autoremovePreview?.isEmpty ?? true)
    }

    private let service: any BrewService
    private let installed: InstalledFeatureStore
    private let redactor = OutputRedactor()

    init(service: any BrewService, installed: InstalledFeatureStore) {
        self.service = service
        self.installed = installed
    }

    // MARK: - Doctor

    func runDoctor() async {
        isRunningDoctor = true
        doctorOutput = ""
        do {
            let result = try await service.doctor()
            doctorOutput = redactor.redact(result.stdout + result.stderr)
        } catch {
            doctorOutput = "Error: \(redactor.redact(error.localizedDescription))"
        }
        isRunningDoctor = false
    }

    func clearDoctorOutput() {
        doctorOutput = ""
    }

    // MARK: - Cleanup

    func loadCleanupPreview() async {
        isLoadingCleanupPreview = true
        error = nil
        do {
            let result = try await service.cleanupDryRun()
            cleanupPreview = CleanupPreview(output: redactor.redact(result.stdout + result.stderr))
        } catch {
            cleanupPreview = nil
            self.error = redactor.redact(error.localizedDescription)
        }
        isLoadingCleanupPreview = false
    }

    func clearCleanupPreview() {
        cleanupPreview = nil
    }

    /// Runs `brew cleanup` if a preview found something to remove. Returns false, and
    /// runs nothing, otherwise.
    @discardableResult
    func runCleanup(onOutput: (@MainActor (String) -> Void)? = nil) async -> Bool {
        guard canRunCleanup else {
            error = "Preview the cleanup first. It runs only after a dry run that found something to remove."
            return false
        }
        isRunningCleanup = true
        error = nil
        await runDestructive(onOutput: onOutput) { try await self.service.cleanup(onOutput: $0) }
        // What the preview listed no longer matches the disk.
        cleanupPreview = nil
        isRunningCleanup = false
        return true
    }

    // MARK: - Autoremove

    func loadAutoremovePreview() async {
        isLoadingAutoremovePreview = true
        error = nil
        do {
            let result = try await service.autoremoveDryRun()
            autoremovePreview = AutoremovePreview(output: redactor.redact(result.stdout + result.stderr))
        } catch {
            autoremovePreview = nil
            self.error = redactor.redact(error.localizedDescription)
        }
        isLoadingAutoremovePreview = false
    }

    func clearAutoremovePreview() {
        autoremovePreview = nil
    }

    /// Runs `brew autoremove` if a preview listed formulae to remove, then re-reads
    /// installed packages. Returns false, and runs nothing, otherwise.
    @discardableResult
    func runAutoremove(onOutput: (@MainActor (String) -> Void)? = nil) async -> Bool {
        guard canRunAutoremove else {
            error = "Preview autoremove first. It runs only after a dry run that listed formulae to remove."
            return false
        }
        isRunningAutoremove = true
        error = nil
        await runDestructive(onOutput: onOutput) { try await self.service.autoremove(onOutput: $0) }
        autoremovePreview = nil
        isRunningAutoremove = false
        await installed.refresh()
        return true
    }

    private func runDestructive(
        onOutput: (@MainActor (String) -> Void)?,
        _ command: (_ onOutput: @escaping @Sendable (String) -> Void) async throws -> ProcessResult
    ) async {
        do {
            let result = try await OrderedOutput.run(sink: { onOutput?($0) }, command)
            if result.exitCode != 0 {
                error = redactor.redact(result.stderr.isEmpty ? result.stdout : result.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            self.error = redactor.redact(error.localizedDescription)
        }
    }
}
