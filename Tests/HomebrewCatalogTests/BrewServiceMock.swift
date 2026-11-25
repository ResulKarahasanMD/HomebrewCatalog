import Foundation
@testable import HomebrewCatalog

actor MockBrewService: BrewService {
    struct RunCall: Sendable, Equatable {
        let arguments: [String]
        let timeout: TimeInterval
        let hasOnOutput: Bool
    }

    struct PackageCall: Sendable, Equatable {
        let name: String
        let isCask: Bool
    }

    struct UpgradeCall: Sendable, Equatable {
        let name: String?
        let isCask: Bool
    }

    // MARK: - Recorded Calls

    var runCalls: [RunCall] = []
    var installCalls: [PackageCall] = []
    var uninstallCalls: [PackageCall] = []
    var upgradeCalls: [UpgradeCall] = []
    var reinstallCalls: [PackageCall] = []
    var pinCalls: [String] = []
    var unpinCalls: [String] = []
    var reverseDependencyCalls: [(name: String, installed: Bool)] = []
    var serviceStartCalls: [String] = []
    var serviceStopCalls: [String] = []
    var serviceRestartCalls: [String] = []
    var addTapCalls: [String] = []
    var removeTapCalls: [String] = []
    var setCustomBrewPathCalls: [String] = []
    var invalidateBrewPathCount = 0
    var listInstalledFormulasCount = 0
    var listInstalledCasksCount = 0
    var listOutdatedCount = 0
    var listPinnedCount = 0
    var listLeavesCount = 0
    var infoInstalledFormulaCount = 0
    var infoInstalledCaskCount = 0

    // MARK: - Canned Responses

    var cannedBrewPath: String = "/opt/homebrew/bin/brew"
    var shouldThrowOnResolvePath: BrewProcessError?
    var cannedRunResult = ProcessResult(stdout: "", stderr: "", exitCode: 0, command: "")
    var cannedInstalledFormulas: [InstalledFormulaInfo] = []
    var cannedInstalledCasks: [InstalledCaskInfo] = []
    var cannedOutdated: [OutdatedInfo] = []
    var cannedPinned: [String] = []
    var cannedLeaves: [String] = []
    var cannedReverseDependencies: [String] = []
    var cannedServices: [BrewServiceInfo] = []
    var cannedTaps: [BrewTapInfo] = []
    var cannedBrewEnvironmentInfo = BrewEnvironmentInfo()
    var installedFormulasError: Error?
    var installedCasksError: Error?
    var outdatedError: Error?
    var pinnedError: Error?
    var leavesError: Error?
    var infoFormulaError: Error?
    var infoCaskError: Error?
    var listingDelayNanoseconds: UInt64 = 0
    private var activeListingCalls = 0
    private(set) var maxConcurrentListingCalls = 0

    // MARK: - Mutation Behaviour

    var upgradeNamesCalls: [[String]] = []
    /// Streamed through `onOutput`, one call per element, before the mutation returns.
    var mutationOutputChunks: [String] = []
    var mutationError: Error?
    /// When set, every mutation suspends until `releaseHeldMutation()` or the cancellation
    /// of the task that started it.
    var holdsMutations = false
    private var heldMutations: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []
    private var activeMutations = 0
    private(set) var maxConcurrentMutations = 0

    var heldMutationCount: Int { heldMutations.count }

    // MARK: - Services, Taps, Maintenance

    var listServicesCount = 0
    var listTapsCount = 0
    var cleanupCalls = 0
    var autoremoveCalls = 0
    var cannedCleanupDryRun = ProcessResult(stdout: "", stderr: "", exitCode: 0, command: "brew cleanup --dry-run")
    var cannedAutoremoveDryRun = ProcessResult(stdout: "", stderr: "", exitCode: 0, command: "brew autoremove --dry-run")
    var dryRunError: Error?

    func configureDryRuns(cleanup: String = "", autoremove: String = "", error: Error? = nil) {
        cannedCleanupDryRun = ProcessResult(stdout: cleanup, stderr: "", exitCode: 0, command: "brew cleanup --dry-run")
        cannedAutoremoveDryRun = ProcessResult(
            stdout: autoremove, stderr: "", exitCode: 0, command: "brew autoremove --dry-run")
        dryRunError = error
    }

    func configureServices(_ services: [BrewServiceInfo]) {
        cannedServices = services
    }

    func configureTaps(_ taps: [BrewTapInfo]) {
        cannedTaps = taps
    }

    // MARK: - Test Configuration

    func configureInstalledListings(
        formulas: [InstalledFormulaInfo] = [],
        casks: [InstalledCaskInfo] = [],
        outdated: [OutdatedInfo] = [],
        pinned: [String] = [],
        leaves: [String] = []
    ) {
        cannedInstalledFormulas = formulas
        cannedInstalledCasks = casks
        cannedOutdated = outdated
        cannedPinned = pinned
        cannedLeaves = leaves
    }

    func configureListingErrors(
        formulas: Error? = nil,
        casks: Error? = nil,
        outdated: Error? = nil,
        pinned: Error? = nil,
        leaves: Error? = nil
    ) {
        installedFormulasError = formulas
        installedCasksError = casks
        outdatedError = outdated
        pinnedError = pinned
        leavesError = leaves
    }

    func configureListingDelay(nanoseconds: UInt64) {
        listingDelayNanoseconds = nanoseconds
    }

    func configureMutations(
        result: ProcessResult? = nil,
        outputChunks: [String] = [],
        error: Error? = nil,
        hold: Bool = false
    ) {
        if let result { cannedRunResult = result }
        mutationOutputChunks = outputChunks
        mutationError = error
        holdsMutations = hold
    }

    func releaseHeldMutation() {
        guard !heldMutations.isEmpty else { return }
        heldMutations.removeFirst().continuation.resume()
    }

    private func releaseCancelledMutation(_ id: UUID) {
        guard let index = heldMutations.firstIndex(where: { $0.id == id }) else { return }
        heldMutations.remove(at: index).continuation.resume()
    }

    /// Mirrors the live service: a command whose task is cancelled throws `.cancelled`.
    private func performMutation(
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        activeMutations += 1
        maxConcurrentMutations = max(maxConcurrentMutations, activeMutations)
        defer { activeMutations -= 1 }

        for chunk in mutationOutputChunks {
            onOutput?(chunk)
        }
        if holdsMutations {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { heldMutations.append((id, $0)) }
            } onCancel: {
                Task { await self.releaseCancelledMutation(id) }
            }
        }
        if Task.isCancelled { throw BrewProcessError.cancelled }
        if let mutationError { throw mutationError }
        return cannedRunResult
    }

    private func trackListingCall<T>(_ operation: () async throws -> T) async throws -> T {
        activeListingCalls += 1
        maxConcurrentListingCalls = max(maxConcurrentListingCalls, activeListingCalls)
        defer { activeListingCalls -= 1 }
        return try await operation()
    }

    // MARK: - Path Management

    func resolveBrewPath() async throws -> String {
        if let err = shouldThrowOnResolvePath { throw err }
        return cannedBrewPath
    }

    func setCustomBrewPath(_ path: String) async {
        setCustomBrewPathCalls.append(path)
        cannedBrewPath = path
    }

    func invalidateBrewPath() async {
        invalidateBrewPathCount += 1
    }

    func currentBrewPath() async -> String? {
        return cannedBrewPath
    }

    // MARK: - Core Execution

    func run(_ arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        runCalls.append(RunCall(arguments: arguments, timeout: timeout, hasOnOutput: false))
        return cannedRunResult
    }

    func run(
        _ arguments: [String],
        timeout: TimeInterval,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        runCalls.append(RunCall(arguments: arguments, timeout: timeout, hasOnOutput: true))
        if !cannedRunResult.stdout.isEmpty {
            onOutput(cannedRunResult.stdout)
        }
        return cannedRunResult
    }

    // MARK: - Listings

    func listInstalledFormulas() async throws -> [InstalledFormulaInfo] {
        try await trackListingCall {
            if listingDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: listingDelayNanoseconds)
            }
            listInstalledFormulasCount += 1
            if let installedFormulasError { throw installedFormulasError }
            return cannedInstalledFormulas
        }
    }

    func listInstalledCasks() async throws -> [InstalledCaskInfo] {
        try await trackListingCall {
            if listingDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: listingDelayNanoseconds)
            }
            listInstalledCasksCount += 1
            if let installedCasksError { throw installedCasksError }
            return cannedInstalledCasks
        }
    }

    func listOutdated() async throws -> [OutdatedInfo] {
        if listingDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: listingDelayNanoseconds)
        }
        listOutdatedCount += 1
        if let outdatedError { throw outdatedError }
        return cannedOutdated
    }

    func listPinned() async throws -> [String] {
        if listingDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: listingDelayNanoseconds)
        }
        listPinnedCount += 1
        if let pinnedError { throw pinnedError }
        return cannedPinned
    }

    func listLeaves() async throws -> [String] {
        try await trackListingCall {
            if listingDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: listingDelayNanoseconds)
            }
            listLeavesCount += 1
            if let leavesError { throw leavesError }
            return cannedLeaves
        }
    }

    func infoInstalledFormula(name: String) async throws -> InstalledFormulaInfo? {
        infoInstalledFormulaCount += 1
        if let infoFormulaError { throw infoFormulaError }
        return cannedInstalledFormulas.first { $0.name == name }
    }

    func infoInstalledCask(name: String) async throws -> InstalledCaskInfo? {
        infoInstalledCaskCount += 1
        if let infoCaskError { throw infoCaskError }
        return cannedInstalledCasks.first { $0.token == name || $0.name == name }
    }

    // MARK: - Package Operations

    func install(
        name: String,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        installCalls.append(PackageCall(name: name, isCask: isCask))
        return try await performMutation(onOutput: onOutput)
    }

    func uninstall(
        name: String,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        uninstallCalls.append(PackageCall(name: name, isCask: isCask))
        return try await performMutation(onOutput: onOutput)
    }

    func upgrade(
        name: String?,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        upgradeCalls.append(UpgradeCall(name: name, isCask: isCask))
        return try await performMutation(onOutput: onOutput)
    }

    func upgrade(
        names: [String],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        upgradeNamesCalls.append(names)
        return try await performMutation(onOutput: onOutput)
    }

    func reinstall(
        name: String,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        reinstallCalls.append(PackageCall(name: name, isCask: isCask))
        return try await performMutation(onOutput: onOutput)
    }

    func pin(name: String) async throws -> ProcessResult {
        pinCalls.append(name)
        return try await performMutation(onOutput: nil)
    }

    func unpin(name: String) async throws -> ProcessResult {
        unpinCalls.append(name)
        return try await performMutation(onOutput: nil)
    }

    func reverseDependencies(name: String, installed: Bool) async throws -> [String] {
        reverseDependencyCalls.append((name, installed))
        return cannedReverseDependencies
    }

    // MARK: - Services

    func listServices() async throws -> [BrewServiceInfo] {
        listServicesCount += 1
        return cannedServices
    }

    func startService(name: String) async throws -> ProcessResult {
        serviceStartCalls.append(name)
        return try await performMutation(onOutput: nil)
    }

    func stopService(name: String) async throws -> ProcessResult {
        serviceStopCalls.append(name)
        return try await performMutation(onOutput: nil)
    }

    func restartService(name: String) async throws -> ProcessResult {
        serviceRestartCalls.append(name)
        return try await performMutation(onOutput: nil)
    }

    // MARK: - Taps

    func listTaps() async throws -> [BrewTapInfo] {
        listTapsCount += 1
        return cannedTaps
    }

    func addTap(
        name: String,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        addTapCalls.append(name)
        return cannedRunResult
    }

    func removeTap(name: String) async throws -> ProcessResult {
        removeTapCalls.append(name)
        return cannedRunResult
    }

    // MARK: - Maintenance

    func doctor() async throws -> ProcessResult {
        return cannedRunResult
    }

    func cleanupDryRun() async throws -> ProcessResult {
        if let dryRunError { throw dryRunError }
        return cannedCleanupDryRun
    }

    func cleanup(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        cleanupCalls += 1
        return try await performMutation(onOutput: onOutput)
    }

    func autoremoveDryRun() async throws -> ProcessResult {
        if let dryRunError { throw dryRunError }
        return cannedAutoremoveDryRun
    }

    func autoremove(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        autoremoveCalls += 1
        return try await performMutation(onOutput: onOutput)
    }

    func brewInfo() async throws -> BrewEnvironmentInfo {
        return cannedBrewEnvironmentInfo
    }
}
