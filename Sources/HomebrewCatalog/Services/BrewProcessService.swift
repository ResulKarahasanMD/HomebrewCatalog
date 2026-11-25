@preconcurrency import Foundation

// MARK: - Process Result

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let command: String
}

// MARK: - Errors

enum BrewProcessError: Error, LocalizedError {
    case brewNotFound
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case parseError(String)
    case cancelled
    /// A name that is not a valid package, service or tap name; nothing was run.
    case invalidArgument(kind: String, value: String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew not found. Please install Homebrew or configure the correct path in Settings."
        case .executionFailed(let code, let stderr):
            return "Command failed (exit \(code)): \(stderr)"
        case .timeout:
            return "Command timed out."
        case .parseError(let detail):
            return "Failed to parse output: \(detail)"
        case .cancelled:
            return "Command was cancelled."
        case .invalidArgument(let kind, let value):
            return "Refused to run brew: \"\(value)\" is not a valid \(kind) name."
        }
    }
}

// MARK: - JSON Helpers

/// Decodes Homebrew fields that may be either a single string or a string array.
private struct FlexibleStringList: Decodable, Sendable {
    let values: [String]

    var first: String? { values.first }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            values = [string]
        } else if let array = try? container.decode([String].self) {
            values = array
        } else {
            values = []
        }
    }
}

// MARK: - Service

