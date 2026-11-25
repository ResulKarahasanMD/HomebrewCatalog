import Foundation

protocol BrewService: Sendable {
    func resolveBrewPath() async throws -> String
    func setCustomBrewPath(_ path: String) async
    func invalidateBrewPath() async
    func currentBrewPath() async -> String?

    func run(_ arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
    func run(
        _ arguments: [String],
        timeout: TimeInterval,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult

    func listInstalledFormulas() async throws -> [InstalledFormulaInfo]
    func listInstalledCasks() async throws -> [InstalledCaskInfo]
    func listOutdated() async throws -> [OutdatedInfo]
    func listPinned() async throws -> [String]
    func listLeaves() async throws -> [String]

    func infoInstalledFormula(name: String) async throws -> InstalledFormulaInfo?
    func infoInstalledCask(name: String) async throws -> InstalledCaskInfo?

    func install(
        name: String,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult
    func uninstall(
        name: String,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult
    func upgrade(
        name: String?,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult
    /// Upgrades the given formulae/casks in one invocation; an empty list upgrades everything.
    func upgrade(
        names: [String],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult
    func reinstall(
        name: String,
        isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult
    func pin(name: String) async throws -> ProcessResult
    func unpin(name: String) async throws -> ProcessResult

    func reverseDependencies(name: String, installed: Bool) async throws -> [String]

    func listServices() async throws -> [BrewServiceInfo]
    func startService(name: String) async throws -> ProcessResult
    func stopService(name: String) async throws -> ProcessResult
    func restartService(name: String) async throws -> ProcessResult

    func listTaps() async throws -> [BrewTapInfo]
    func addTap(
        name: String,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult
    func removeTap(name: String) async throws -> ProcessResult

    func doctor() async throws -> ProcessResult
    func cleanupDryRun() async throws -> ProcessResult
    func cleanup(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult
    func autoremoveDryRun() async throws -> ProcessResult
    func autoremove(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult

    func brewInfo() async throws -> BrewEnvironmentInfo
}

extension BrewService {
    func run(_ arguments: [String]) async throws -> ProcessResult {
        try await run(arguments, timeout: 300)
    }

    func reverseDependencies(name: String) async throws -> [String] {
        try await reverseDependencies(name: name, installed: false)
    }

    func upgrade(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        try await upgrade(name: nil, isCask: false, onOutput: onOutput)
    }

    func upgrade(
        names: [String],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        try await run(["upgrade"] + names, timeout: 1800, onOutput: onOutput)
    }
}

extension BrewProcessService: BrewService {}
