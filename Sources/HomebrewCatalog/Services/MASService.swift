import Foundation

// MARK: - MAS App Info

struct MASAppInfo: Identifiable, Sendable, Hashable {
    var id: String { "\(appID)" }
    let appID: Int
    let name: String
    let currentVersion: String
    let availableVersion: String?
    var isOutdated: Bool { availableVersion != nil && availableVersion != currentVersion }
}

// MARK: - MAS Service

actor MASService {
    static let shared = MASService()

    private var masPath: String?

    func isAvailable() -> Bool {
        if let cached = masPath {
            return FileManager.default.isExecutableFile(atPath: cached)
        }
        let candidates = ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                masPath = path
                return true
            }
        }
        return false
    }

    private func runMAS(_ arguments: [String], timeout: TimeInterval = 30) async throws -> String {
        guard let path = masPath else {
            throw MASError.masNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Same pattern as BrewProcessService.runRaw: never block the actor with
        // waitUntilExit(), drain both pipes while the process runs, honour the
        // timeout, and surface a non-zero exit code (e.g. `mas upgrade` needing
        // root) instead of returning an empty string.
        let collector = MASPipeOutput()
        let readGroup = DispatchGroup()
        readGroup.enter()
        readGroup.enter()

        return try await withCheckedThrowingContinuation { continuation in
            // DispatchWorkItem isn't Sendable; it is only ever cancelled from the handler.
            nonisolated(unsafe) let timeoutTask = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()
                readGroup.notify(queue: .global()) {
                    let stdout = collector.stdout
                    let stderr = collector.stderr
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: MASError.timeout)
                    } else if proc.terminationStatus != 0 {
                        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(
                            throwing: MASError.commandFailed(
                                message.isEmpty ? stdout.trimmingCharacters(in: .whitespacesAndNewlines) : message))
                    } else {
                        continuation.resume(returning: stdout)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                process.terminationHandler = nil
                continuation.resume(throwing: MASError.commandFailed(error.localizedDescription))
                return
            }

            DispatchQueue.global().async {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                collector.stdout = String(data: data, encoding: .utf8) ?? ""
                readGroup.leave()
            }
            DispatchQueue.global().async {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                collector.stderr = String(data: data, encoding: .utf8) ?? ""
                readGroup.leave()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
        }
    }

    func listInstalled() async throws -> [MASAppInfo] {
        Self.parseInstalled(try await runMAS(["list"]))
    }

    /// Parses `mas list` output; static so malformed lines can be unit-tested.
    static func parseInstalled(_ output: String) -> [MASAppInfo] {
        var apps: [MASAppInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Format: "123456789  App Name  (1.2.3)"
            let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true) {
                $0 == " " || $0 == "\t"
            }
            guard parts.count >= 2, let appID = Int(parts[0]) else { continue }

            let rest = String(parts[1])
            var name = rest
            var version = "unknown"

            // "(" must come before ")"; otherwise the slice below traps (BUG-03).
            if let parenRange = rest.range(of: "(", options: .backwards),
                let closeRange = rest.range(of: ")", options: .backwards),
                parenRange.upperBound <= closeRange.lowerBound
            {
                version = String(rest[parenRange.upperBound..<closeRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                name = String(rest[..<parenRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            }

            apps.append(
                MASAppInfo(
                    appID: appID,
                    name: name,
                    currentVersion: version,
                    availableVersion: nil
                ))
        }
        return apps
    }

    func listOutdated() async throws -> [MASAppInfo] {
        Self.parseOutdated(try await runMAS(["outdated"]))
    }

    /// Parses `mas outdated` output; static so malformed lines can be unit-tested.
    static func parseOutdated(_ output: String) -> [MASAppInfo] {
        var apps: [MASAppInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Format: "123456789  App Name  (1.2.3 -> 1.3.0)"
            let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true) {
                $0 == " " || $0 == "\t"
            }
            guard parts.count >= 2, let appID = Int(parts[0]) else { continue }

            let rest = String(parts[1])
            var name = rest
            var currentVer = "unknown"
            var availableVer: String? = nil

            // "(" must come before ")"; otherwise the slice below traps (BUG-03).
            if let parenRange = rest.range(of: "(", options: .backwards),
                let closeRange = rest.range(of: ")", options: .backwards),
                parenRange.upperBound <= closeRange.lowerBound
            {
                let versionStr = String(rest[parenRange.upperBound..<closeRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                name = String(rest[..<parenRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)

                let vParts = versionStr.components(separatedBy: "->").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if vParts.count >= 2 {
                    currentVer = vParts[0]
                    availableVer = vParts[1]
                } else {
                    currentVer = versionStr
                }
            }

            apps.append(
                MASAppInfo(
                    appID: appID,
                    name: name,
                    currentVersion: currentVer,
                    availableVersion: availableVer
                ))
        }
        return apps
    }

    func upgrade(appID: Int) async throws -> String {
        return try await runMAS(["upgrade", "\(appID)"])
    }

    func upgradeAll() async throws -> String {
        return try await runMAS(["upgrade"])
    }

    func search(query: String) async throws -> [MASAppInfo] {
        guard BrewArgumentValidator.isValid(query, as: .masQuery) else {
            throw MASError.invalidQuery
        }
        let output = try await runMAS(["search", query])
        var results: [MASAppInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true) {
                $0 == " " || $0 == "\t"
            }
            guard parts.count >= 2, let appID = Int(parts[0]) else { continue }
            let name = String(parts[1]).trimmingCharacters(in: .whitespaces)

            results.append(
                MASAppInfo(
                    appID: appID,
                    name: name,
                    currentVersion: "",
                    availableVersion: nil
                ))
        }
        return results
    }
}

enum MASError: Error, LocalizedError {
    case masNotInstalled
    case commandFailed(String)
    case timeout
    /// The search text would be read by mas as an option, or is not printable text.
    case invalidQuery

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Search text cannot start with \"-\" or contain control characters."
        case .masNotInstalled:
            return "mas is not installed. Install it with: brew install mas"
        case .commandFailed(let output):
            return "mas command failed: \(output)"
        case .timeout:
            return "mas command timed out."
        }
    }
}

/// Filled by the two pipe readers in `runMAS` and read only after `readGroup`
/// notifies, so the group orders every access and no lock is needed.
private final class MASPipeOutput: @unchecked Sendable {
    var stdout = ""
    var stderr = ""
}