actor BrewProcessService {
    static let shared = BrewProcessService()

    private var brewPath: String?

    // MARK: - Brew Path Resolution

    static let allowedBrewPrefixes: Set<String> = [
        "/opt/homebrew",
        "/usr/local",
    ]

    func resolveBrewPath() async throws -> String {
        if let cached = brewPath {
            return cached
        }

        var customPath = UserDefaults.standard.string(forKey: "customBrewPath")
        if let custom = customPath, !custom.isEmpty,
            !Self.isAllowedBrewPath(custom, customOverride: custom)
        {
            UserDefaults.standard.removeObject(forKey: "customBrewPath")
            customPath = nil
        }

        let candidates = [
            customPath,
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ].compactMap { $0 }.filter { !$0.isEmpty }

        for path in candidates {
            if Self.isAllowedBrewPath(path, customOverride: customPath) {
                brewPath = path
                return path
            }
        }

        if let whichResult = try? await runRaw(
            executable: "/usr/bin/which", arguments: ["brew"], timeout: 5
        ) {
            let path = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAllowedBrewPath(path, customOverride: customPath) {
                brewPath = path
                return path
            }
        }

        throw BrewProcessError.brewNotFound
    }

    static func isAllowedBrewPath(_ path: String, customOverride: String?) -> Bool {
        guard !path.isEmpty else { return false }
        let resolved = URL(fileURLWithPath: (path as NSString).standardizingPath)
            .resolvingSymlinksInPath()
        let resolvedPath = resolved.path
        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else { return false }

        let grandparent = resolved.deletingLastPathComponent().deletingLastPathComponent().path
        if allowedBrewPrefixes.contains(grandparent) { return true }

        // Outside the standard prefixes only the user's own override is considered, and
        // only when it looks like a Homebrew prefix that other users cannot modify.
        if let override = customOverride, !override.isEmpty, path == override {
            return isTrustworthyCustomBrew(
                resolved: resolved, given: URL(fileURLWithPath: (path as NSString).standardizingPath))
        }

        return false
    }

    /// gid of `admin`, the group Homebrew's installer makes its directories writable by.
    private static let adminGroupID: UInt32 = 80

    /// True when a file-system entry on the way to a custom brew cannot be replaced by
    /// another unprivileged user: owned by root or the current user, never world-writable,
    /// and group-writable only for directories of the `admin` group (Homebrew's own layout).
    static func isTrustedOwnership(
        mode: Int, owner: UInt32, group: UInt32, isDirectory: Bool, currentUser: UInt32 = getuid()
    ) -> Bool {
        guard owner == 0 || owner == currentUser else { return false }
        guard mode & 0o002 == 0 else { return false }
        if mode & 0o020 != 0 {
            return isDirectory && group == adminGroupID
        }
        return true
    }

    private static func hasTrustedOwnership(_ url: URL, isDirectory: Bool) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue,
            let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value,
            let group = (attrs[.groupOwnerAccountID] as? NSNumber)?.uint32Value
        else { return false }
        return isTrustedOwnership(mode: mode, owner: owner, group: group, isDirectory: isDirectory)
    }

    /// A custom brew must be a file named `brew` inside a Homebrew prefix
    /// (`<prefix>/bin/brew` next to `<prefix>/Library/Homebrew/brew.sh`) whose file,
    /// `bin` directory and prefix pass `isTrustedOwnership`. `given` is the path as typed:
    /// when it is a symlink, the directory holding the link is held to the same rule.
    static func isTrustworthyCustomBrew(resolved: URL, given: URL) -> Bool {
        guard resolved.lastPathComponent == "brew", given.lastPathComponent == "brew" else { return false }
        let bin = resolved.deletingLastPathComponent()
        let prefix = bin.deletingLastPathComponent()
        guard hasTrustedOwnership(resolved, isDirectory: false),
            hasTrustedOwnership(bin, isDirectory: true),
            hasTrustedOwnership(prefix, isDirectory: true)
        else { return false }
        let givenDirectory = given.deletingLastPathComponent()
        if givenDirectory.path != bin.path, !hasTrustedOwnership(givenDirectory, isDirectory: true) {
            return false
        }
        return FileManager.default.fileExists(
            atPath: prefix.appendingPathComponent("Library/Homebrew/brew.sh").path)
    }

    func setCustomBrewPath(_ path: String) {
        guard Self.isAllowedBrewPath(path, customOverride: path) else { return }
        brewPath = path
        UserDefaults.standard.set(path, forKey: "customBrewPath")
    }

    func invalidateBrewPath() {
        brewPath = nil
    }

    /// Drops the stored override so the next resolve searches the standard locations.
    func clearCustomBrewPath() {
        UserDefaults.standard.removeObject(forKey: "customBrewPath")
        brewPath = nil
    }

    func clearInvalidCustomBrewPathIfNeeded() {
        guard let custom = UserDefaults.standard.string(forKey: "customBrewPath"),
            !custom.isEmpty
        else { return }
        if !Self.isAllowedBrewPath(custom, customOverride: custom) {
            UserDefaults.standard.removeObject(forKey: "customBrewPath")
            brewPath = nil
        }
    }

    func currentBrewPath() async -> String? {
        return try? await resolveBrewPath()
    }

    // MARK: - Core Execution

    /// Runs an arbitrary executable through the shared pipe-draining process runner (tests only).
    internal func runExecutableForTests(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 30
    ) async throws -> ProcessResult {
        try await runProcess(
            executable: executable, arguments: arguments, timeout: timeout, onOutput: nil
        )
    }

    func run(_ arguments: [String], timeout: TimeInterval = 300) async throws -> ProcessResult {
        let path = try await resolveBrewPath()
        return try await runRaw(executable: path, arguments: arguments, timeout: timeout)
    }

    func run(
        _ arguments: [String],
        timeout: TimeInterval = 300,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        let path = try await resolveBrewPath()
        return try await runRawStreaming(
            executable: path, arguments: arguments, timeout: timeout, onOutput: onOutput
        )
    }

    private func runRaw(
        executable: String, arguments: [String], timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await runProcess(
            executable: executable, arguments: arguments, timeout: timeout, onOutput: nil
        )
    }

    private func runRawStreaming(
        executable: String, arguments: [String], timeout: TimeInterval,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        try await runProcess(
            executable: executable, arguments: arguments, timeout: timeout, onOutput: onOutput
        )
    }

    /// Runs a subprocess and drains stdout/stderr while it runs to avoid pipe-buffer deadlocks.
    private func runProcess(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = Self.processEnvironment(forExecutable: executable)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let cause = TerminationCause()

        let commandString = ([executable] + arguments).joined(separator: " ")
        let collector = OutputCollector()
        let (stream, streamContinuation) = AsyncStream<(String, OutputCollector.Stream)>.makeStream()

        let drainTask = Task {
            for await (chunk, kind) in stream {
                await collector.append(chunk, to: kind)
                onOutput?(chunk)
            }
        }

        let emitChunk: @Sendable (String, OutputCollector.Stream) -> Void = { chunk, kind in
            streamContinuation.yield((chunk, kind))
        }

        // A pipe read can end inside a multi-byte character; each stream's decoder keeps
        // those bytes for the next read instead of failing to decode the whole read.
        let stdoutDecoder = UTF8ChunkDecoder()
        let stderrDecoder = UTF8ChunkDecoder()
        let emitData: @Sendable (Data, UTF8ChunkDecoder, OutputCollector.Stream) -> Void = { data, decoder, kind in
            let str = decoder.decode(data)
            if !str.isEmpty { emitChunk(str, kind) }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            emitData(data, stdoutDecoder, .stdout)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            emitData(data, stderrDecoder, .stderr)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resumeGate = ProcessResumeGate(continuation: continuation)

                let timeoutTask = DispatchWorkItem {
                    if process.isRunning {
                        cause.record(.timeout)
                        process.terminate()
                    }
                }

                // Already cancelled: don't launch a command nobody is waiting for.
                if Task.isCancelled || cause.reason == .cancelled {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    streamContinuation.finish()
                    drainTask.cancel()
                    resumeGate.resumeOnce(with: .failure(BrewProcessError.cancelled))
                    return
                }

                DispatchQueue.global().asyncAfter(
                    deadline: .now() + timeout, execute: timeoutTask)

                process.terminationHandler = { proc in
                    timeoutTask.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    // readToEnd() throws a Swift error where readDataToEndOfFile() raises an
                    // uncatchable NSException if the handle is already closed (BUG-02).
                    for (pipe, decoder, kind) in [
                        (stdoutPipe, stdoutDecoder, OutputCollector.Stream.stdout),
                        (stderrPipe, stderrDecoder, .stderr),
                    ] {
                        if let remaining = try? pipe.fileHandleForReading.readToEnd() {
                            emitData(remaining, decoder, kind)
                        }
                        let rest = decoder.finish()
                        if !rest.isEmpty { emitChunk(rest, kind) }
                    }
                    streamContinuation.finish()

                    Task {
                        _ = await drainTask.value
                        let snap = await collector.snapshot()

                        // This Task is unstructured, so Task.isCancelled here never sees the
                        // caller's cancellation; the recorded cause says why we killed it.
                        switch cause.reason {
                        case .cancelled:
                            resumeGate.resumeOnce(with: .failure(BrewProcessError.cancelled))
                        case .timeout:
                            resumeGate.resumeOnce(with: .failure(BrewProcessError.timeout))
                        case nil where proc.terminationReason == .uncaughtSignal:
                            // Killed by a signal we did not send: report it, not as a timeout.
                            resumeGate.resumeOnce(
                                with: .failure(
                                    BrewProcessError.executionFailed(
                                        exitCode: proc.terminationStatus, stderr: snap.stderr)))
                        case nil:
                            resumeGate.resumeOnce(
                                with: .success(
                                    ProcessResult(
                                        stdout: snap.stdout,
                                        stderr: snap.stderr,
                                        exitCode: proc.terminationStatus,
                                        command: commandString
                                    )))
                        }
                    }
                }

                do {
                    try process.run()
                    // Cancelled between the check above and launch: stop it now.
                    if cause.reason == .cancelled {
                        process.terminate()
                    }
                } catch {
                    timeoutTask.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    streamContinuation.finish()
                    drainTask.cancel()
                    resumeGate.resumeOnce(
                        with: .failure(
                            BrewProcessError.executionFailed(
                                exitCode: -1, stderr: error.localizedDescription)))
                }
            }
        } onCancel: {
            cause.record(.cancelled)
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func processEnvironment(forExecutable executable: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewPrefix =
            URL(fileURLWithPath: executable)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let binPath = "\(brewPrefix)/bin:\(brewPrefix)/sbin"
        env["PATH"] = "\(binPath):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        return env
    }

    // MARK: - Installed Packages

    func listInstalledFormulas() async throws -> [InstalledFormulaInfo] {
        let result = try await run(["info", "--installed", "--json=v2", "--formula"], timeout: 60)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return try Self.parseInstalledFormulas(result.stdout)
    }

    func listInstalledCasks() async throws -> [InstalledCaskInfo] {
        let result = try await run(["info", "--installed", "--json=v2", "--cask"], timeout: 60)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return try Self.parseInstalledCasks(result.stdout)
    }

    func listOutdated() async throws -> [OutdatedInfo] {
        let result = try await run(["outdated", "--json=v2"], timeout: 60)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return try Self.parseOutdated(result.stdout)
    }

    func listPinned() async throws -> [String] {
        let result = try await run(["list", "--pinned"], timeout: 30)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return Self.parseLineSeparatedNames(result.stdout)
    }

    func listLeaves() async throws -> [String] {
        let result = try await run(["leaves"], timeout: 30)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return Self.parseLineSeparatedNames(result.stdout)
    }

    func infoInstalledFormula(name: String) async throws -> InstalledFormulaInfo? {
        let result = try await run(
            try BrewArguments.named(["info", "--json=v2"], names: [name]), timeout: 30)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        let formulas = try await Self.parseInstalledFormulasDetached(result.stdout)
        return formulas.first { $0.name == name } ?? formulas.first
    }

    func infoInstalledCask(name: String) async throws -> InstalledCaskInfo? {
        let result = try await run(
            try BrewArguments.named(["info", "--json=v2", "--cask"], names: [name]), timeout: 30)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        let casks = try await Self.parseInstalledCasksDetached(result.stdout)
        return casks.first { $0.token == name || $0.name == name } ?? casks.first
    }

    static func parseInstalledFormulas(_ stdout: String) throws -> [InstalledFormulaInfo] {
        try parseInstalledFormulasSync(stdout)
    }

    static func parseInstalledCasks(_ stdout: String) throws -> [InstalledCaskInfo] {
        try parseInstalledCasksSync(stdout)
    }

    static func parseInstalledFormulasDetached(_ stdout: String) async throws -> [InstalledFormulaInfo] {
        try await Task.detached {
            try parseInstalledFormulasSync(stdout)
        }.value
    }

    static func parseInstalledCasksDetached(_ stdout: String) async throws -> [InstalledCaskInfo] {
        try await Task.detached {
            try parseInstalledCasksSync(stdout)
        }.value
    }

    private static func parseInstalledFormulasSync(_ stdout: String) throws -> [InstalledFormulaInfo] {
        guard let data = stdout.data(using: .utf8) else {
            throw BrewProcessError.parseError("Could not convert output to data")
        }

        let response = try JSONDecoder().decode(InstalledFormulaResponse.self, from: data)
        return (response.formulae ?? []).map { formula in
            let installed = formula.installed?.first
            return InstalledFormulaInfo(
                name: formula.name,
                fullName: formula.full_name ?? formula.name,
                desc: formula.desc,
                homepage: formula.homepage,
                license: formula.license,
                installedVersion: installed?.version ?? "unknown",
                latestVersion: formula.versions?.stable,
                isPinned: formula.pinned ?? false,
                isOutdated: formula.outdated ?? false,
                installedOnRequest: installed?.installed_on_request ?? true,
                installedAsDependency: installed?.installed_as_dependency ?? false
            )
        }
    }

    private static func parseInstalledCasksSync(_ stdout: String) throws -> [InstalledCaskInfo] {
        guard let data = stdout.data(using: .utf8) else {
            throw BrewProcessError.parseError("Could not convert output to data")
        }

        let response = try JSONDecoder().decode(InstalledCaskResponse.self, from: data)
        return (response.casks ?? []).map { cask in
            InstalledCaskInfo(
                token: cask.token,
                fullToken: cask.full_token ?? cask.token,
                name: cask.name?.first ?? cask.token,
                desc: cask.desc,
                homepage: cask.homepage,
                installedVersion: cask.installed ?? cask.version ?? "unknown",
                latestVersion: cask.version,
                isOutdated: cask.outdated ?? false,
                autoUpdates: cask.auto_updates ?? false
            )
        }
    }

    static func parseOutdated(_ stdout: String) throws -> [OutdatedInfo] {
        guard let data = stdout.data(using: .utf8) else {
            throw BrewProcessError.parseError("Could not convert output to data")
        }

        let response = try JSONDecoder().decode(OutdatedResponse.self, from: data)
        var results: [OutdatedInfo] = []

        for formula in response.formulae ?? [] {
            results.append(
                OutdatedInfo(
                    name: formula.name,
                    installedVersion: formula.installed_versions?.first ?? "unknown",
                    latestVersion: formula.current_version ?? "unknown",
                    isPinned: formula.pinned ?? false,
                    itemType: .formula
                )
            )
        }

        for cask in response.casks ?? [] {
            results.append(
                OutdatedInfo(
                    name: cask.name,
                    installedVersion: cask.installed_versions?.first ?? "unknown",
                    latestVersion: cask.current_version ?? "unknown",
                    isPinned: false,
                    itemType: .cask
                )
            )
        }

        return results
    }

    static func parseLineSeparatedNames(_ stdout: String) -> [String] {
        stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private struct InstalledFormulaResponse: Decodable {
        let formulae: [InstalledFormulaJSON]?
    }

    private struct InstalledFormulaJSON: Decodable {
        let name: String
        let full_name: String?
        let desc: String?
        let homepage: String?
        let license: String?
        let pinned: Bool?
        let outdated: Bool?
        let installed: [InstalledVersionJSON]?
        let versions: FormulaVersionsJSON?
    }

    private struct InstalledVersionJSON: Decodable {
        let version: String
        let installed_as_dependency: Bool?
        let installed_on_request: Bool?
    }

    private struct FormulaVersionsJSON: Decodable {
        let stable: String?
    }

    private struct InstalledCaskResponse: Decodable {
        let casks: [InstalledCaskJSON]?
    }

    private struct InstalledCaskJSON: Decodable {
        let token: String
        let full_token: String?
        let name: [String]?
        let desc: String?
        let homepage: String?
        let version: String?
        let installed: String?
        let outdated: Bool?
        let auto_updates: Bool?
    }

    private struct OutdatedResponse: Decodable {
        let formulae: [OutdatedFormula]?
        let casks: [OutdatedCask]?
    }

    private struct OutdatedFormula: Decodable {
        let name: String
        let installed_versions: [String]?
        let current_version: String?
        let pinned: Bool?
    }

    private struct OutdatedCask: Decodable {
        let name: String
        let installed_versions: FlexibleStringList?
        let current_version: String?
    }

    // MARK: - Package Operations

    func install(name: String, isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        let args = try BrewArguments.package("install", name: name, isCask: isCask)
        return try await run(args, timeout: 600, onOutput: onOutput)
    }

    func uninstall(name: String, isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        let args = try BrewArguments.package("uninstall", name: name, isCask: isCask)
        return try await run(args, timeout: 120, onOutput: onOutput)
    }

    func upgrade(name: String? = nil, isCask: Bool = false,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        let args = try BrewArguments.named(
            ["upgrade"], options: isCask ? ["--cask"] : [], names: name.map { [$0] } ?? [])
        return try await run(args, timeout: 600, onOutput: onOutput)
    }

    /// Upgrades the given formulae/casks in one brew invocation; an empty list upgrades everything.
    func upgrade(names: [String],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        return try await run(
            try BrewArguments.named(["upgrade"], names: names), timeout: 1800, onOutput: onOutput)
    }

    func reinstall(name: String, isCask: Bool,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        let args = try BrewArguments.package("reinstall", name: name, isCask: isCask)
        return try await run(args, timeout: 600, onOutput: onOutput)
    }

    func pin(name: String) async throws -> ProcessResult {
        return try await run(try BrewArguments.named(["pin"], names: [name]), timeout: 30)
    }

    func unpin(name: String) async throws -> ProcessResult {
        return try await run(try BrewArguments.named(["unpin"], names: [name]), timeout: 30)
    }

    // MARK: - Reverse Dependencies

    func reverseDependencies(name: String, installed: Bool = false) async throws -> [String] {
        let args = try BrewArguments.named(
            ["uses"], options: installed ? ["--installed"] : [], names: [name])
        let result = try await run(args, timeout: 30)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Services

    func listServices() async throws -> [BrewServiceInfo] {
        // The table output has a variable number of columns (error rows add an
        // exit-code column), so whitespace splitting mis-assigned user/file. JSON is stable.
        let result = try await run(["services", "list", "--json"], timeout: 30)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        struct ServiceJSON: Decodable {
            let name: String
            let status: String
            let user: String?
            let file: String?
            let exit_code: Int?
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw BrewProcessError.parseError("Could not convert output to data")
        }
        let entries = try JSONDecoder().decode([ServiceJSON].self, from: data)

        return entries.map { entry in
            let status: BrewServiceInfo.Status
            switch entry.status.lowercased() {
            case "started", "scheduled": status = .started
            case "stopped", "none": status = .stopped
            case "error": status = .error
            default: status = .unknown
            }
            return BrewServiceInfo(
                name: entry.name, status: status, user: entry.user, file: entry.file,
                exitCode: entry.exit_code)
        }
    }

    func startService(name: String) async throws -> ProcessResult {
        return try await run(try BrewArguments.service("start", name: name), timeout: 30)
    }

    func stopService(name: String) async throws -> ProcessResult {
        return try await run(try BrewArguments.service("stop", name: name), timeout: 30)
    }

    func restartService(name: String) async throws -> ProcessResult {
        return try await run(try BrewArguments.service("restart", name: name), timeout: 30)
    }

    // MARK: - Taps

    func listTaps() async throws -> [BrewTapInfo] {
        let result = try await run(["tap-info", "--installed", "--json"], timeout: 60)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return try await Self.decodeInstalledTaps(from: result.stdout)
    }

    private struct TapJSON: Decodable, Sendable {
        let name: String
        let remote: String?
        let installed: Bool?
        let official: Bool?
        let formula_names: [String]?
        let cask_tokens: [String]?
    }

    private static func decodeInstalledTaps(from stdout: String) async throws -> [BrewTapInfo] {
        try await Task.detached {
            guard let data = stdout.data(using: .utf8) else {
                throw BrewProcessError.parseError("Could not convert output to data")
            }
            let taps = try JSONDecoder().decode([TapJSON].self, from: data)
            return taps.map { t in
                BrewTapInfo(
                    name: t.name,
                    remote: t.remote,
                    isOfficial: t.official ?? t.name.hasPrefix("homebrew/"),
                    formulaCount: t.formula_names?.count ?? 0,
                    caskCount: t.cask_tokens?.count ?? 0,
                    isInstalled: t.installed ?? true
                )
            }
        }.value
    }

    func addTap(name: String,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        return try await run(try BrewArguments.tap("tap", name: name), timeout: 120, onOutput: onOutput)
    }

    func removeTap(name: String) async throws -> ProcessResult {
        return try await run(try BrewArguments.tap("untap", name: name), timeout: 30)
    }

    // MARK: - Maintenance

    func doctor() async throws -> ProcessResult {
        return try await run(["doctor"], timeout: 120)
    }

    func cleanupDryRun() async throws -> ProcessResult {
        return try await run(["cleanup", "--dry-run"], timeout: 60)
    }

    func cleanup(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        return try await run(["cleanup"], timeout: 120, onOutput: onOutput)
    }

    func autoremoveDryRun() async throws -> ProcessResult {
        return try await run(["autoremove", "--dry-run"], timeout: 60)
    }

    func autoremove(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        return try await run(["autoremove"], timeout: 60, onOutput: onOutput)
    }

    func brewInfo() async throws -> BrewEnvironmentInfo {
        let result = try await run(["config"], timeout: 30)
        guard result.exitCode == 0 else {
            throw BrewProcessError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        var info = BrewEnvironmentInfo()
        for line in result.stdout.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "HOMEBREW_VERSION": info.version = parts[1]
            case "HOMEBREW_PREFIX": info.prefix = parts[1]
            case "HOMEBREW_CELLAR": info.cellar = parts[1]
            case "HOMEBREW_CASK_OPTS": info.caskOpts = parts[1]
            case "CPU": info.cpu = parts[1]
            case "macOS": info.macOS = parts[1]
            default: break
            }
        }
        return info
    }
}

// MARK: - Supporting Types

struct BrewServiceInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let status: Status
    let user: String?
    let file: String?
    /// Last exit code reported by launchd; non-nil only for services in the error state.
    let exitCode: Int?

    enum Status: String, Sendable {
        case started, stopped, error, unknown
    }
}

struct BrewTapInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let remote: String?
    let isOfficial: Bool
    let formulaCount: Int
    let caskCount: Int
    let isInstalled: Bool
}

/// Why this service terminated a process, set by the timeout and by `onCancel` when the
/// calling task is cancelled, and read after exit to choose the error to report.
private final class TerminationCause: @unchecked Sendable {
    enum Reason { case timeout, cancelled }

    private let lock = NSLock()
    private var recorded: Reason?

    var reason: Reason? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Keeps the first reason, so a timeout firing after a cancel doesn't overwrite it.
    func record(_ reason: Reason) {
        lock.lock()
        defer { lock.unlock() }
        if recorded == nil { recorded = reason }
    }
}

/// Decodes a stream of pipe reads as UTF-8 without losing a character split across two
/// reads: the bytes of an unfinished character wait for the read that completes them.
/// Invalid bytes become U+FFFD rather than dropping the read they arrived in.
final class UTF8ChunkDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var carry = Data()

    func decode(_ data: Data) -> String {
        lock.lock()
        defer { lock.unlock() }
        var bytes = carry + data
        let held = Self.unfinishedSuffixLength(bytes)
        carry = Data(bytes.suffix(held))
        bytes.removeLast(held)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Decodes whatever is still waiting; call once the stream has ended.
    func finish() -> String {
        lock.lock()
        defer { lock.unlock() }
        let rest = carry
        carry = Data()
        return String(decoding: rest, as: UTF8.self)
    }

    /// Bytes at the end of `bytes` that start a character still missing its last bytes.
    static func unfinishedSuffixLength(_ bytes: Data) -> Int {
        var seen = 0
        for byte in bytes.reversed().prefix(3) {
            seen += 1
            if byte & 0b1100_0000 == 0b1000_0000 { continue }
            let length: Int
            switch byte {
            case 0xC2...0xDF: length = 2
            case 0xE0...0xEF: length = 3
            case 0xF0...0xF4: length = 4
            default: return 0
            }
            return length > seen ? seen : 0
        }
        return 0
    }
}

private final class ProcessResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<ProcessResult, Error>

    init(continuation: CheckedContinuation<ProcessResult, Error>) {
        self.continuation = continuation
    }

    func resumeOnce(with result: Result<ProcessResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

actor OutputCollector {
    enum Stream: Sendable { case stdout, stderr }

    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    func append(_ chunk: String, to stream: Stream) {
        switch stream {
        case .stdout: stdoutBuffer += chunk
        case .stderr: stderrBuffer += chunk
        }
    }

    func snapshot() -> (stdout: String, stderr: String) {
        (stdoutBuffer, stderrBuffer)
    }

    func getStdout() -> String { stdoutBuffer }
    func getStderr() -> String { stderrBuffer }
}

struct BrewEnvironmentInfo: Sendable {
    var version: String = "unknown"
    var prefix: String = ""
    var cellar: String = ""
    var caskOpts: String = ""
    var cpu: String = ""
    var macOS: String = ""
}
